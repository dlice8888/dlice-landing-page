import test from "node:test";
import assert from "node:assert/strict";
import { ingestXenditPayrollPayoutWebhook } from "../../src/fnb-transactional-workflows.mjs";

const evidence = { authenticated: true, provider: "xendit", businessId: "biz-a",
  providerReference: "po-a", referenceId: "intent-a", amountIdr: 300000,
  currency: "IDR", providerStatus: "SUCCEEDED", eventId: "event-fingerprint-a",
  occurredAt: "2026-11-25T10:00:00Z" };
const payment = { id: "payment-a", tenantId: "tenant-a", branchId: "branch-a",
  providerId: "xendit", providerBusinessId: "biz-a", providerReference: "po-a",
  providerReferenceId: "intent-a", amountIdr: 300000, currency: "IDR" };

function deps({ incoming = evidence, duplicate = false } = {}) {
  let persistedDecision;
  let persistedEventKind;
  return {
    state: () => ({ decision: persistedDecision, eventKind: persistedEventKind }),
    verifyPayrollPayoutWebhook: async () => incoming,
    resolvePayrollPayoutWebhookScope: async () => ({
      tenantId: "tenant-a", branchId: "branch-a", actorId: "system-payout-webhook",
    }),
    withTenantTransaction: async (_scope, callback) => callback({}),
    authorize: async () => {},
    appendAudit: async () => {},
    loadPayrollPaymentForWebhookUpdate: async () => payment,
    persistPayrollPaymentWebhookEvidence: async (_tx, args) => {
      persistedDecision = args.decision;
      persistedEventKind = args.eventKind;
      return { eventId: "stored-event-a", duplicate };
    },
    persistPayrollPaymentWebhookException: async (_tx, args) => {
      persistedDecision = args.decision;
      return { eventId: "stored-exception-a", duplicate };
    },
  };
}

test("verified Xendit payout webhook is reloaded and persisted inside resolved tenant transaction", async () => {
  const repository = deps();
  const result = await ingestXenditPayrollPayoutWebhook({ rawBody: "raw", callbackToken: "verified" }, repository);
  assert.equal(result.status, "settled");
  assert.equal(result.paymentId, "payment-a");
  assert.equal(result.matched, true);
  assert.equal(result.reconciliationRequired, true);
  assert.equal(repository.state().eventKind, "settled");
});

test("webhook for mismatched amount persists as an exception, never as settlement", async () => {
  const repository = deps({ incoming: { ...evidence, amountIdr: 299999 } });
  const result = await ingestXenditPayrollPayoutWebhook({ rawBody: "raw", callbackToken: "verified" }, repository);
  assert.equal(result.status, "exception");
  assert.equal(result.matched, false);
  assert.deepEqual(repository.state().decision.mismatches, ["amount"]);
});

test("duplicate webhook fingerprint is acknowledged without a second business transition", async () => {
  const repository = deps({ duplicate: true });
  const result = await ingestXenditPayrollPayoutWebhook({ rawBody: "raw", callbackToken: "verified" }, repository);
  assert.equal(result.status, "duplicate");
});

test("unauthenticated webhook is rejected before tenant lookup", async () => {
  let resolved = false;
  const repository = deps({ incoming: { ...evidence, authenticated: false } });
  repository.resolvePayrollPayoutWebhookScope = async () => { resolved = true; return {}; };
  await assert.rejects(ingestXenditPayrollPayoutWebhook({ rawBody: "raw", callbackToken: "bad" }, repository),
    { code: "PAYROLL_WEBHOOK_UNAUTHENTICATED" });
  assert.equal(resolved, false);
});

test("provider business ID mismatch is blocked after scoped payment reload", async () => {
  const repository = deps();
  repository.loadPayrollPaymentForWebhookUpdate = async () => ({ ...payment, providerBusinessId: "biz-other" });
  await assert.rejects(ingestXenditPayrollPayoutWebhook({ rawBody: "raw", callbackToken: "verified" }, repository),
    { code: "PAYROLL_WEBHOOK_PROVIDER_SCOPE_MISMATCH" });
});

test("authenticated provider reversal is persisted then quarantined in Finance", async () => {
  let quarantined;
  const repository = deps({ incoming: { ...evidence, providerStatus: "REVERSED", eventId: "reverse-fingerprint" } });
  repository.quarantineReversedPayrollPaymentClearing = async (_tx, args) => {
    quarantined = args;
    return { status: "reversal_exception" };
  };
  const result = await ingestXenditPayrollPayoutWebhook({ rawBody: "raw", callbackToken: "verified" }, repository);
  assert.equal(result.status, "reversed");
  assert.equal(result.reversalException, "reversal_exception");
  assert.equal(quarantined.paymentItemId, payment.id);
  assert.equal(quarantined.providerEventId, "stored-event-a");
});
