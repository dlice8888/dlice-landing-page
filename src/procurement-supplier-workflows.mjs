/**
 * Supplier contract pricing, multi-branch demand consolidation and returns.
 * All mutable workflows require trusted tenant transactions and adapters.
 */
const fail = (code, message) => { const error = new Error(message); error.code = code; throw error; };
const required = (v, field) => { if (typeof v !== "string" || !v.trim()) fail("PROCUREMENT_INPUT_REQUIRED", field); return v.trim(); };
const positive = (v, field) => { const n = Number(v); if (!Number.isFinite(n) || n <= 0) fail("PROCUREMENT_QUANTITY_INVALID", field); return n; };
const adapter = (deps, name) => { if (typeof deps?.[name] !== "function") fail("PROCUREMENT_ADAPTER_REQUIRED", name); return deps[name]; };
const scopeOf = (input, action) => ({
  tenantId: required(input?.tenantId, "tenantId"), branchId: required(input?.branchId, "branchId"),
  actorId: required(input?.actorId, "actorId"), idempotencyKey: required(input?.idempotencyKey, "idempotencyKey"), action,
});
const inTransaction = (deps, scope, fn) => adapter(deps, "withTenantTransaction")(scope, async (tx) => {
  if (!tx) fail("PROCUREMENT_TRANSACTION_REQUIRED", "A database transaction is required");
  await adapter(deps, "authorize")(tx, scope);
  return fn(tx);
});
const assertScope = (row, scope, field) => {
  if (!row || row.tenantId !== scope.tenantId || row.branchId !== scope.branchId) fail("PROCUREMENT_SCOPE_MISMATCH", field);
};

/** Select exactly one approved supplier contract price effective for branch/date/quantity. */
export function resolveEffectiveSupplierPrice(input) {
  const tenantId = required(input?.tenantId, "tenantId");
  const supplierId = required(input?.supplierId, "supplierId");
  const itemId = required(input?.itemId, "itemId");
  const branchId = required(input?.branchId, "branchId");
  const date = required(input?.date, "date");
  const quantity = positive(input?.quantity, "quantity");
  const candidates = (input.contracts || []).filter((c) =>
    c.tenantId === tenantId && c.supplierId === supplierId && c.itemId === itemId &&
    c.status === "approved" && c.effectiveFrom <= date && (!c.effectiveTo || c.effectiveTo >= date) &&
    (!c.branchIds || c.branchIds.includes(branchId)) && Number(c.minimumQuantity ?? 0) <= quantity &&
    c.currency === "IDR" && Number.isSafeInteger(c.unitPriceIdr) && c.unitPriceIdr >= 0
  );
  if (!candidates.length) fail("PROCUREMENT_EFFECTIVE_PRICE_NOT_FOUND", "No approved effective supplier price matches this scope");
  candidates.sort((a, b) => Number(b.priority ?? 0) - Number(a.priority ?? 0) ||
    b.effectiveFrom.localeCompare(a.effectiveFrom) || Number(a.unitPriceIdr) - Number(b.unitPriceIdr));
  const best = candidates[0];
  const ambiguous = candidates.filter((c) => Number(c.priority ?? 0) === Number(best.priority ?? 0) &&
    c.effectiveFrom === best.effectiveFrom && c.unitPriceIdr !== best.unitPriceIdr);
  if (ambiguous.length) fail("PROCUREMENT_PRICE_CONTRACT_AMBIGUOUS", "Conflicting approved prices share the same priority and effective date");
  return Object.freeze({ contractId: best.id, supplierId, itemId, branchId, unitPriceIdr: best.unitPriceIdr,
    currency: "IDR", effectiveFrom: best.effectiveFrom, effectiveTo: best.effectiveTo ?? null });
}

/** Aggregate branch demand in one canonical base unit; subtract available stock and open PO. */
export function consolidateBranchDemand(input) {
  const tenantId = required(input?.tenantId, "tenantId");
  if (!Array.isArray(input.rows) || input.rows.length === 0) fail("PROCUREMENT_DEMAND_ROWS_REQUIRED", "At least one branch demand row is required");
  const grouped = new Map();
  for (const row of input.rows) {
    if (row.tenantId !== tenantId || !row.branchId) fail("PROCUREMENT_DEMAND_SCOPE_MISMATCH", "Demand row must belong to the requested tenant and a branch");
    const itemId = required(row.itemId, "itemId");
    const unit = required(row.baseUnit, "baseUnit");
    const key = itemId + "::" + unit;
    const forecast = Number(row.forecastQuantity), onHand = Number(row.onHandQuantity), reserved = Number(row.reservedQuantity ?? 0);
    const openPo = Number(row.openPurchaseOrderQuantity ?? 0), safety = Number(row.safetyStockQuantity ?? 0);
    if ([forecast,onHand,reserved,openPo,safety].some((n) => !Number.isFinite(n) || n < 0) || reserved > onHand) {
      fail("PROCUREMENT_DEMAND_QUANTITY_INVALID", "Demand and inventory quantities must be non-negative and reserved cannot exceed on-hand");
    }
    const net = Math.max(0, forecast + safety - (onHand - reserved) - openPo);
    const current = grouped.get(key) ?? { tenantId, itemId, baseUnit: unit, branchCount: 0, forecastQuantity: 0,
      availableStockQuantity: 0, openPurchaseOrderQuantity: 0, safetyStockQuantity: 0, consolidatedPurchaseQuantity: 0, branches: [] };
    current.branchCount++;
    current.forecastQuantity += forecast;
    current.availableStockQuantity += onHand - reserved;
    current.openPurchaseOrderQuantity += openPo;
    current.safetyStockQuantity += safety;
    current.consolidatedPurchaseQuantity += net;
    current.branches.push(Object.freeze({ branchId: row.branchId, purchaseQuantity: net }));
    grouped.set(key, current);
  }
  return Object.freeze([...grouped.values()].map((row) => {
    const byBranch = new Map();
    for (const branch of row.branches) {
      byBranch.set(branch.branchId, (byBranch.get(branch.branchId) ?? 0) + branch.purchaseQuantity);
    }
    const branches = [...byBranch.entries()].map(([branchId, purchaseQuantity]) =>
      Object.freeze({ branchId, purchaseQuantity: Number(purchaseQuantity.toFixed(6)) }));
    return Object.freeze({ ...row, branchCount: branches.length, branches: Object.freeze(branches),
      consolidatedPurchaseQuantity: Number(row.consolidatedPurchaseQuantity.toFixed(6)) });
  }));
}

/** Request a supplier return against received, not-yet-returned receipt quantity. */
export async function requestSupplierReturn(input, deps) {
  const scope = scopeOf(input, "procurement.supplier_return.request");
  const receiptLineId = required(input.receiptLineId, "receiptLineId");
  const quantity = positive(input.quantity, "quantity");
  const reason = required(input.reason, "reason");
  return inTransaction(deps, scope, async (tx) => {
    const prior = await adapter(deps, "findSupplierReturnByIdempotencyKey")(tx, scope);
    if (prior) return Object.freeze({ status: "duplicate", returnId: prior.id });
    const line = await adapter(deps, "loadSupplierReceiptLineForUpdate")(tx, { ...scope, receiptLineId });
    assertScope(line, scope, "receiptLine");
    const available = Number(line.receivedQuantity) - Number(line.previouslyReturnedQuantity ?? 0);
    if (!Number.isFinite(available) || available < 0 || quantity > available) {
      fail("PROCUREMENT_RETURN_QUANTITY_EXCEEDS_RECEIPT", "Return quantity exceeds the unreturned received quantity");
    }
    const unitPrice = Number(line.approvedUnitPriceIdr);
    if (!Number.isSafeInteger(unitPrice) || unitPrice < 0) fail("PROCUREMENT_RETURN_PRICE_NOT_RECONCILED", "Approved receipt price is required");
    const saved = await adapter(deps, "persistSupplierReturnRequest")(tx, {
      ...scope, receiptLineId, quantity, reason, creditAmountIdr: Math.round(quantity * unitPrice), status: "pending_approval",
    });
    if (!saved?.id) fail("PROCUREMENT_RETURN_PERSIST_FAILED", "Supplier return request was not persisted");
    await adapter(deps, "appendAudit")(tx, { ...scope, action: "procurement.supplier_return.requested",
      entityType: "supplier_return", entityId: saved.id, metadata: { quantity, creditAmountIdr: Math.round(quantity * unitPrice) } });
    return Object.freeze({ status: "pending_approval", returnId: saved.id, creditAmountIdr: Math.round(quantity * unitPrice) });
  });
}

/** Independent approval posts stock reversal and AP credit evidence in the same transaction. */
export async function approveSupplierReturn(input, deps) {
  const scope = scopeOf(input, "procurement.supplier_return.approve");
  const returnId = required(input.returnId, "returnId");
  const creditNoteReference = required(input.creditNoteReference, "creditNoteReference");
  return inTransaction(deps, scope, async (tx) => {
    const request = await adapter(deps, "loadSupplierReturnForUpdate")(tx, { ...scope, returnId });
    assertScope(request, scope, "supplierReturn");
    if (request.status !== "pending_approval") fail("PROCUREMENT_RETURN_NOT_PENDING", "Only pending returns may be approved");
    if (request.requestedBy === scope.actorId) fail("PROCUREMENT_RETURN_SELF_APPROVAL_DENIED", "Requester cannot approve their own supplier return");
    const approved = await adapter(deps, "approveSupplierReturn")(tx, { ...scope, returnId, creditNoteReference });
    if (!approved?.approved) fail("PROCUREMENT_RETURN_APPROVAL_FAILED", "Independent approval was not persisted");
    const stock = await adapter(deps, "postSupplierReturnStockMovement")(tx, { ...scope, returnId });
    const credit = await adapter(deps, "postSupplierCreditNoteToAp")(tx, { ...scope, returnId, creditNoteReference });
    if (!stock?.movementId || !credit?.journalId || credit.status !== "posted") {
      fail("PROCUREMENT_RETURN_RECONCILIATION_FAILED", "Stock reversal and AP credit note must both post atomically");
    }
    await adapter(deps, "appendAudit")(tx, { ...scope, action: "procurement.supplier_return.approved",
      entityType: "supplier_return", entityId: returnId, metadata: { stockMovementId: stock.movementId, apJournalId: credit.journalId } });
    return Object.freeze({ status: "approved", returnId, stockMovementId: stock.movementId, apJournalId: credit.journalId });
  });
}
