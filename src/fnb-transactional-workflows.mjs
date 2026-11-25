/**
 * Transactional orchestration ports for the eight priority FnB OS domains.
 *
 * These services are server-side application boundaries. They require trusted
 * actor scope, authorization inside the transaction, tenant-scoped repository
 * adapters, durable idempotency, and append-only audit adapters. They never
 * accept client-supplied financial evidence or service-role credentials.
 *
 * Database-specific adapters are intentionally injected: the staging schema
 * has not yet been migrated to the proposed domain tables. A missing adapter
 * fails closed instead of silently degrading to an in-memory implementation.
 */
import { calculateEligibleLoyaltyAward } from "./crm-eligible-net-sales.mjs";
import { buildPayrollFinanceJournalBatch } from "./hr-payroll-finance-batch.mjs";
import { verifyDeliveryWebhook, deliveryWebhookEventDecision } from "./delivery-webhook-verification.mjs";
import { recordUsageAfterAuthoritativeCommit } from "./saas-post-commit-metering.mjs";
import { reconcileSupplierPayment } from "./procurement-ap-settlement.mjs";
import { verifyExecutiveFinanceKpi } from "./executive-finance-kpi.mjs";

const fail = (code, message) => {
  const error = new Error(message);
  error.code = code;
  throw error;
};
const required = (value, field) => {
  if (typeof value !== "string" || !value.trim()) fail("WORKFLOW_INPUT_REQUIRED", field);
  return value.trim();
};
const adapter = (deps, name) => {
  if (typeof deps?.[name] !== "function") fail("WORKFLOW_ADAPTER_REQUIRED", name);
  return deps[name];
};
const scopeOf = (input) => ({
  tenantId: required(input?.tenantId, "tenantId"),
  branchId: input?.branchId == null ? null : required(input.branchId, "branchId"),
  actorId: required(input?.actorId, "actorId"),
  idempotencyKey: required(input?.idempotencyKey, "idempotencyKey"),
});
async function inTenantTransaction(deps, scope, operation) {
  const withTransaction = adapter(deps, "withTenantTransaction");
  return withTransaction(scope, async (tx) => {
    if (!tx) fail("TRANSACTION_CONTEXT_REQUIRED", "Repository transaction context is required");
    await adapter(deps, "authorize")(tx, {
      actorId: scope.actorId, tenantId: scope.tenantId,
      branchId: scope.branchId, action: scope.action,
    });
    return operation(tx);
  });
}
async function audit(deps, tx, event) {
  await adapter(deps, "appendAudit")(tx, Object.freeze(event));
}
function assertScope(record, scope, field) {
  if (!record || record.tenantId !== scope.tenantId ||
      (scope.branchId && record.branchId !== scope.branchId)) {
    fail("WORKFLOW_SCOPE_MISMATCH", field);
  }
}

/**
 * CRM: create the earning ledger row and balance projection atomically after
 * loading a server-built close projection from authoritative source records.
 */
export async function awardLoyaltyForFinancialClose(input, deps) {
  const scope = { ...scopeOf(input), action: "crm.loyalty.award" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const close = await adapter(deps, "loadFinancialCloseForUpdate")(tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, sourceType: input.sourceType,
      sourceId: required(input.sourceId, "sourceId"),
    });
    assertScope(close, scope, "financialClose");
    const rule = await adapter(deps, "loadApprovedEarningRule")(tx, scope.tenantId);
    const award = calculateEligibleLoyaltyAward(close, rule);
    const existing = await adapter(deps, "findLoyaltyAwardByIdempotencyKey")(tx, award.idempotencyKey);
    if (existing) return Object.freeze({ status: "duplicate", awardId: existing.id, idempotencyKey: award.idempotencyKey });
    const customer = await adapter(deps, "resolveSourceCustomerIdentity")(tx, {
      tenantId: scope.tenantId, branchId: scope.branchId,
      sourceType: award.sourceType, sourceId: award.sourceId,
    });
    if (!customer?.id || customer.tenantId !== scope.tenantId) fail("SOURCE_CUSTOMER_IDENTITY_UNRESOLVED", "POS/order source must resolve to a tenant customer");
    const inserted = await adapter(deps, "insertLoyaltyAwardAndUpdateBalance")(tx, {
      ...award, customerId: customer.id, actorId: scope.actorId,
      idempotencyKey: award.idempotencyKey,
    });
    if (!inserted?.awardId) fail("LOYALTY_LEDGER_INSERT_FAILED", "Atomic award ledger write did not return an id");
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "crm.loyalty.awarded", entityType: "loyalty_award",
      entityId: inserted.awardId, idempotencyKey: award.idempotencyKey });
    return Object.freeze({ status: "awarded", awardId: inserted.awardId, points: award.points, idempotencyKey: award.idempotencyKey });
  });
}

/** HR: persist an immutable approved payroll run and balanced Finance batch. */
export async function persistApprovedPayrollRun(input, deps) {
  const scope = { ...scopeOf(input), action: "hr.payroll.post" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const run = await adapter(deps, "loadPayrollRunForUpdate")(tx, input.payrollRunId);
    assertScope(run, scope, "payrollRun");
    if (run.status !== "approved") fail("PAYROLL_RUN_NOT_APPROVED", "Payroll run must be approved before posting");
    const period = await adapter(deps, "loadFiscalPeriodForUpdate")(tx, run.periodStart, run.periodEnd);
    if (!period || period.status !== "open" || period.startsOn > run.periodStart || period.endsOn < run.periodEnd) {
      fail("FISCAL_PERIOD_NOT_OPEN", "Payroll period must be covered by an open fiscal period");
    }
    const existing = await adapter(deps, "findPayrollJournalByIdempotencyKey")(tx, scope.idempotencyKey);
    if (existing) return Object.freeze({ status: "duplicate", batchId: existing.batchId });
    const lines = await adapter(deps, "loadImmutableApprovedPayrollLines")(tx, run.id);
    const mapping = await adapter(deps, "loadApprovedPayrollAccountMapping")(tx, scope.tenantId, scope.branchId);
    const batch = buildPayrollFinanceJournalBatch({
      payrollRun: run, payrollLines: lines, accountMapping: mapping,
      idempotencyKey: scope.idempotencyKey,
    });
    const persisted = await adapter(deps, "insertPayrollFinanceBatch")(tx, {
      run, batch, fiscalPeriodId: period.id, actorId: scope.actorId,
    });
    if (!persisted?.batchId || persisted.status !== "draft") fail("PAYROLL_BATCH_PERSIST_FAILED", "Finance batch must persist as draft");
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "hr.payroll.finance_batch_created",
      entityType: "finance_journal_batch", entityId: persisted.batchId,
      idempotencyKey: scope.idempotencyKey });
    return Object.freeze({ status: "draft", batchId: persisted.batchId,
      debitTotalIdr: batch.debitTotalIdr, creditTotalIdr: batch.creditTotalIdr,
      requiresIndependentApproval: true });
  });
}

/**
 * Delivery: verify the provider signature over raw bytes before opening a
 * transaction; dedupe and apply the event under a tenant-scoped transaction.
 */
export async function ingestSignedDeliveryWebhook(input, deps) {
  const verified = await verifyDeliveryWebhook({
    rawBody: input.rawBody, signature: input.signature, timestamp: input.timestamp,
    secret: adapter(deps, "getProviderWebhookSecret")(input.providerId),
    nowMs: input.nowMs, maxSkewSeconds: input.maxSkewSeconds,
  });
  const scope = { tenantId: required(input.tenantId, "tenantId"),
    branchId: input.branchId == null ? null : required(input.branchId, "branchId"),
    actorId: "system:delivery-webhook", idempotencyKey: verified.eventId,
    action: "delivery.webhook.ingest" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const dispatch = await adapter(deps, "loadDispatchForUpdate")(tx, verified.dispatchId);
    assertScope(dispatch, scope, "dispatch");
    const existing = await adapter(deps, "findDeliveryProviderEvent")(tx, input.providerId, verified.eventId);
    const decision = deliveryWebhookEventDecision({
      eventId: verified.eventId, bodySha256: verified.bodySha256,
      existingEvent: existing && { id: existing.id, bodySha256: existing.bodySha256 },
    });
    if (decision.action === "ack_duplicate") return Object.freeze({ status: "duplicate", eventId: verified.eventId });
    const result = await adapter(deps, "insertAndApplyDeliveryEvent")(tx, {
      dispatch, providerId: input.providerId, verified, actorId: scope.actorId,
    });
    if (!result?.eventId || !result?.dispatchStatus) fail("DELIVERY_EVENT_APPLY_FAILED", "Provider event was not durably applied");
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "delivery.provider_event.applied",
      entityType: "delivery_provider_event", entityId: result.eventId,
      idempotencyKey: verified.eventId });
    return Object.freeze({ status: "applied", eventId: result.eventId, dispatchStatus: result.dispatchStatus });
  });
}

/** Franchise: reserve territory and provision tenant/branch only after all gates. */
export async function provisionApprovedFranchise(input, deps) {
  const scope = { ...scopeOf(input), action: "franchise.provision" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const application = await adapter(deps, "loadFranchiseApplicationForUpdate")(tx, input.applicationId);
    assertScope(application, scope, "franchiseApplication");
    if (application.status !== "approved" || !application.contract?.signed ||
        !application.contract?.version || !application.contract?.effectiveAt) {
      fail("SIGNED_EFFECTIVE_FRANCHISE_CONTRACT_REQUIRED", "Approved application and effective signed contract are required");
    }
    const gates = await adapter(deps, "loadFranchiseOpeningGates")(tx, application.id);
    if (!Array.isArray(gates) || gates.length !== 10 || gates.some(g => g.status !== "passed" || !g.verifiedBy || !g.verifiedAt)) {
      fail("TEN_OPENING_GATES_NOT_INDEPENDENTLY_VERIFIED", "All ten opening gates need independent verification");
    }
    const conflict = await adapter(deps, "checkTerritoryConflict")(tx, application.proposedTerritory);
    if (conflict?.conflict) fail("FRANCHISE_TERRITORY_CONFLICT", "Proposed territory conflicts with an active reservation or franchise");
    const prior = await adapter(deps, "findFranchiseProvisioningByIdempotencyKey")(tx, scope.idempotencyKey);
    if (prior) return Object.freeze({ status: "duplicate", tenantId: prior.tenantId, branchId: prior.branchId });
    const created = await adapter(deps, "provisionTenantAndBranchAtomically")(tx, {
      application, contractVersion: application.contract.version, actorId: scope.actorId,
    });
    if (!created?.tenantId || !created?.branchId) fail("FRANCHISE_PROVISIONING_FAILED", "Tenant and branch provisioning must commit together");
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "franchise.tenant_branch_provisioned",
      entityType: "franchise_application", entityId: application.id,
      idempotencyKey: scope.idempotencyKey });
    return Object.freeze({ status: "provisioned", tenantId: created.tenantId, branchId: created.branchId });
  });
}

/** BI: immutable versioned KPI ingestion with complete source lineage. */
export async function ingestReconciledKpiSnapshot(input, deps) {
  const scope = { ...scopeOf(input), action: "bi.kpi.ingest" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const definition = await adapter(deps, "loadPublishedKpiDefinition")(tx, input.metricId, input.formulaVersion);
    if (!definition || definition.status !== "published" || definition.formulaVersion !== input.formulaVersion) {
      fail("PUBLISHED_KPI_VERSION_REQUIRED", "KPI formula version must be published and immutable");
    }
    const facts = await adapter(deps, "loadFinanceFactsForKpi")(tx, {
      tenantId: scope.tenantId, branchId: scope.branchId,
      metricId: definition.id, periodStart: input.periodStart, periodEnd: input.periodEnd,
    });
    const reconciliations = await adapter(deps, "loadSourceReconciliations")(tx, facts.map(f => f.sourceId));
    const targets = await adapter(deps, "loadApprovedKpiTarget")(tx, definition.id, input.periodStart, input.periodEnd);
    const snapshot = verifyExecutiveFinanceKpi({
      tenantId: scope.tenantId, metric: { ...definition, sourceOfTruth: "finance" },
      periodStart: input.periodStart, periodEnd: input.periodEnd,
      financeFacts: facts, sourceReconciliations: reconciliations, targets,
    });
    const lineage = await adapter(deps, "buildAndValidateKpiLineage")(tx, {
      definition, facts, reconciliations, formulaVersion: definition.formulaVersion,
    });
    if (!lineage?.complete || !lineage?.lineageId) fail("KPI_LINEAGE_INCOMPLETE", "KPI source lineage must be complete");
    const saved = await adapter(deps, "insertImmutableKpiSnapshot")(tx, { snapshot, lineage, actorId: scope.actorId });
    if (!saved?.snapshotId) fail("KPI_SNAPSHOT_PERSIST_FAILED", "KPI snapshot did not persist");
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "bi.kpi.snapshot_ingested",
      entityType: "bi_kpi_snapshot", entityId: saved.snapshotId,
      idempotencyKey: scope.idempotencyKey });
    return Object.freeze({ status: "ingested", snapshotId: saved.snapshotId, lineageId: lineage.lineageId, actualIdr: snapshot.actualIdr });
  });
}

/** SaaS: record usage only after the caller's authoritative transaction committed. */
export async function meterCommittedTenantOperation(input, deps) {
  const recordUsage = adapter(deps, "recordUsage");
  return recordUsageAfterAuthoritativeCommit({
    operationResult: input.operationResult, tenantId: input.tenantId,
    entitlementKey: input.entitlementKey, quantity: input.quantity ?? 1,
    sourceEntity: input.sourceEntity, sourceId: input.sourceId,
    idempotencyKey: input.idempotencyKey, occurredAt: input.occurredAt,
    recordUsage,
  });
}

/**
 * Procurement: reserve a payment instruction in a DB transaction, call the
 * external payment provider outside that transaction, then persist its result.
 * Provider idempotency is mandatory because a network timeout is ambiguous.
 */
export async function executeApprovedSupplierPayment(input, deps) {
  const scope = { ...scopeOf(input), action: "procurement.payment.execute" };
  const intent = await inTenantTransaction(deps, scope, async (tx) => {
    const invoice = await adapter(deps, "loadApprovedSupplierInvoice")(tx, input.invoiceId);
    assertScope(invoice, scope, "supplierInvoice");
    const approval = await adapter(deps, "loadIndependentApApproval")(tx, invoice.id);
    const journal = await adapter(deps, "loadPostedApJournal")(tx, invoice.id);
    const creditNotes = await adapter(deps, "loadApprovedCreditNotes")(tx, invoice.id);
    if (!approval || !journal || !Array.isArray(creditNotes)) fail("AP_PAYMENT_EVIDENCE_REQUIRED", "Approval, posted journal and credit notes are required");
    const existing = await adapter(deps, "findSupplierPaymentIntent")(tx, scope.idempotencyKey);
    if (existing) return { duplicate: true, intent: existing };
    const payable = invoice.totalIdr - creditNotes.reduce((sum, note) => sum + note.amountIdr, 0);
    if (!Number.isSafeInteger(payable) || payable <= 0) fail("AP_PAYABLE_INVALID", "Payable amount must be positive");
    const created = await adapter(deps, "createSupplierPaymentIntent")(tx, {
      invoice, approval, journal, creditNotes, amountIdr: payable,
      idempotencyKey: scope.idempotencyKey, actorId: scope.actorId,
    });
    if (!created?.intentId || !created?.providerId) fail("AP_PAYMENT_INTENT_FAILED", "Durable payment intent is required");
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "procurement.payment_intent.created",
      entityType: "supplier_payment_intent", entityId: created.intentId,
      idempotencyKey: scope.idempotencyKey });
    return { duplicate: false, intent: created };
  });
  if (intent.duplicate && intent.intent.status === "executed") return Object.freeze({ status: "duplicate", paymentReference: intent.intent.providerReference });
  const execute = adapter(deps, "executeProviderPayment");
  const providerResult = await execute({
    providerId: intent.intent.providerId, amountIdr: intent.intent.amountIdr,
    currency: "IDR", idempotencyKey: scope.idempotencyKey,
    supplierReference: intent.intent.supplierReference,
  });
  if (!providerResult?.accepted || !providerResult.providerReference) {
    fail("SUPPLIER_PAYMENT_ACCEPTANCE_UNVERIFIED", "Payment provider acceptance requires a stable reference");
  }
  const finalized = await inTenantTransaction(deps, scope, async (tx) => {
    const saved = await adapter(deps, "finalizeSupplierPaymentIntent")(tx, {
      intentId: intent.intent.intentId, providerResult, actorId: scope.actorId,
    });
    if (!saved?.paymentId || saved.status !== "submitted") fail("SUPPLIER_PAYMENT_FINALIZATION_FAILED", "Provider result must be durably recorded");
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "procurement.payment.submitted",
      entityType: "supplier_payment", entityId: saved.paymentId,
      idempotencyKey: scope.idempotencyKey });
    return saved;
  });
  return Object.freeze({ status: "submitted_for_settlement", paymentId: finalized.paymentId,
    providerReference: providerResult.providerReference, reconciliationRequired: true });
}

/** Procurement settlement: require posted AP, executed payment and bank match. */
export async function reconcileApprovedSupplierSettlement(input, deps) {
  const scope = { ...scopeOf(input), action: "procurement.payment.reconcile" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const evidence = await adapter(deps, "loadSupplierSettlementEvidence")(tx, input.invoiceId);
    assertScope(evidence?.invoice, scope, "supplierInvoice");
    const result = reconcileSupplierPayment(evidence);
    const saved = await adapter(deps, "persistSupplierSettlementReconciliation")(tx, {
      ...result, actorId: scope.actorId, idempotencyKey: scope.idempotencyKey,
    });
    if (!saved?.settlementId) fail("SUPPLIER_SETTLEMENT_PERSIST_FAILED", "Settlement reconciliation must persist");
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "procurement.supplier_settlement.reconciled",
      entityType: "supplier_settlement", entityId: saved.settlementId,
      idempotencyKey: scope.idempotencyKey });
    return Object.freeze({ ...result, settlementId: saved.settlementId });
  });
}

/** Executive: authorize each hierarchy node before returning source transactions. */
export async function readAuthorizedExecutiveDrilldown(input, deps) {
  const scope = { ...scopeOf(input), action: "executive.drilldown.read" };
  const hierarchy = input.hierarchy;
  if (!Array.isArray(hierarchy) || hierarchy.length < 1 || hierarchy.length > 5) {
    fail("EXECUTIVE_HIERARCHY_REQUIRED", "Provide company, region, branch, shift or transaction path");
  }
  return inTenantTransaction(deps, scope, async (tx) => {
    let parent = null;
    const resolved = [];
    for (const node of hierarchy) {
      if (!node || !["company", "region", "branch", "shift", "transaction"].includes(node.type) || !node.id) {
        fail("EXECUTIVE_HIERARCHY_NODE_INVALID", "Invalid drill-down node");
      }
      const record = await adapter(deps, "loadAuthorizedHierarchyNode")(tx, {
        tenantId: scope.tenantId, parent, type: node.type, id: node.id,
      });
      if (!record || record.tenantId !== scope.tenantId || (parent && record.parentId !== parent.id)) {
        fail("EXECUTIVE_HIERARCHY_SCOPE_DENIED", "Hierarchy node is outside the authorized parent scope");
      }
      await adapter(deps, "authorizeHierarchyNode")(tx, {
        actorId: scope.actorId, tenantId: scope.tenantId, branchId: record.branchId ?? scope.branchId,
        nodeType: node.type, nodeId: node.id,
      });
      resolved.push(record);
      parent = record;
    }
    const data = await adapter(deps, "loadFinanceBackedDrilldown")(tx, {
      tenantId: scope.tenantId, hierarchy: resolved,
    });
    if (!data?.financeReconciled || !Array.isArray(data.transactions) ||
        data.transactions.some(t => t.tenantId !== scope.tenantId || t.financeStatus !== "reconciled")) {
      fail("EXECUTIVE_SOURCE_RECONCILIATION_REQUIRED", "Drill-down must return reconciled Finance source transactions");
    }
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "executive.drilldown.read",
      entityType: hierarchy.at(-1).type, entityId: hierarchy.at(-1).id,
      idempotencyKey: scope.idempotencyKey });
    return Object.freeze({ status: "verified", hierarchy: resolved, data });
  });
}
