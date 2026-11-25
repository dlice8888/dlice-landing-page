import test from "node:test";
import assert from "node:assert/strict";
import { reconcileXenditPayrollPayoutEvidence } from "../../src/providers/xendit-payout-reconciliation.mjs";

const payment = { providerId: "xendit", providerReference: "po-001",
  providerReferenceId: "intent-001", amountIdr: 500000, currency: "IDR" };
const evidence = { authenticated: true, provider: "xendit", providerReference: "po-001",
  referenceId: "intent-001", amountIdr: 500000, currency: "IDR",
  providerStatus: "SUCCEEDED", eventId: "sha256-event", occurredAt: "2026-11-25T10:00:00Z" };

test("settlement is matched only when payout ID, reference, IDR amount and currency all match", () => {
  const result = reconcileXenditPayrollPayoutEvidence({ payment, evidence });
  assert.equal(result.status, "settled");
  assert.equal(result.settled, true);
  assert.equal(result.matched, true);
});

test("mismatched provider evidence is an exception, not a partial settlement", () => {
  const result = reconcileXenditPayrollPayoutEvidence({ payment,
    evidence: { ...evidence, amountIdr: 499999, providerReference: "po-other" } });
  assert.equal(result.status, "exception");
  assert.equal(result.matched, false);
  assert.deepEqual(result.mismatches, ["provider_reference", "amount"]);
});

test("reversal is surfaced as a compensating event requirement", () => {
  const result = reconcileXenditPayrollPayoutEvidence({ payment,
    evidence: { ...evidence, providerStatus: "REVERSED" } });
  assert.equal(result.status, "reversed");
  assert.equal(result.reversalRequired, true);
  assert.equal(result.settled, false);
});

test("unauthenticated webhook evidence cannot be reconciled", () => {
  assert.throws(() => reconcileXenditPayrollPayoutEvidence({ payment,
    evidence: { ...evidence, authenticated: false } }),
    { code: "XENDIT_RECONCILIATION_EVIDENCE_REQUIRED" });
});
