import test from "node:test";
import assert from "node:assert/strict";
import {
  awardLoyaltyForFinancialClose,
  persistApprovedPayrollRun,
  ingestSignedDeliveryWebhook,
  provisionApprovedFranchise,
  meterCommittedTenantOperation,
  readAuthorizedExecutiveDrilldown,
  dispatchApprovedCampaignMessage,
  ingestSignedCampaignReceipt,
  executeApprovedPayrollPayment,
  reconcileApprovedPayrollPayment,
  enforceSaasTenantEntitlement,
  issueSaasSubscriptionInvoice,
  requestDeliveryQuotes,
  bookDeliveryDispatch,
  buildCrmFinancialCloseProjection,
  calculateAndPersistPayrollRun,
  createReconciledFranchiseRoyaltyStatement,
  postMatchedSupplierInvoiceToApJournal,
  publishExecutiveBranchRanking,
  runScheduledBiKpiIngestion
} from "../../src/fnb-transactional-workflows.mjs";

const base = { tenantId: "tenant-a", branchId: "branch-a", actorId: "actor-a", idempotencyKey: "workflow-key-0001" };

test("CRM award fails closed when tenant transaction adapter is missing", async () => {
  await assert.rejects(
    awardLoyaltyForFinancialClose({ ...base, sourceType: "pos_sale", sourceId: "sale-a" }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("payroll posting fails closed without trusted authorization and transaction ports", async () => {
  await assert.rejects(
    persistApprovedPayrollRun({ ...base, payrollRunId: "run-a" }, { withTenantTransaction: async (_scope, callback) => callback({}) }),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("delivery webhook refuses unsigned or incomplete provider events", async () => {
  await assert.rejects(
    ingestSignedDeliveryWebhook({ ...base, providerId: "provider-a", rawBody: "{}", signature: "", timestamp: "1" }, {
      getProviderWebhookSecret: () => "0123456789abcdef",
    }),
    { code: "SIGNATURE_REQUIRED" },
  );
});

test("franchise provisioning requires a transactional repository adapter", async () => {
  await assert.rejects(
    provisionApprovedFranchise({ ...base, applicationId: "application-a" }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("SaaS usage cannot be metered before authoritative commit", async () => {
  await assert.rejects(
    meterCommittedTenantOperation({
      operationResult: { committed: false }, tenantId: "tenant-a",
      entitlementKey: "orders", sourceEntity: "order", sourceId: "order-a",
      idempotencyKey: "usage-key-0001", occurredAt: "2026-11-25T00:00:00.000Z",
    }, { recordUsage: async () => ({ usage_event_id: "usage-a" }) }),
    { code: "AUTHORITATIVE_COMMIT_REQUIRED" },
  );
});

test("executive drilldown requires tenant-scoped hierarchy and authorization adapters", async () => {
  await assert.rejects(
    readAuthorizedExecutiveDrilldown({ ...base, hierarchy: [{ type: "company", id: "company-a" }] }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("executive drilldown rejects empty and over-deep hierarchy before repository access", async () => {
  const deps = {
    withTenantTransaction: async (_scope, callback) => callback({}),
    authorize: async () => {},
    appendAudit: async () => {},
  };
  await assert.rejects(
    readAuthorizedExecutiveDrilldown({ ...base, hierarchy: [] }, deps),
    { code: "EXECUTIVE_HIERARCHY_REQUIRED" },
  );
  await assert.rejects(
    readAuthorizedExecutiveDrilldown({ ...base, hierarchy: Array.from({ length: 6 }, () => ({ type: "company", id: "x" })) }, deps),
    { code: "EXECUTIVE_HIERARCHY_REQUIRED" },
  );
});

test("campaign dispatch requires server-side transactional authorization", async () => {
  await assert.rejects(
    dispatchApprovedCampaignMessage({ ...base, campaignId: "campaign-a", customerId: "customer-a" }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("campaign receipts cannot be applied without a provider signature verifier", async () => {
  await assert.rejects(
    ingestSignedCampaignReceipt({ ...base, providerId: "provider-a", rawBody: "{}", signature: "bad", timestamp: "1" }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("payroll payment requires a tenant transaction and authorization", async () => {
  await assert.rejects(
    executeApprovedPayrollPayment({ ...base, payrollRunId: "run-a" }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("payroll settlement cannot be reconciled without persisted evidence adapters", async () => {
  await assert.rejects(
    reconcileApprovedPayrollPayment({ ...base, payrollRunId: "run-a" }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});


test("SaaS entitlement enforcement fails closed without a tenant transaction", async () => {
  await assert.rejects(
    enforceSaasTenantEntitlement({
      tenantId: "tenant-a", actorId: "actor-a", idempotencyKey: "saas-entitlement-0001",
      entitlementKey: "orders", quantity: 1,
    }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("SaaS invoice issuance fails closed without a tenant transaction", async () => {
  await assert.rejects(
    issueSaasSubscriptionInvoice({
      tenantId: "tenant-a", actorId: "actor-a", idempotencyKey: "saas-invoice-0001",
      subscriptionId: "subscription-a", periodStart: "2026-11-01", periodEnd: "2026-11-30",
    }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});


test("delivery quote requests fail closed without tenant-scoped repository adapters", async () => {
  await assert.rejects(
    requestDeliveryQuotes({
      ...base, sourceType: "online_order", sourceId: "order-a",
    }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("delivery booking fails closed without a durable booking-intent adapter", async () => {
  await assert.rejects(
    bookDeliveryDispatch({
      ...base, quoteId: "quote-a", customerAcceptedQuote: true,
    }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});


test("CRM close projection requires authoritative transaction adapters", async () => {
  await assert.rejects(
    buildCrmFinancialCloseProjection({
      ...base, sourceType: "pos_sale", sourceId: "sale-a", financialCloseId: "close-a",
    }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("payroll calculation requires locked run and approved time adapters", async () => {
  await assert.rejects(
    calculateAndPersistPayrollRun({ ...base, payrollRunId: "run-a" }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("franchise royalty requires tenant-scoped agreement and reconciled close adapters", async () => {
  await assert.rejects(
    createReconciledFranchiseRoyaltyStatement({
      ...base, agreementId: "agreement-a", periodStart: "2026-11-01", periodEnd: "2026-11-30",
    }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("supplier AP journal requires tenant transaction and independent approval adapters", async () => {
  await assert.rejects(
    postMatchedSupplierInvoiceToApJournal({ ...base, invoiceId: "invoice-a" }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("executive branch ranking requires an authoritative complete branch scope", async () => {
  await assert.rejects(
    publishExecutiveBranchRanking({
      ...base, periodStart: "2026-11-01", periodEnd: "2026-11-30",
    }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});

test("scheduled BI ingestion requires active governed KPI definitions", async () => {
  await assert.rejects(
    runScheduledBiKpiIngestion({
      ...base, periodStart: "2026-11-01", periodEnd: "2026-11-30",
    }, {}),
    { code: "WORKFLOW_ADAPTER_REQUIRED" },
  );
});
