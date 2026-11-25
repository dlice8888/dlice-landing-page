import test from "node:test";
import assert from "node:assert/strict";
import { createXenditPayoutV3Adapter, XENDIT_PAYOUT_V3_EVENTS } from "../../src/providers/xendit-payout-v3.mjs";

const payoutBody = {
  reference_id: "DLC-PAYROLL-2026-11-RUN-001",
  recipient: { type: "INDIVIDUAL", given_name: "Test", surname: "Employee", relationship: "EMPLOYEE",
    account_details: { currency: "IDR", account_country: "ID", account_holder_name: "Test Employee",
      account_number: "0000000000", routing_type_1: "BANK_CODE", routing_value_1: "TEST" },
    address: { country: "ID" } },
  payout_details: { source_currency: "IDR", source_amount: 1500000, destination_currency: "IDR" },
  source_of_fund: "BUSINESS_REVENUE", purpose_code: "SALARY",
};
const webhook = { event: "v3_payout.succeeded", business_id: "business-test",
  created: "2026-11-25T10:00:00.000Z",
  data: { payout_id: "po-test-001", status: "SUCCEEDED", reference_id: payoutBody.reference_id,
    source_currency: "IDR", source_amount: 1500000 } };

test("dispatch is locked by default and never calls network", async () => {
  let calls = 0;
  const adapter = createXenditPayoutV3Adapter({ secretApiKey: "xnd_development_test",
    fetchImpl: async () => { calls += 1; throw new Error("must not run"); } });
  await assert.rejects(adapter.executePayrollPaymentProvider({ providerPayload: payoutBody,
    idempotencyKey: "payroll-001" }), { code: "XENDIT_PAYOUT_LIVE_LOCKED" });
  assert.equal(calls, 0);
});

test("dispatch uses v3 headers and stable idempotency key in test mode", async () => {
  let request;
  const adapter = createXenditPayoutV3Adapter({ secretApiKey: "xnd_development_test", enableTestNetwork: true,
    fetchImpl: async (url, init) => {
      request = { url, init };
      return new Response(JSON.stringify({ payout_id: "po-test-001", reference_id: payoutBody.reference_id,
        status: "ACCEPTED" }), { status: 200, headers: { "content-type": "application/json" } });
    } });
  const result = await adapter.executePayrollPaymentProvider({ providerPayload: payoutBody,
    idempotencyKey: "payroll-tenant-a-run-001" });
  assert.equal(request.url, "https://api.xendit.co/v3/payouts");
  assert.equal(request.init.headers["api-version"], "2025-09-01");
  assert.equal(request.init.headers["idempotency-key"], "payroll-tenant-a-run-001");
  assert.match(request.init.headers.authorization, /^Basic /);
  assert.equal(result.providerReference, "po-test-001");
  assert.equal(result.providerStatus, "ACCEPTED");
  assert.equal(result.amountIdr, 1500000);
});

test("production key is rejected even when test networking is enabled", async () => {
  const adapter = createXenditPayoutV3Adapter({ secretApiKey: "xnd_production_never-use",
    enableTestNetwork: true, fetchImpl: async () => { throw new Error("must not run"); } });
  await assert.rejects(adapter.executePayrollPaymentProvider({ providerPayload: payoutBody,
    idempotencyKey: "payroll-002" }), { code: "XENDIT_PAYOUT_LIVE_LOCKED" });
});

test("non-IDR and malformed amounts fail before network", async () => {
  const adapter = createXenditPayoutV3Adapter({ secretApiKey: "xnd_development_test",
    enableTestNetwork: true, fetchImpl: async () => { throw new Error("must not run"); } });
  await assert.rejects(adapter.executePayrollPaymentProvider({ providerPayload: { ...payoutBody,
    payout_details: { ...payoutBody.payout_details, source_currency: "USD" } }, idempotencyKey: "payroll-003" }),
    { code: "XENDIT_PAYOUT_CURRENCY_UNSUPPORTED" });
  await assert.rejects(adapter.executePayrollPaymentProvider({ providerPayload: { ...payoutBody,
    payout_details: { ...payoutBody.payout_details, source_amount: 1.5 } }, idempotencyKey: "payroll-004" }),
    { code: "XENDIT_PAYOUT_INPUT_INVALID" });
});

test("webhook verifies callback token and normalizes settlement evidence", () => {
  const adapter = createXenditPayoutV3Adapter({ secretApiKey: "xnd_development_test",
    webhookToken: "dashboard-webhook-token", fetchImpl: async () => {} });
  const rawBody = JSON.stringify(webhook);
  const evidence = adapter.verifyPayrollPayoutWebhook({ rawBody, callbackToken: "dashboard-webhook-token" });
  assert.equal(evidence.authenticated, true);
  assert.equal(evidence.providerReference, "po-test-001");
  assert.equal(evidence.referenceId, payoutBody.reference_id);
  assert.equal(evidence.providerStatus, "SUCCEEDED");
  assert.equal(evidence.amountIdr, 1500000);
  assert.equal(evidence.eventId, adapter.verifyPayrollPayoutWebhook({ rawBody,
    callbackToken: "dashboard-webhook-token" }).eventId);
});

test("webhook rejects bad token, unknown event and status mismatch", () => {
  const adapter = createXenditPayoutV3Adapter({ secretApiKey: "xnd_development_test",
    webhookToken: "dashboard-webhook-token", fetchImpl: async () => {} });
  const rawBody = JSON.stringify(webhook);
  assert.throws(() => adapter.verifyPayrollPayoutWebhook({ rawBody, callbackToken: "attacker-token" }),
    { code: "XENDIT_WEBHOOK_UNAUTHENTICATED" });
  assert.throws(() => adapter.verifyPayrollPayoutWebhook({ rawBody: JSON.stringify({ ...webhook,
    event: "payment.succeeded" }), callbackToken: "dashboard-webhook-token" }),
    { code: "XENDIT_WEBHOOK_INVALID" });
  assert.throws(() => adapter.verifyPayrollPayoutWebhook({ rawBody: JSON.stringify({ ...webhook,
    data: { ...webhook.data, status: "FAILED" } }), callbackToken: "dashboard-webhook-token" }),
    { code: "XENDIT_WEBHOOK_STATUS_MISMATCH" });
  assert.equal(XENDIT_PAYOUT_V3_EVENTS.length, 5);
});

test("provider response without stable payout identity is not accepted", async () => {
  const adapter = createXenditPayoutV3Adapter({ secretApiKey: "xnd_development_test", enableTestNetwork: true,
    fetchImpl: async () => new Response(JSON.stringify({ status: "ACCEPTED" }), { status: 200 }) });
  await assert.rejects(adapter.executePayrollPaymentProvider({ providerPayload: payoutBody,
    idempotencyKey: "payroll-005" }), { code: "XENDIT_PAYOUT_RESPONSE_UNVERIFIED" });
});
