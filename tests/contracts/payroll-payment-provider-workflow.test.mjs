import test from "node:test";
import assert from "node:assert/strict";
import { executeApprovedPayrollPayment } from "../../src/fnb-transactional-workflows.mjs";

const base = { tenantId: "tenant-a", branchId: "branch-a", actorId: "actor-a",
  idempotencyKey: "payroll-payment-idempotency-001", payrollRunId: "run-a" };
function dependencies(payload) {
  let dispatched = false;
  return {
    state: () => ({ dispatched }),
    withTenantTransaction: async (_scope, callback) => callback({}),
    authorize: async () => {},
    appendAudit: async () => {},
    loadApprovedPayrollRunForPayment: async () => ({ id: "run-a", tenantId: "tenant-a", branchId: "branch-a" }),
    loadApprovedPostedPayrollJournal: async () => ({ status: "posted", debitIdr: 250000, creditIdr: 250000 }),
    findPayrollPaymentIntent: async () => null,
    createPayrollPaymentIntent: async () => ({ intentId: "intent-a", providerReferenceId: "intent-a",
      providerId: "xendit", amountIdr: 250000, beneficiaryReference: "vault-token-a" }),
    loadApprovedPayrollPayoutProviderPayload: async () => payload,
    executePayrollPaymentProvider: async (args) => {
      dispatched = true;
      assert.equal(args.providerPayload, payload);
      assert.equal(args.idempotencyKey, base.idempotencyKey);
      return { accepted: true, providerReference: "po-test-a" };
    },
    finalizePayrollPaymentIntent: async () => ({ paymentId: "payment-a", status: "submitted" }),
  };
}

test("approved payroll payment binds provider payload to amount, IDR currency and immutable intent reference", async () => {
  const payload = { reference_id: "intent-a", recipient: { account_details: { account_number: "vault-token-resolved" } },
    payout_details: { source_amount: 250000, source_currency: "IDR", destination_currency: "IDR" } };
  const deps = dependencies(payload);
  const result = await executeApprovedPayrollPayment(base, deps);
  assert.equal(result.status, "submitted_for_settlement");
  assert.equal(result.providerReference, "po-test-a");
  assert.equal(deps.state().dispatched, true);
});

test("provider payload mismatch fails closed before payout dispatch", async () => {
  const payload = { reference_id: "wrong", payout_details: {
    source_amount: 1, source_currency: "IDR", destination_currency: "IDR" } };
  const deps = dependencies(payload);
  await assert.rejects(executeApprovedPayrollPayment(base, deps),
    { code: "PAYROLL_PROVIDER_PAYLOAD_MISMATCH" });
  assert.equal(deps.state().dispatched, false);
});
