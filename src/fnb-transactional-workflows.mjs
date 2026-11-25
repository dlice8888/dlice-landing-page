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
import {
  dispatchConsentedCampaignMessage,
  applyCampaignProviderReceipt,
  applyCampaignUnsubscribe,
  calculateCampaignRoi,
} from "./crm-campaign-delivery.mjs";
import { reconcilePayrollPayment } from "./hr-payroll-payment-reconciliation.mjs";
import { enforceTenantEntitlement } from "./saas-entitlement-enforcement.mjs";
import { buildSupplierInvoiceApJournal } from "./procurement-ap-journal.mjs";
import { rankReconciledBranches } from "./executive-branch-ranking.mjs";
import { calculateFranchiseRoyalty } from "./franchise-royalty-calculation.mjs";
import { calculatePayrollLine } from "./hr-payroll-calculation.mjs";
import { buildCrmFinancialCloseEvidence } from "./crm-financial-close.mjs";

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
  const secret = await adapter(deps, "getProviderWebhookSecret")(input.providerId);
  const verified = await verifyDeliveryWebhook({
    rawBody: input.rawBody, signature: input.signature, timestamp: input.timestamp,
    secret, nowMs: input.nowMs, maxSkewSeconds: input.maxSkewSeconds,
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


/** CRM campaign: atomically claim outbox, call approved provider, persist acceptance. */
export async function dispatchApprovedCampaignMessage(input, deps) {
  const scope = { tenantId: required(input.tenantId, "tenantId"),
    branchId: input.branchId == null ? null : required(input.branchId, "branchId"),
    actorId: required(input.actorId, "actorId"),
    idempotencyKey: required(input.idempotencyKey, "idempotencyKey"),
    action: "crm.campaign.dispatch" };
  const records = await inTenantTransaction(deps, scope, async (tx) => {
    const campaign = await adapter(deps, "loadApprovedCampaign")(tx, input.campaignId);
    const customer = await adapter(deps, "loadCampaignCustomer")(tx, input.customerId);
    const consent = await adapter(deps, "loadCurrentCustomerConsent")(tx, input.customerId, campaign?.channel, campaign?.purpose);
    const provider = await adapter(deps, "loadApprovedCampaignProvider")(tx, campaign?.channel);
    assertScope(campaign, scope, "campaign");
    assertScope(customer, scope, "customer");
    return { campaign, customer, consent, provider };
  });
  return dispatchConsentedCampaignMessage({
    ...records, outbox: null,
    claimOutbox: (args) => inTenantTransaction(deps, scope, async (tx) =>
      adapter(deps, "claimCampaignOutbox")(tx, args)),
    sendProvider: (args) => adapter(deps, "sendCampaignProviderMessage")(records.provider, args),
    recordProviderAcceptance: (args) => inTenantTransaction(deps, scope, async (tx) => {
      const saved = await adapter(deps, "persistCampaignProviderAcceptance")(tx, args);
      if (!saved?.outboxId) fail("CAMPAIGN_ACCEPTANCE_PERSIST_FAILED", "Provider acceptance must persist to the outbox");
      await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
        actorId: scope.actorId, action: "crm.campaign.provider_accepted",
        entityType: "campaign_outbox", entityId: saved.outboxId,
        idempotencyKey: scope.idempotencyKey });
      return saved;
    }),
    scheduleRetry: (args) => inTenantTransaction(deps, scope, async (tx) =>
      adapter(deps, "scheduleCampaignRetry")(tx, args)),
    now: input.now,
  });
}

/** CRM campaign receipt: provider-specific signature verification precedes dedupe and state update. */
export async function ingestSignedCampaignReceipt(input, deps) {
  const verified = await adapter(deps, "verifyCampaignReceiptSignature")({
    providerId: input.providerId, rawBody: input.rawBody,
    signature: input.signature, timestamp: input.timestamp,
  });
  if (verified?.verified !== true || !verified.receipt) {
    fail("CAMPAIGN_RECEIPT_SIGNATURE_INVALID", "Provider receipt signature must be verified over the raw body");
  }
  const scope = { tenantId: required(input.tenantId, "tenantId"),
    branchId: input.branchId == null ? null : required(input.branchId, "branchId"),
    actorId: "system:campaign-webhook", idempotencyKey: required(verified.receipt.eventId, "eventId"),
    action: "crm.campaign.receipt" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const outbox = await adapter(deps, "loadCampaignOutboxForUpdate")(tx, verified.receipt.providerMessageId);
    assertScope(outbox, scope, "campaignOutbox");
    const existingEvent = await adapter(deps, "findCampaignProviderEvent")(tx, input.providerId, scope.tenantId, verified.receipt.eventId);
    const decision = applyCampaignProviderReceipt({
      outbox, receipt: verified.receipt, signatureVerified: true,
      existingEvent, maxAttempts: input.maxAttempts ?? 5,
    });
    if (decision.action === "duplicate") return Object.freeze({ status: "duplicate", eventId: verified.receipt.eventId });
    const saved = await adapter(deps, "persistCampaignReceiptAndOutboxState")(tx, {
      decision, receipt: verified.receipt, outboxId: outbox.id,
    });
    if (!saved?.eventId) fail("CAMPAIGN_RECEIPT_PERSIST_FAILED", "Campaign receipt event was not persisted");
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "crm.campaign.receipt_applied",
      entityType: "campaign_provider_event", entityId: saved.eventId,
      idempotencyKey: verified.receipt.eventId });
    return Object.freeze({ status: "applied", eventId: saved.eventId,
      deliveryStatus: decision.status, retryScheduled: decision.retryScheduled === true,
      deadLetter: decision.deadLetter === true });
  });
}

/** Signed campaign unsubscribe: append consent withdrawal and suppress future recipients atomically. */
export async function ingestSignedCampaignUnsubscribe(input, deps) {
  const verified = await adapter(deps, "verifyCampaignUnsubscribeSignature")({
    providerId: input.providerId, rawBody: input.rawBody,
    signature: input.signature, timestamp: input.timestamp,
  });
  if (verified?.verified !== true || !verified.event?.eventId ||
      !verified.event?.occurredAt || !verified.bodySha256) {
    fail("CAMPAIGN_UNSUBSCRIBE_SIGNATURE_INVALID", "Signed provider unsubscribe event is required");
  }
  const scope = {
    tenantId: required(input.tenantId, "tenantId"),
    branchId: input.branchId == null ? null : required(input.branchId, "branchId"),
    actorId: "system:campaign-unsubscribe",
    idempotencyKey: required(verified.event.eventId, "eventId"),
    action: "crm.campaign.unsubscribe",
  };
  return inTenantTransaction(deps, scope, async (tx) => {
    const context = await adapter(deps, "loadCampaignUnsubscribeContextForUpdate")(tx, {
      providerId: input.providerId, providerEvent: verified.event,
    });
    assertScope(context?.customer, scope, "campaignUnsubscribeCustomer");
    const existing = await adapter(deps, "findCampaignProviderEvent")(tx, input.providerId, scope.tenantId, verified.event.eventId);
    if (existing) {
      if (existing.bodySha256 !== verified.bodySha256) {
        fail("CAMPAIGN_PROVIDER_EVENT_COLLISION", "Provider event id was reused with a different payload");
      }
      return Object.freeze({ status: "duplicate", eventId: verified.event.eventId });
    }
    const decision = applyCampaignUnsubscribe({
      customer: context.customer, consent: context.consent,
      providerEvent: verified.event, signatureVerified: true,
    });
    const saved = await adapter(deps, "persistCampaignUnsubscribeAndConsentEvent")(tx, {
      decision, customer: context.customer, consent: context.consent,
      outbox: context.outbox, providerId: input.providerId,
      bodySha256: verified.bodySha256, actorId: scope.actorId,
    });
    if (!saved?.eventId || !saved?.consentEventId) {
      fail("CAMPAIGN_UNSUBSCRIBE_PERSIST_FAILED", "Consent withdrawal and provider event must persist together");
    }
    await audit(deps, tx, {
      tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "crm.campaign.consent_withdrawn",
      entityType: "crm_customer_consent_event", entityId: saved.consentEventId,
      idempotencyKey: verified.event.eventId,
    });
    return Object.freeze({
      status: "unsubscribed", eventId: saved.eventId,
      consentEventId: saved.consentEventId,
      customerId: context.customer.id,
      suppressedRecipients: saved.suppressedRecipients ?? null,
    });
  });
}

/** Campaign ROI is calculated only from attributed, Finance-reconciled eligible net sales. */
export async function calculateReconciledCampaignRoi(input, deps) {
  const scope = { tenantId: required(input.tenantId, "tenantId"),
    branchId: input.branchId == null ? null : required(input.branchId, "branchId"),
    actorId: required(input.actorId, "actorId"),
    idempotencyKey: required(input.idempotencyKey, "idempotencyKey"),
    action: "crm.campaign.roi.read" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const campaign = await adapter(deps, "loadApprovedCampaign")(tx, input.campaignId);
    assertScope(campaign, scope, "campaign");
    const attributedOrders = await adapter(deps, "loadReconciledCampaignAttribution")(tx, campaign.id, input.windowStart, input.windowEnd);
    const result = calculateCampaignRoi({
      campaignCostIdr: await adapter(deps, "loadCampaignCostIdr")(tx, campaign.id),
      attributedOrders, attributionWindowStart: input.windowStart,
      attributionWindowEnd: input.windowEnd,
    });
    return Object.freeze({ ...result, campaignId: campaign.id, tenantId: scope.tenantId });
  });
}

/** HR payroll payment: create a durable intent, execute externally, then reconcile bank/provider settlement. */
export async function executeApprovedPayrollPayment(input, deps) {
  const scope = { ...scopeOf(input), action: "hr.payroll.payment.execute" };
  const intent = await inTenantTransaction(deps, scope, async (tx) => {
    const run = await adapter(deps, "loadApprovedPayrollRunForPayment")(tx, input.payrollRunId);
    assertScope(run, scope, "payrollRun");
    const journal = await adapter(deps, "loadApprovedPostedPayrollJournal")(tx, run.id);
    if (!journal || journal.status !== "posted" || journal.debitIdr !== journal.creditIdr) {
      fail("PAYROLL_JOURNAL_NOT_POSTED", "Balanced posted payroll journal is required before payment");
    }
    const prior = await adapter(deps, "findPayrollPaymentIntent")(tx, scope.idempotencyKey);
    if (prior) return { duplicate: true, intent: prior };
    const created = await adapter(deps, "createPayrollPaymentIntent")(tx, {
      run, journal, idempotencyKey: scope.idempotencyKey, actorId: scope.actorId,
    });
    if (!created?.intentId || !created?.providerId || !Number.isSafeInteger(created.amountIdr) || created.amountIdr <= 0) {
      fail("PAYROLL_PAYMENT_INTENT_INVALID", "Durable payroll payment intent is required");
    }
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "hr.payroll.payment_intent.created",
      entityType: "payroll_payment_intent", entityId: created.intentId,
      idempotencyKey: scope.idempotencyKey });
    return { duplicate: false, intent: created };
  });
  if (intent.duplicate && intent.intent.status === "executed") {
    return Object.freeze({ status: "duplicate", providerReference: intent.intent.providerReference });
  }
  const providerResult = await adapter(deps, "executePayrollPaymentProvider")({
    providerId: intent.intent.providerId, amountIdr: intent.intent.amountIdr,
    currency: "IDR", idempotencyKey: scope.idempotencyKey,
    beneficiaryReference: intent.intent.beneficiaryReference,
  });
  if (!providerResult?.accepted || !providerResult.providerReference) {
    fail("PAYROLL_PAYMENT_ACCEPTANCE_UNVERIFIED", "Payment provider acceptance needs a stable reference");
  }
  const saved = await inTenantTransaction(deps, scope, async (tx) => {
    const result = await adapter(deps, "finalizePayrollPaymentIntent")(tx, {
      intentId: intent.intent.intentId, providerResult, actorId: scope.actorId,
    });
    if (!result?.paymentId || result.status !== "submitted") fail("PAYROLL_PAYMENT_FINALIZATION_FAILED", "Provider result must persist");
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "hr.payroll.payment.submitted",
      entityType: "payroll_payment", entityId: result.paymentId,
      idempotencyKey: scope.idempotencyKey });
    return result;
  });
  return Object.freeze({ status: "submitted_for_settlement", paymentId: saved.paymentId,
    providerReference: providerResult.providerReference, reconciliationRequired: true });
}

export async function reconcileApprovedPayrollPayment(input, deps) {
  const scope = { ...scopeOf(input), action: "hr.payroll.payment.reconcile" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const evidence = await adapter(deps, "loadPayrollPaymentSettlementEvidence")(tx, input.payrollRunId);
    assertScope(evidence?.payrollRun, scope, "payrollRun");
    const result = reconcilePayrollPayment(evidence);
    const saved = await adapter(deps, "persistPayrollPaymentReconciliation")(tx, {
      ...result, actorId: scope.actorId, idempotencyKey: scope.idempotencyKey,
    });
    if (!saved?.reconciliationId) fail("PAYROLL_PAYMENT_RECONCILIATION_PERSIST_FAILED", "Payroll payment reconciliation must persist");
    await audit(deps, tx, { tenantId: scope.tenantId, branchId: scope.branchId,
      actorId: scope.actorId, action: "hr.payroll.payment.reconciled",
      entityType: "payroll_payment_reconciliation", entityId: saved.reconciliationId,
      idempotencyKey: scope.idempotencyKey });
    return Object.freeze({ ...result, reconciliationId: saved.reconciliationId });
  });
}




/** CRM: build a close projection only from server-loaded reconciled source evidence. */
export async function buildCrmFinancialCloseProjection(input, deps) {
  const scope = { ...scopeOf(input), action: "crm.financial_close.project" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const source = await adapter(deps, "loadCrmFinancialCloseSourceForUpdate")(tx, {
      sourceType: input.sourceType, sourceId: required(input.sourceId, "sourceId"),
    });
    assertScope(source, scope, "crmFinancialCloseSource");
    const [refunds, settlement, shift, finance, financeExpectedIdr] = await Promise.all([
      adapter(deps, "loadCrmSourceRefunds")(tx, source.id),
      adapter(deps, "loadCrmSettlementReconciliation")(tx, source.id),
      adapter(deps, "loadCrmApprovedShiftReconciliation")(tx, source.id),
      adapter(deps, "loadCrmPostedFinanceSource")(tx, source.id),
      adapter(deps, "loadCrmFinanceExpectedAmount")(tx, source.id),
    ]);
    const projection = buildCrmFinancialCloseEvidence({
      financialCloseId: required(input.financialCloseId, "financialCloseId"),
      source, refunds, settlement, shift, finance, financeExpectedIdr,
    });
    const saved = await adapter(deps, "insertImmutableCrmFinancialCloseProjection")(tx, {
      projection, actorId: scope.actorId, idempotencyKey: scope.idempotencyKey,
    });
    if (!saved?.projectionId || saved.status !== "reconciled") {
      fail("CRM_FINANCIAL_CLOSE_PROJECTION_PERSIST_FAILED", "Immutable reconciled close projection must persist");
    }
    await audit(deps, tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
      action: "crm.financial_close.projected", entityType: "crm_financial_close_projection",
      entityId: saved.projectionId, idempotencyKey: scope.idempotencyKey,
    });
    return Object.freeze({ status: "reconciled", projectionId: saved.projectionId,
      eligibleNetSalesIdr: projection.eligibleNetSalesIdr, sourceId: source.id });
  });
}

/** HR: calculate immutable payroll lines from approved timesheets and effective compensation. */
export async function calculateAndPersistPayrollRun(input, deps) {
  const scope = { ...scopeOf(input), action: "hr.payroll.calculate" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const run = await adapter(deps, "loadPayrollRunForUpdate")(tx, input.payrollRunId);
    assertScope(run, scope, "payrollRun");
    if (run.status !== "draft") fail("PAYROLL_RUN_NOT_DRAFT", "Only a draft payroll run can be calculated");
    const rows = await adapter(deps, "loadApprovedPayrollCalculationInputs")(tx, {
      tenantId: scope.tenantId, branchId: scope.branchId,
      periodStart: run.periodStart, periodEnd: run.periodEnd,
    });
    if (!Array.isArray(rows) || rows.length === 0) {
      fail("APPROVED_PAYROLL_INPUTS_REQUIRED", "Approved attendance/timesheet and compensation inputs are required");
    }
    const lines = rows.map((row) => {
      if (!row.employee || row.employee.tenantId !== scope.tenantId ||
          (scope.branchId && row.employee.branchId !== scope.branchId) ||
          row.employee.status !== "active" || !row.approvedTime?.approved) {
        fail("PAYROLL_EMPLOYEE_OR_TIME_NOT_ELIGIBLE", "Every payroll line needs an active scoped employee and approved time");
      }
      return {
        ...calculatePayrollLine({
          employeeId: row.employee.id, periodStart: run.periodStart, periodEnd: run.periodEnd,
          compensation: row.compensation, approvedTime: row.approvedTime,
          components: row.components, monthlyProration: row.monthlyProration ?? null,
        }),
        tenantId: scope.tenantId, branchId: row.employee.branchId,
      };
    });
    const saved = await adapter(deps, "persistImmutableCalculatedPayrollLines")(tx, {
      run, lines, actorId: scope.actorId, idempotencyKey: scope.idempotencyKey,
    });
    if (!saved?.payrollRunId || saved.status !== "calculated" || saved.lineCount !== lines.length) {
      fail("PAYROLL_CALCULATION_PERSIST_FAILED", "Complete immutable payroll line snapshot must persist");
    }
    await audit(deps, tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
      action: "hr.payroll.calculated", entityType: "hr_payroll_run",
      entityId: run.id, idempotencyKey: scope.idempotencyKey,
    });
    return Object.freeze({ status: "calculated", payrollRunId: run.id,
      lineCount: lines.length, grossTotalIdr: lines.reduce((n, x) => n + x.grossAmountIdr, 0),
      netTotalIdr: lines.reduce((n, x) => n + x.netAmountIdr, 0) });
  });
}

/** Franchise: create royalty only from an effective signed agreement and reconciled close. */
export async function createReconciledFranchiseRoyaltyStatement(input, deps) {
  const scope = { ...scopeOf(input), action: "franchise.royalty.create" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const agreement = await adapter(deps, "loadEffectiveFranchiseAgreementForUpdate")(tx, input.agreementId);
    assertScope(agreement, scope, "franchiseAgreement");
    const close = await adapter(deps, "loadReconciledFranchiseFinancialClose")(tx, {
      tenantId: scope.tenantId, franchiseId: agreement.franchiseId,
      periodStart: input.periodStart, periodEnd: input.periodEnd,
    });
    const statement = calculateFranchiseRoyalty({
      agreement, financialClose: close,
      statementPeriodStart: input.periodStart, statementPeriodEnd: input.periodEnd,
    });
    const prior = await adapter(deps, "findFranchiseRoyaltyByIdempotencyKey")(tx, scope.tenantId, statement.idempotencyKey);
    if (prior) return Object.freeze({ status: "duplicate", statementId: prior.id });
    const saved = await adapter(deps, "persistFranchiseRoyaltyStatement")(tx, {
      statement, actorId: scope.actorId, requestIdempotencyKey: scope.idempotencyKey,
    });
    if (!saved?.statementId || saved.status !== "draft") {
      fail("FRANCHISE_ROYALTY_PERSIST_FAILED", "Royalty statement must persist as draft before review and approval");
    }
    await audit(deps, tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
      action: "franchise.royalty.statement_created", entityType: "franchise_royalty_statement",
      entityId: saved.statementId, idempotencyKey: scope.idempotencyKey,
    });
    return Object.freeze({ status: "draft", statementId: saved.statementId,
      netSalesIdr: statement.netSalesIdr, royaltyIdr: statement.royaltyIdr,
      paymentStatus: "not_paid" });
  });
}

/** Procurement: persist a balanced AP journal draft after a clean three-way match. */
export async function postMatchedSupplierInvoiceToApJournal(input, deps) {
  const scope = { ...scopeOf(input), action: "procurement.ap.post" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const invoice = await adapter(deps, "loadSupplierInvoiceForUpdate")(tx, input.invoiceId);
    assertScope(invoice, scope, "supplierInvoice");
    const lines = await adapter(deps, "loadMatchedSupplierInvoiceLines")(tx, invoice.id);
    const accountMapping = await adapter(deps, "loadApprovedSupplierApAccountMapping")(tx, scope.tenantId, scope.branchId);
    const approval = await adapter(deps, "loadIndependentSupplierInvoiceApproval")(tx, invoice.id);
    if (!approval?.approvedBy || approval.approvedBy === invoice.receivedBy) {
      fail("INDEPENDENT_SUPPLIER_INVOICE_APPROVAL_REQUIRED", "Invoice approval must be independent from invoice receiver");
    }
    const period = await adapter(deps, "loadOpenSupplierApFiscalPeriod")(tx, invoice.invoiceDate);
    if (!period || period.status !== "open") fail("SUPPLIER_AP_FISCAL_PERIOD_NOT_OPEN", "An open Finance fiscal period is required");
    const journal = buildSupplierInvoiceApJournal({
      invoice, lines, accountMapping, idempotencyKey: scope.idempotencyKey,
    });
    const prior = await adapter(deps, "findSupplierApJournalByIdempotencyKey")(tx, scope.tenantId, scope.idempotencyKey);
    if (prior) return Object.freeze({ status: "duplicate", journalBatchId: prior.batchId });
    const saved = await adapter(deps, "persistSupplierApJournalDraft")(tx, {
      invoice, journal, fiscalPeriod: period, actorId: scope.actorId,
    });
    if (!saved?.batchId || saved.status !== "draft" || saved.debitIdr !== saved.creditIdr) {
      fail("SUPPLIER_AP_JOURNAL_PERSIST_FAILED", "Balanced AP journal must persist as a draft");
    }
    await audit(deps, tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
      action: "procurement.ap_journal.draft_created", entityType: "finance_journal_batch",
      entityId: saved.batchId, idempotencyKey: scope.idempotencyKey,
    });
    return Object.freeze({ status: "draft", journalBatchId: saved.batchId,
      debitIdr: saved.debitIdr, creditIdr: saved.creditIdr,
      requiresIndependentFinancePosting: true });
  });
}

/** Executive: rank the complete authorized branch set, never a partial sample. */
export async function publishExecutiveBranchRanking(input, deps) {
  const scope = { ...scopeOf(input), action: "executive.branch_ranking.publish" };
  return inTenantTransaction(deps, scope, async (tx) => {
    const expectedBranchIds = await adapter(deps, "loadAuthorizedActiveBranchIds")(tx, scope.tenantId);
    if (!Array.isArray(expectedBranchIds) || expectedBranchIds.length < 1 || expectedBranchIds.length > 150) {
      fail("EXECUTIVE_BRANCH_SCOPE_INVALID", "Authoritative active branch scope must contain 1–150 branches");
    }
    const [snapshots, targets] = await Promise.all([
      adapter(deps, "loadReconciledBranchFinanceSnapshots")(tx, {
        tenantId: scope.tenantId, periodStart: input.periodStart, periodEnd: input.periodEnd,
      }),
      adapter(deps, "loadApprovedBranchTargets")(tx, {
        tenantId: scope.tenantId, periodStart: input.periodStart, periodEnd: input.periodEnd,
      }),
    ]);
    const ranking = rankReconciledBranches({
      tenantId: scope.tenantId, periodStart: input.periodStart, periodEnd: input.periodEnd,
      branchSnapshots: snapshots, targets, expectedBranchIds, limit: 150,
    });
    const saved = await adapter(deps, "persistImmutableExecutiveBranchRanking")(tx, {
      ranking, actorId: scope.actorId, idempotencyKey: scope.idempotencyKey,
    });
    if (!saved?.rankingId || saved.branchCount !== ranking.branchCount) {
      fail("EXECUTIVE_RANKING_PERSIST_FAILED", "Complete branch ranking snapshot must persist");
    }
    await audit(deps, tx, {
      tenantId: scope.tenantId, branchId: null, actorId: scope.actorId,
      action: "executive.branch_ranking.published", entityType: "executive_branch_ranking",
      entityId: saved.rankingId, idempotencyKey: scope.idempotencyKey,
    });
    return Object.freeze({ status: "published", rankingId: saved.rankingId,
      branchCount: ranking.branchCount, ranking: ranking.ranking });
  });
}

/** BI: scheduled ingestion runner; each metric result/error is durably accounted for. */
export async function runScheduledBiKpiIngestion(input, deps) {
  const scope = { ...scopeOf(input), action: "bi.ingestion.run" };
  const definitions = await inTenantTransaction(deps, scope, async (tx) =>
    adapter(deps, "loadActiveScheduledKpiDefinitions")(tx, scope.tenantId));
  if (!Array.isArray(definitions) || definitions.length === 0) {
    fail("BI_SCHEDULED_METRICS_NOT_CONFIGURED", "No active scheduled KPI definitions are configured");
  }
  const results = [];
  for (const definition of definitions) {
    const key = `${scope.idempotencyKey}:${definition.id}:${input.periodStart}:${input.periodEnd}`;
    try {
      const result = await ingestReconciledKpiSnapshot({
        tenantId: scope.tenantId, branchId: input.branchId ?? null,
        actorId: scope.actorId, idempotencyKey: key,
        metricId: definition.id, formulaVersion: definition.formulaVersion,
        periodStart: input.periodStart, periodEnd: input.periodEnd,
      }, deps);
      results.push({ metricId: definition.id, status: "ingested", snapshotId: result.snapshotId });
    } catch (error) {
      const failure = { metricId: definition.id, status: "failed",
        errorCode: error?.code ?? "BI_INGESTION_FAILED" };
      await inTenantTransaction(deps, scope, async (tx) => {
        await adapter(deps, "persistBiIngestionFailure")(tx, {
          tenantId: scope.tenantId, metricId: definition.id,
          periodStart: input.periodStart, periodEnd: input.periodEnd,
          runIdempotencyKey: key, errorCode: failure.errorCode,
        });
        await audit(deps, tx, {
          tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
          action: "bi.kpi.ingestion_failed", entityType: "bi_metric_definition",
          entityId: definition.id, idempotencyKey: key,
        });
      });
      results.push(failure);
    }
  }
  return Object.freeze({ status: results.every(x => x.status === "ingested") ? "complete" : "partial",
    metricCount: definitions.length, results: Object.freeze(results.map(Object.freeze)) });
}

/**
 * Delivery: request quotes from explicitly approved providers. Provider calls
 * happen outside database transactions; only validated quote snapshots are
 * persisted, scoped to the source tenant and branch.
 */
export async function requestDeliveryQuotes(input, deps) {
  const scope = { ...scopeOf(input), action: "delivery.quote.request" };
  const source = await inTenantTransaction(deps, scope, async (tx) => {
    const record = await adapter(deps, "loadDeliverySourceForUpdate")(tx, {
      sourceType: input.sourceType, sourceId: required(input.sourceId, "sourceId"),
    });
    assertScope(record, scope, "deliverySource");
    if (record.paymentStatus !== "paid" || record.fulfillmentStatus === "delivered" ||
        record.fulfillmentStatus === "cancelled") {
      fail("DELIVERY_SOURCE_NOT_ELIGIBLE", "Delivery quote requires a paid, active fulfillment source");
    }
    const address = await adapter(deps, "loadValidatedDeliveryAddress")(tx, record.id);
    if (!address?.validated || !address.addressHash) {
      fail("VALIDATED_DELIVERY_ADDRESS_REQUIRED", "A server-validated destination address is required");
    }
    const providers = await adapter(deps, "loadApprovedDeliveryProviders")(tx, scope.tenantId, scope.branchId);
    if (!Array.isArray(providers) || providers.length === 0) {
      fail("APPROVED_DELIVERY_PROVIDER_UNAVAILABLE", "No approved delivery provider is configured for this tenant and branch");
    }
    return { record, address, providers };
  });
  const quotes = [];
  for (const provider of source.providers) {
    const result = await adapter(deps, "requestDeliveryProviderQuote")({
      provider, source: source.record, address: source.address,
      idempotencyKey: scope.idempotencyKey,
    });
    if (!result?.accepted || !result.providerQuoteId || result.currency !== "IDR" ||
        !Number.isSafeInteger(result.quotedCostIdr) || result.quotedCostIdr < 0 ||
        !result.expiresAt || Date.parse(result.expiresAt) <= Date.now() ||
        !/^[0-9a-f]{64}$/i.test(result.payloadSha256 || "")) {
      continue;
    }
    const saved = await inTenantTransaction(deps, scope, async (tx) => {
      const quote = await adapter(deps, "persistDeliveryProviderQuote")(tx, {
        tenantId: scope.tenantId, branchId: scope.branchId,
        sourceType: input.sourceType, sourceId: source.record.id,
        providerId: provider.id, providerQuoteId: result.providerQuoteId,
        serviceLevel: result.serviceLevel, currency: "IDR",
        quotedCostIdr: result.quotedCostIdr, codSupported: result.codSupported === true,
        expiresAt: result.expiresAt, payloadSha256: result.payloadSha256,
        idempotencyKey: scope.idempotencyKey,
      });
      if (!saved?.quoteId) fail("DELIVERY_QUOTE_PERSIST_FAILED", "Provider quote snapshot must persist before checkout can select it");
      await audit(deps, tx, {
        tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
        action: "delivery.provider_quote.persisted", entityType: "delivery_provider_quote",
        entityId: saved.quoteId, idempotencyKey: scope.idempotencyKey,
      });
      return saved;
    });
    quotes.push(Object.freeze({
      quoteId: saved.quoteId, providerId: provider.id,
      serviceLevel: result.serviceLevel, quotedCostIdr: result.quotedCostIdr,
      codSupported: result.codSupported === true, expiresAt: result.expiresAt,
    }));
  }
  if (quotes.length === 0) fail("DELIVERY_NO_VALID_PROVIDER_QUOTES", "No provider returned a valid, unexpired IDR quote");
  return Object.freeze({ status: "quoted", sourceId: source.record.id, quotes: Object.freeze(quotes) });
}

/**
 * Delivery: persist a booking intent before calling the provider. An ambiguous
 * timeout remains pending and must be reconciled using the same provider
 * idempotency key; it is never reported as booked without a stable reference.
 */
export async function bookDeliveryDispatch(input, deps) {
  const scope = { ...scopeOf(input), action: "delivery.booking.create" };
  const intent = await inTenantTransaction(deps, scope, async (tx) => {
    const quote = await adapter(deps, "loadDeliveryQuoteForUpdate")(tx, input.quoteId);
    assertScope(quote, scope, "deliveryQuote");
    if (quote.status !== "selected" || Date.parse(quote.expiresAt) <= Date.now()) {
      fail("DELIVERY_QUOTE_NOT_SELECTED_OR_EXPIRED", "A selected, unexpired quote is required");
    }
    const source = await adapter(deps, "loadDeliverySourceForUpdate")(tx, {
      sourceType: quote.sourceType, sourceId: quote.sourceId,
    });
    assertScope(source, scope, "deliverySource");
    if (source.paymentStatus !== "paid" || input.customerAcceptedQuote !== true) {
      fail("DELIVERY_CUSTOMER_ACCEPTANCE_REQUIRED", "Paid source and explicit customer acceptance are required");
    }
    const prior = await adapter(deps, "findDeliveryDispatchByIdempotencyKey")(tx, scope.tenantId, scope.idempotencyKey);
    if (prior) return { duplicate: true, dispatch: prior, quote };
    const dispatch = await adapter(deps, "createDeliveryBookingIntent")(tx, {
      quote, source, tenantId: scope.tenantId, branchId: scope.branchId,
      idempotencyKey: scope.idempotencyKey, actorId: scope.actorId,
      codExpectedIdr: input.codExpectedIdr ?? 0,
    });
    if (!dispatch?.dispatchId || dispatch.status !== "booking_pending") {
      fail("DELIVERY_BOOKING_INTENT_FAILED", "Durable booking intent must persist before provider submission");
    }
    await audit(deps, tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
      action: "delivery.booking_intent.created", entityType: "delivery_dispatch",
      entityId: dispatch.dispatchId, idempotencyKey: scope.idempotencyKey,
    });
    return { duplicate: false, dispatch, quote };
  });
  if (intent.duplicate && intent.dispatch.status === "booked") {
    return Object.freeze({ status: "duplicate", dispatchId: intent.dispatch.dispatchId,
      providerBookingReference: intent.dispatch.providerBookingReference });
  }
  if (intent.duplicate && intent.dispatch.status !== "booking_pending") {
    return Object.freeze({ status: intent.dispatch.status, dispatchId: intent.dispatch.dispatchId });
  }
  const providerResult = await adapter(deps, "bookDeliveryProvider")({
    providerId: intent.quote.providerId, providerQuoteId: intent.quote.providerQuoteId,
    dispatchId: intent.dispatch.dispatchId, idempotencyKey: scope.idempotencyKey,
    codExpectedIdr: input.codExpectedIdr ?? 0,
  });
  if (!providerResult?.accepted || !providerResult.providerBookingReference) {
    await inTenantTransaction(deps, scope, async (tx) => {
      await adapter(deps, "recordDeliveryBookingUncertain")(tx, {
        dispatchId: intent.dispatch.dispatchId, providerResult,
        idempotencyKey: scope.idempotencyKey,
      });
      await audit(deps, tx, {
        tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
        action: "delivery.booking.acceptance_unverified", entityType: "delivery_dispatch",
        entityId: intent.dispatch.dispatchId, idempotencyKey: scope.idempotencyKey,
      });
    });
    return Object.freeze({ status: "booking_pending_reconciliation", dispatchId: intent.dispatch.dispatchId });
  }
  const saved = await inTenantTransaction(deps, scope, async (tx) => {
    const result = await adapter(deps, "finalizeDeliveryBooking")(tx, {
      dispatchId: intent.dispatch.dispatchId, providerResult,
      idempotencyKey: scope.idempotencyKey,
    });
    if (!result?.dispatchId || result.status !== "booked" || !result.providerBookingReference) {
      fail("DELIVERY_BOOKING_FINALIZATION_FAILED", "Provider acceptance must be persisted before dispatch is booked");
    }
    await audit(deps, tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
      action: "delivery.booking.confirmed", entityType: "delivery_dispatch",
      entityId: result.dispatchId, idempotencyKey: scope.idempotencyKey,
    });
    return result;
  });
  return Object.freeze({ status: "booked", dispatchId: saved.dispatchId,
    providerBookingReference: saved.providerBookingReference, trackingUrl: saved.trackingUrl ?? null });
}

/**
 * SaaS: enforce plan entitlements before an authoritative tenant operation.
 * The subscription and usage rows must be locked/read in the same transaction
 * as the protected business operation by the caller's repository adapter.
 */
export async function enforceSaasTenantEntitlement(input, deps) {
  const scope = {
    tenantId: required(input?.tenantId, "tenantId"),
    branchId: input?.branchId == null ? null : required(input.branchId, "branchId"),
    actorId: required(input?.actorId, "actorId"),
    idempotencyKey: required(input?.idempotencyKey, "idempotencyKey"),
    action: "saas.entitlement.enforce",
  };
  return inTenantTransaction(deps, scope, async (tx) => {
    const tenant = await adapter(deps, "loadTenantForEntitlement")(tx, scope.tenantId);
    if (!tenant || tenant.id !== scope.tenantId) fail("TENANT_NOT_FOUND", "Tenant must be resolved from trusted database scope");
    const subscription = await adapter(deps, "loadActiveSubscriptionForUpdate")(tx, scope.tenantId);
    const entitlement = await adapter(deps, "loadPlanEntitlementForUpdate")(tx, {
      tenantId: scope.tenantId, entitlementKey: required(input.entitlementKey, "entitlementKey"),
    });
    const usage = await adapter(deps, "loadCommittedUsageForPeriod")(tx, {
      tenantId: scope.tenantId, entitlementKey: input.entitlementKey,
      periodStart: subscription?.currentPeriodStart, periodEnd: subscription?.currentPeriodEnd,
    });
    const decision = enforceTenantEntitlement({
      tenant, subscription, entitlement, usage,
      requested: input.quantity ?? 1, now: input.now ?? Date.now(),
    });
    await audit(deps, tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
      action: "saas.entitlement.allowed", entityType: "saas_entitlement",
      entityId: entitlement.id, idempotencyKey: scope.idempotencyKey,
    });
    return Object.freeze({ ...decision, subscriptionId: subscription.id, entitlementId: entitlement.id });
  });
}

/**
 * SaaS: issue a subscription invoice from the effective plan version and an
 * approved tax decision. Tax is never guessed or calculated from a hard-coded
 * statutory rate; the tax adapter must return a reviewed amount and reference.
 */
export async function issueSaasSubscriptionInvoice(input, deps) {
  const scope = {
    tenantId: required(input?.tenantId, "tenantId"),
    branchId: null,
    actorId: required(input?.actorId, "actorId"),
    idempotencyKey: required(input?.idempotencyKey, "idempotencyKey"),
    action: "saas.billing.invoice.issue",
  };
  return inTenantTransaction(deps, scope, async (tx) => {
    const subscription = await adapter(deps, "loadSubscriptionForBillingUpdate")(tx, input.subscriptionId);
    if (!subscription || subscription.tenantId !== scope.tenantId ||
        !["active", "past_due", "trialing"].includes(subscription.status)) {
      fail("BILLABLE_SUBSCRIPTION_REQUIRED", "A billable tenant subscription is required");
    }
    const plan = await adapter(deps, "loadEffectivePlanVersion")(tx, subscription.planVersionId);
    if (!plan || plan.active !== true || plan.id !== subscription.planVersionId ||
        !Number.isSafeInteger(plan.priceIdr) || plan.priceIdr < 0) {
      fail("EFFECTIVE_PLAN_VERSION_REQUIRED", "An active, effective and immutable plan version is required");
    }
    const period = await adapter(deps, "resolveInvoicePeriod")(tx, {
      subscription, periodStart: input.periodStart, periodEnd: input.periodEnd,
    });
    if (!period?.start || !period?.end || period.end < period.start) {
      fail("SAAS_INVOICE_PERIOD_INVALID", "Invoice period must be valid and subscription-scoped");
    }
    const existing = await adapter(deps, "findSaasInvoiceByIdempotencyKey")(tx, scope.tenantId, scope.idempotencyKey);
    if (existing) return Object.freeze({ status: "duplicate", invoiceId: existing.id, invoiceNumber: existing.invoiceNumber });
    const tax = await adapter(deps, "loadApprovedSaasTaxDecision")(tx, {
      tenantId: scope.tenantId, plan, period,
    });
    if (!tax || tax.status !== "approved" || !tax.reference ||
        !Number.isSafeInteger(tax.taxIdr) || tax.taxIdr < 0) {
      fail("APPROVED_SAAS_TAX_DECISION_REQUIRED", "Invoice tax must come from an approved tax decision, including an explicit zero-tax decision");
    }
    const invoice = await adapter(deps, "insertIssuedSaasInvoice")(tx, {
      tenantId: scope.tenantId, subscription, plan, period,
      subtotalIdr: plan.priceIdr, taxIdr: tax.taxIdr,
      taxReference: tax.reference, idempotencyKey: scope.idempotencyKey,
      actorId: scope.actorId,
    });
    if (!invoice?.id || invoice.status !== "issued" || !invoice.invoiceNumber ||
        invoice.subtotalIdr !== plan.priceIdr || invoice.taxIdr !== tax.taxIdr) {
      fail("SAAS_INVOICE_PERSISTENCE_FAILED", "Issued invoice must persist the exact approved plan and tax amounts");
    }
    await audit(deps, tx, {
      tenantId: scope.tenantId, branchId: null, actorId: scope.actorId,
      action: "saas.billing.invoice_issued", entityType: "saas_invoice",
      entityId: invoice.id, idempotencyKey: scope.idempotencyKey,
    });
    return Object.freeze({
      status: "issued", invoiceId: invoice.id, invoiceNumber: invoice.invoiceNumber,
      subtotalIdr: invoice.subtotalIdr, taxIdr: invoice.taxIdr,
      totalIdr: invoice.totalIdr, dueAt: invoice.dueAt,
    });
  });
}
