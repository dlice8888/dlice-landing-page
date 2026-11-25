import test from "node:test";
import assert from "node:assert/strict";
import { executeApprovedPayrollPaymentBatch } from "../../src/fnb-transactional-workflows.mjs";

const scope = { tenantId: "tenant-a", branchId: "branch-a", actorId: "actor-a", idempotencyKey: "batch-approve-001", paymentBatchId: "batch-a" };
const batch = { id: "batch-a", tenantId: "tenant-a", branchId: "branch-a", providerId: "xendit", status: "approved", itemCount: 2 };
const items = [
  { id: "item-a", paymentBatchId: "batch-a", tenantId: "tenant-a", branchId: "branch-a", status: "pending", amountIdr: 100000, beneficiaryReference: "vault-a" },
  { id: "item-b", paymentBatchId: "batch-a", tenantId: "tenant-a", branchId: "branch-a", status: "pending", amountIdr: 200000, beneficiaryReference: "vault-b" },
];

function makeDeps(currentItems = items) {
  const dispatched = [];
  return {
    dispatched,
    withTenantTransaction: async (_scope, callback) => callback({}),
    authorize: async () => {},
    appendAudit: async () => {},
    loadApprovedPayrollPaymentBatchForExecution: async () => batch,
    loadPayrollPaymentItemsForExecution: async () => currentItems,
    loadApprovedPayrollPayoutProviderPayload: async (_tx, args) => ({
      reference_id: args.providerReferenceId,
      recipient: { account_details: { account_number: "resolved-in-vault" } },
      payout_details: { source_amount: args.amountIdr, source_currency: "IDR", destination_currency: "IDR" },
      source_of_fund: "BUSINESS_REVENUE", purpose_code: "SALARY",
    }),
    executePayrollPaymentProvider: async (args) => {
      dispatched.push(args);
      return { accepted: true, providerReference: "po-" + args.paymentItemId, providerStatus: "ACCEPTED" };
    },
    finalizePayrollPaymentItemSubmission: async (_tx, args) => ({ paymentItemId: args.paymentItemId, status: "accepted" }),
  };
}

test("payroll batch dispatches a separate payout and idempotency key for each employee item", async () => {
  const deps = makeDeps();
  const result = await executeApprovedPayrollPaymentBatch(scope, deps);
  assert.equal(result.status, "submitted_for_settlement");
  assert.equal(result.submittedCount, 2);
  assert.equal(deps.dispatched.length, 2);
  assert.notEqual(deps.dispatched[0].idempotencyKey, deps.dispatched[1].idempotencyKey);
  assert.equal(deps.dispatched[0].providerPayload.reference_id, "item-a");
  assert.equal(deps.dispatched[1].providerPayload.reference_id, "item-b");
  assert.equal(deps.dispatched[0].amountIdr, 100000);
  assert.equal(deps.dispatched[1].amountIdr, 200000);
});

test("payroll batch skips already accepted or settled items and only dispatches pending items", async () => {
  const current = [
    { ...items[0], status: "accepted" },
    { ...items[1], status: "pending" },
  ];
  const deps = makeDeps(current);
  const result = await executeApprovedPayrollPaymentBatch(scope, deps);
  assert.equal(result.submittedCount, 1);
  assert.equal(result.skippedCount, 1);
  assert.equal(deps.dispatched.length, 1);
  assert.equal(deps.dispatched[0].paymentItemId, "item-b");
});

test("payroll batch rejects item payload mismatch before provider call", async () => {
  const deps = makeDeps();
  deps.loadApprovedPayrollPayoutProviderPayload = async () => ({
    reference_id: "wrong-reference",
    payout_details: { source_amount: 1, source_currency: "IDR", destination_currency: "IDR" },
  });
  await assert.rejects(executeApprovedPayrollPaymentBatch(scope, deps),
    { code: "PAYROLL_PROVIDER_PAYLOAD_MISMATCH" });
  assert.equal(deps.dispatched.length, 0);
});

test("payroll batch requires complete persisted item count", async () => {
  const deps = makeDeps([items[0]]);
  await assert.rejects(executeApprovedPayrollPaymentBatch(scope, deps),
    { code: "PAYROLL_PAYMENT_BATCH_ITEMS_INCOMPLETE" });
  assert.equal(deps.dispatched.length, 0);
});
