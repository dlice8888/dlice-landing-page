const STATUS = Object.freeze({ SUCCEEDED: "settled", FAILED: "failed", REJECTED: "rejected", REVERSED: "reversed", PENDING_COMPLIANCE_ASSESSMENT: "pending_compliance", ACCEPTED: "submitted", REQUESTED: "submitted", READY: "submitted", ROUTING: "submitted", LOCKED: "submitted", EXPIRED: "failed", CANCELLED: "failed" });

/** Match authenticated provider evidence. Persistence and Finance posting remain in the tenant-scoped workflow. */
export function reconcileXenditPayrollPayoutEvidence({ payment, evidence }) {
  if (!payment || payment.providerId !== "xendit" || !evidence?.authenticated || evidence.provider !== "xendit") {
    throw Object.assign(new Error("Authenticated Xendit payment and webhook evidence are required"), { code: "XENDIT_RECONCILIATION_EVIDENCE_REQUIRED" });
  }
  const mismatches = [];
  if (!payment.providerReference || payment.providerReference !== evidence.providerReference) mismatches.push("provider_reference");
  if (!payment.providerReferenceId || payment.providerReferenceId !== evidence.referenceId) mismatches.push("reference_id");
  if (!Number.isSafeInteger(payment.amountIdr) || payment.amountIdr <= 0 || payment.amountIdr !== evidence.amountIdr) mismatches.push("amount");
  if (payment.currency !== "IDR" || evidence.currency !== "IDR") mismatches.push("currency");
  if (mismatches.length) return Object.freeze({ status: "exception", matched: false, mismatches: Object.freeze(mismatches) });
  const settlementStatus = STATUS[evidence.providerStatus];
  if (!settlementStatus) return Object.freeze({ status: "exception", matched: false, mismatches: Object.freeze(["unsupported_provider_status"]) });
  return Object.freeze({
    status: settlementStatus, matched: true, settled: settlementStatus === "settled",
    reversalRequired: settlementStatus === "reversed", provider: "xendit",
    providerReference: evidence.providerReference, referenceId: evidence.referenceId,
    amountIdr: payment.amountIdr, currency: "IDR", eventId: evidence.eventId,
    failureCode: evidence.failureCode ?? null, occurredAt: evidence.occurredAt,
  });
}
