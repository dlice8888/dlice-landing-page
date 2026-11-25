import test from "node:test";
import assert from "node:assert/strict";
import { reconcileApprovedPayrollPaymentBatch } from "../../src/fnb-transactional-workflows.mjs";

const scope = { tenantId: "tenant-a", branchId: "branch-a", actorId: "finance-reconciler",
  idempotencyKey: "batch-reconcile-001", paymentBatchId: "batch-a" };
const batch = { id: "batch-a", tenantId: "tenant-a", branchId: "branch-a",
  payrollRunId: "run-a", financePostingId: "posting-a", status: "processing",
  amountIdr: 300000, itemCount: 2 };
const payrollRun = { id: "run-a", tenantId: "tenant-a", branchId: "branch-a",
  status: "reconciled", netAmountIdr: 300000 };
const financePosting = { id: "posting-a", status: "reconciled" };
const items = [
  { id: "item-a", tenantId: "tenant-a", branchId: "branch-a", paymentBatchId: "batch-a",
    providerId: "xendit", providerReference: "po-a", providerReferenceId: "item-a",
    amountIdr: 100000, status: "settled", settledAt: "2026-11-25T10:00:00Z",
    settlementEvidence: { authenticated: true, provider: "xendit", providerReference: "po-a",
      referenceId: "item-a", amountIdr: 100000, currency: "IDR", providerStatus: "SUCCEEDED" } },
  { id: "item-b", tenantId: "tenant-a", branchId: "branch-a", paymentBatchId: "batch-a",
    providerId: "xendit", providerReference: "po-b", providerReferenceId: "item-b",
    amountIdr: 200000, status: "settled", settledAt: "2026-11-25T10:01:00Z",
    settlementEvidence: { authenticated: true, provider: "xendit", providerReference: "po-b",
      referenceId: "item-b", amountIdr: 200000, currency: "IDR", providerStatus: "SUCCEEDED" } },
];

function makeDeps(changes = {}) {
  let persisted;
  return {
    state: () => persisted,
    withTenantTransaction: async (_scope, callback) => callback({}),
    authorize: async () => {},
    appendAudit: async () => {},
    loadPayrollPaymentBatchSettlementEvidence: async () => ({
      batch, payrollRun, financePosting, items, ...changes,
    }),
    persistPayrollPaymentBatchReconciliation: async (_tx, args) => {
      persisted = args;
      return { reconciliationId: "recon-a", status: "reconciled" };
    },
  };
}

test("batch reconciliation matches every settled employee item to the reconciled payroll and Finance source", async () => {
  const deps = makeDeps();
  const result = await reconcileApprovedPayrollPaymentBatch(scope, deps);
  assert.equal(result.status, "reconciled");
  assert.equal(result.itemCount, 2);
  assert.equal(result.settledAmountIdr, 300000);
  assert.equal(deps.state().settledAmountIdr, 300000);
});

test("batch reconciliation blocks any item amount/reference mismatch", async () => {
  const deps = makeDeps({ items: [items[0], { ...items[1],
    settlementEvidence: { ...items[1].settlementEvidence, amountIdr: 199999 } }] });
  await assert.rejects(reconcileApprovedPayrollPaymentBatch(scope, deps),
    { code: "PAYROLL_PAYMENT_ITEM_SETTLEMENT_MISMATCH" });
  assert.equal(deps.state(), undefined);
});

test("batch reconciliation requires Finance posting to be reconciled", async () => {
  const deps = makeDeps({ financePosting: { id: "posting-a", status: "posted" } });
  await assert.rejects(reconcileApprovedPayrollPaymentBatch(scope, deps),
    { code: "PAYROLL_FINANCE_SOURCE_NOT_RECONCILED" });
});

test("batch reconciliation rejects duplicate provider payout IDs", async () => {
  const deps = makeDeps({ items: [items[0], { ...items[1], providerReference: "po-a",
    settlementEvidence: { ...items[1].settlementEvidence, providerReference: "po-a" } }] });
  await assert.rejects(reconcileApprovedPayrollPaymentBatch(scope, deps),
    { code: "PAYROLL_PROVIDER_REFERENCE_DUPLICATE" });
});
