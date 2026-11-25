/**
 * CRM loyalty earning gate for a canonical, reconciled transaction close.
 *
 * This adapter intentionally refuses raw POS/order/payment rows. The caller
 * must construct this evidence object from authoritative, tenant-scoped source
 * records and a completed Finance close. Payment "paid" or settlement "matched"
 * alone is not sufficient.
 */

function reject(code, message) {
  const error = new Error(message);
  error.code = code;
  throw error;
}

function amount(value, field) {
  if (!Number.isSafeInteger(value) || value < 0) {
    reject("INVALID_FINANCIAL_AMOUNT", `${field} must be a non-negative safe integer IDR amount`);
  }
  return value;
}

function requiredRef(value, field) {
  if (typeof value !== "string" || !value.trim()) reject("CLOSE_EVIDENCE_REQUIRED", field);
  return value.trim();
}

/**
 * Requires a canonical financial-close projection with:
 * - exact POS/order source identity and tenant/branch attribution;
 * - reconciled source close, approved shift/cash close;
 * - all refunds in processed state and a complete refund total;
 * - settlement reconciliation (not merely provider "matched");
 * - posted Finance journal batch and source reconciliation.
 *
 * The projection is a contract, not a claim that the current staging schema
 * already provides these fields. No award is written by this function.
 */
export function calculateEligibleLoyaltyAward(close, earningRule) {
  if (!close || close.status !== "reconciled") {
    reject("FINANCIAL_CLOSE_NOT_RECONCILED", "Transaction financial close must be reconciled");
  }
  const tenantId = requiredRef(close.tenantId, "tenantId");
  const branchId = requiredRef(close.branchId, "branchId");
  const sourceId = requiredRef(close.sourceId, "sourceId");
  const sourceType = close.sourceType;
  if (!["pos_sale", "online_order"].includes(sourceType)) {
    reject("UNSUPPORTED_LOYALTY_SOURCE", "Only verified POS sale or online order sources are eligible");
  }
  requiredRef(close.financialCloseId, "financialCloseId");
  requiredRef(close.shiftReconciliationId, "shiftReconciliationId");
  requiredRef(close.settlementReconciliationId, "settlementReconciliationId");
  requiredRef(close.financeJournalBatchId, "financeJournalBatchId");

  if (close.shiftReconciliationStatus !== "approved") {
    reject("SHIFT_RECONCILIATION_NOT_APPROVED", "Shift/cash reconciliation must be approved");
  }
  if (close.settlementReconciliationStatus !== "reconciled") {
    reject("SETTLEMENT_NOT_RECONCILED", "Settlement must be reconciled, not merely matched");
  }
  if (!["posted", "reconciled"].includes(close.financeJournalStatus) ||
      close.financeSourceReconciliationStatus !== "reconciled") {
    reject("FINANCE_JOURNAL_NOT_RECONCILED", "Finance journal and source reconciliation must be complete");
  }
  if (close.currency !== "IDR") reject("UNSUPPORTED_CURRENCY", "Only IDR close snapshots are supported");

  const subtotal = amount(close.subtotalIdr, "subtotalIdr");
  const discount = amount(close.discountIdr, "discountIdr");
  const processedRefunds = amount(close.processedRefundsIdr, "processedRefundsIdr");
  if (discount > subtotal || processedRefunds > subtotal - discount) {
    reject("DISCOUNT_OR_REFUND_EXCEEDS_SOURCE", "Discount/refund total exceeds eligible source value");
  }

  if (!Array.isArray(close.refundEvidence) ||
      close.refundEvidence.some((refund) =>
        refund.status !== "processed" || !refund.id || !Number.isSafeInteger(refund.amountIdr) || refund.amountIdr < 0
      )) {
    reject("REFUND_EVIDENCE_INCOMPLETE", "Every refund must have a processed status and immutable source reference");
  }
  const refundSum = close.refundEvidence.reduce((sum, refund) => sum + refund.amountIdr, 0);
  if (refundSum !== processedRefundsIdrSafe(processedRefunds)) {
    reject("REFUND_TOTAL_MISMATCH", "Processed refund evidence does not reconcile to the close total");
  }

  const eligibleNetSalesIdr = subtotal - discount - processedRefunds;
  if (!earningRule || earningRule.approved !== true || !earningRule.version ||
      !Number.isSafeInteger(earningRule.pointsPerThousandIdr) ||
      earningRule.pointsPerThousandIdr < 0) {
    reject("APPROVED_EARNING_RULE_REQUIRED", "An approved, versioned points rule is required");
  }
  const points = Math.floor(eligibleNetSalesIdr / 1000) * earningRule.pointsPerThousandIdr;
  if (!Number.isSafeInteger(points)) reject("LOYALTY_POINTS_OUT_OF_RANGE", "Calculated points exceed safe integer range");

  return Object.freeze({
    tenantId,
    branchId,
    sourceType,
    sourceId,
    financialCloseId: close.financialCloseId,
    eligibleNetSalesIdr,
    points,
    currency: "IDR",
    idempotencyKey: `crm-earn:${tenantId}:${sourceType}:${sourceId}:${earningRule.version}`,
    earningRuleVersion: earningRule.version,
    status: "eligible_not_awarded",
  });
}

function processedRefundsIdrSafe(value) {
  return value;
}
