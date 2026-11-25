import test from "node:test";
import assert from "node:assert/strict";
import {
  awardLoyaltyForFinancialClose,
  persistApprovedPayrollRun,
  ingestSignedDeliveryWebhook,
  provisionApprovedFranchise,
  meterCommittedTenantOperation,
  readAuthorizedExecutiveDrilldown,
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
    persistApprovedPayrollRun({ ...base, payrollRunId: "run-a" }, { withTenantTransaction: async () => null }),
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
