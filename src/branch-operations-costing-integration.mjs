/**
 * Cross-domain Branch Operations cost close.
 *
 * This is a server-side orchestration boundary. All adapters must use the
 * supplied transaction; callers must never accept client-calculated costs.
 * Inventory valuation, approved GRNs, HR labour and Finance journals remain
 * authoritative source ledgers.
 */
const fail = (code, message) => { const error = new Error(message); error.code = code; throw error; };
const required = (value, field) => {
  if (typeof value !== "string" || !value.trim()) fail("BRANCH_COST_INPUT_REQUIRED", field);
  return value.trim();
};
const adapter = (deps, name) => {
  if (typeof deps?.[name] !== "function") fail("BRANCH_COST_ADAPTER_REQUIRED", name);
  return deps[name];
};
const positiveIdr = (value, field) => {
  if (!Number.isSafeInteger(value) || value < 0) fail("BRANCH_COST_AMOUNT_INVALID", field);
  return value;
};
const sameScope = (row, scope, field) => {
  if (!row || row.tenantId !== scope.tenantId || row.branchId !== scope.branchId) {
    fail("BRANCH_COST_SCOPE_MISMATCH", field);
  }
};
const sum = (rows, pick, field) => rows.reduce((total, row) => {
  const amount = positiveIdr(pick(row), field);
  const next = total + amount;
  if (!Number.isSafeInteger(next)) fail("BRANCH_COST_AMOUNT_OVERFLOW", field);
  return next;
}, 0);

/**
 * Close actual maintenance cost from persisted, approved source records.
 *
 * Required adapters (all receive tx): authorize, loadWorkOrderForUpdate,
 * findCostCloseByIdempotencyKey, loadInventoryIssuesForWorkOrder,
 * loadApprovedProcurementReceipts, loadApprovedLabourEntries,
 * persistMaintenanceCostClose, postMaintenanceFinanceJournal,
 * verifyPostedBalancedJournal, appendAudit.
 */
export async function closeBranchMaintenanceCost(input, deps) {
  const scope = Object.freeze({
    tenantId: required(input?.tenantId, "tenantId"),
    branchId: required(input?.branchId, "branchId"),
    actorId: required(input?.actorId, "actorId"),
    workOrderId: required(input?.workOrderId, "workOrderId"),
    idempotencyKey: required(input?.idempotencyKey, "idempotencyKey"),
    action: "branch.maintenance.cost.close",
  });
  return adapter(deps, "withTenantTransaction")(scope, async (tx) => {
    if (!tx) fail("BRANCH_COST_TRANSACTION_REQUIRED", "A database transaction is required");
    await adapter(deps, "authorize")(tx, scope);

    const prior = await adapter(deps, "findCostCloseByIdempotencyKey")(tx, scope);
    if (prior) return Object.freeze({ status: "duplicate", costCloseId: prior.id, journalId: prior.journalId });

    const workOrder = await adapter(deps, "loadWorkOrderForUpdate")(tx, scope);
    sameScope(workOrder, scope, "workOrder");
    if (!["completed", "awaiting_cost_close"].includes(workOrder.status)) {
      fail("BRANCH_COST_WORK_ORDER_NOT_READY", "Work order must be completed before cost close");
    }
    if (workOrder.costCloseStatus === "closed") {
      fail("BRANCH_COST_ALREADY_CLOSED", "Work order already has a cost close");
    }

    const [issues, receipts, labour] = await Promise.all([
      adapter(deps, "loadInventoryIssuesForWorkOrder")(tx, scope),
      adapter(deps, "loadApprovedProcurementReceipts")(tx, scope),
      adapter(deps, "loadApprovedLabourEntries")(tx, scope),
    ]);
    for (const [rows, name] of [[issues, "inventoryIssues"], [receipts, "procurementReceipts"], [labour, "labourEntries"]]) {
      if (!Array.isArray(rows)) fail("BRANCH_COST_SOURCE_INVALID", name);
      for (const row of rows) sameScope(row, scope, name);
    }

    // Every stock issue must be valued and linked to an approved GRN or an
    // approved opening/transfer valuation. No current-price lookup is allowed.
    for (const issue of issues) {
      if (issue.reconciled !== true || !["approved_grn", "approved_transfer", "approved_opening"].includes(issue.valuationSource)) {
        fail("BRANCH_COST_INVENTORY_UNRECONCILED", "Inventory issue needs reconciled historical valuation");
      }
      positiveIdr(issue.extendedCostIdr, "inventory.extendedCostIdr");
      if (issue.valuationSource === "approved_grn" && !receipts.some((receipt) =>
        receipt.id === issue.receiptId && receipt.status === "approved" && receipt.reconciled === true)) {
        fail("BRANCH_COST_GRN_EVIDENCE_MISSING", "Inventory issue is not backed by an approved reconciled GRN");
      }
    }
    for (const entry of labour) {
      if (entry.approvalStatus !== "approved" || entry.reconciled !== true) {
        fail("BRANCH_COST_LABOUR_UNAPPROVED", "Labour entries must be approved and reconciled");
      }
      positiveIdr(entry.costIdr, "labour.costIdr");
    }
    for (const receipt of receipts) {
      if (receipt.status !== "approved" || receipt.reconciled !== true) {
        fail("BRANCH_COST_PROCUREMENT_UNRECONCILED", "Procurement receipt must be approved and reconciled");
      }
    }

    const inventoryCostIdr = sum(issues, (row) => row.extendedCostIdr, "inventory.extendedCostIdr");
    const labourCostIdr = sum(labour, (row) => row.costIdr, "labour.costIdr");
    const externalCostIdr = positiveIdr(workOrder.approvedExternalCostIdr ?? 0, "workOrder.approvedExternalCostIdr");
    const totalCostIdr = inventoryCostIdr + labourCostIdr + externalCostIdr;
    if (!Number.isSafeInteger(totalCostIdr)) fail("BRANCH_COST_AMOUNT_OVERFLOW", "totalCostIdr");

    const costClose = await adapter(deps, "persistMaintenanceCostClose")(tx, {
      ...scope, currency: "IDR", inventoryCostIdr, labourCostIdr, externalCostIdr, totalCostIdr,
      inventoryIssueIds: issues.map((row) => row.id),
      procurementReceiptIds: receipts.map((row) => row.id),
      labourEntryIds: labour.map((row) => row.id),
      sourceRevision: required(await adapter(deps, "computeSourceRevision")(tx, scope, { issues, receipts, labour }), "sourceRevision"),
    });
    if (!costClose?.id) fail("BRANCH_COST_PERSIST_FAILED", "Cost close was not persisted");

    const journal = await adapter(deps, "postMaintenanceFinanceJournal")(tx, {
      ...scope, costCloseId: costClose.id, currency: "IDR",
      inventoryCostIdr, labourCostIdr, externalCostIdr, totalCostIdr,
    });
    if (!journal?.id) fail("BRANCH_COST_FINANCE_POST_FAILED", "Finance journal was not posted");
    const verified = await adapter(deps, "verifyPostedBalancedJournal")(tx, {
      ...scope, journalId: journal.id, expectedDebitIdr: totalCostIdr, expectedCreditIdr: totalCostIdr,
    });
    if (verified !== true) fail("BRANCH_COST_FINANCE_UNRECONCILED", "Finance journal must be posted, balanced and independently verified");

    await adapter(deps, "appendAudit")(tx, {
      ...scope, action: "branch.maintenance.cost.closed", entityType: "branch_ops_cost_closes",
      entityId: costClose.id, metadata: { journalId: journal.id, inventoryCostIdr, labourCostIdr, externalCostIdr, totalCostIdr },
    });
    return Object.freeze({ status: "closed", costCloseId: costClose.id, journalId: journal.id, totalCostIdr });
  });
}
