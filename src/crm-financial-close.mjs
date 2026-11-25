/**
 * Canonical CRM financial-close projection.
 *
 * Inputs must be loaded server-side from tenant-scoped authoritative records.
 * This module validates their joins and arithmetic; it is not a database
 * transaction, authorization layer, or substitute for Finance reconciliation.
 * Never call with client-supplied financial evidence.
 */

function fail(code, message) {
  const error = new Error(message);
  error.code = code;
  throw error;
}

function ref(value, field) {
  if (typeof value !== "string" || value.trim().length < 1) fail("CLOSE_REF_REQUIRED", field);
  return value.trim();
}

function idr(value, field, { positive = false } = {}) {
  if (!Number.isSafeInteger(value) || value < (positive ? 1 : 0)) {
    fail("INVALID_CLOSE_AMOUNT", `${field} must be a safe integer IDR amount`);
  }
  return value;
}

function sameScope(records, tenantId, branchId, field) {
  for (const record of records) {
    if (record.tenantId !== tenantId || record.branchId !== branchId) {
      fail("CROSS_SCOPE_FINANCIAL_EVIDENCE", `${field} contains a record outside the source tenant/branch`);
    }
  }
}

function sum(values, field) {
  const result = values.reduce((total, value) => total + value, 0);
  if (!Number.isSafeInteger(result)) fail("CLOSE_AMOUNT_OVERFLOW", field);
  return result;
}

/**
 * Required shape:
 * source: {id,type,tenantId,branchId,status,subtotalIdr,discountIdr,closedAt}
 * refunds: [{id,tenantId,branchId,sourceId,status,amountIdr}]
 * settlement: {id,tenantId,branchId,sourceId,status,grossIdr,feeIdr,netIdr,receivedIdr,reconciledAt}
 * shift: {id,tenantId,branchId,status,sourceIds[],expectedSalesIdr,receivedSalesIdr}
 * finance: {batchId,tenantId,branchId,status,sourceType,sourceId,debitIdr,creditIdr,sourceReconciledAt}
 * financeExpected: approved mapping-derived revenue/receivable close amount.
 */
export function buildCrmFinancialCloseEvidence(input) {
  const source = input?.source;
  if (!source || !["pos_sale", "online_order"].includes(source.type) ||
      !["paid", "completed"].includes(source.status)) {
    fail("ELIGIBLE_SOURCE_REQUIRED", "A completed POS sale or online order is required");
  }
  const tenantId = ref(source.tenantId, "source.tenantId");
  const branchId = ref(source.branchId, "source.branchId");
  const sourceId = ref(source.id, "source.id");
  const sourceType = source.type;
  const subtotalIdr = idr(source.subtotalIdr, "source.subtotalIdr");
  const discountIdr = idr(source.discountIdr, "source.discountIdr");
  if (discountIdr > subtotalIdr) fail("DISCOUNT_EXCEEDS_SUBTOTAL", "Discount exceeds source subtotal");

  const refunds = input.refunds;
  if (!Array.isArray(refunds)) fail("REFUND_SET_REQUIRED", "Complete source refund set is required");
  sameScope(refunds, tenantId, branchId, "refunds");
  for (const refund of refunds) {
    if (refund.sourceId !== sourceId || refund.status !== "processed") {
      fail("REFUND_SET_NOT_FINAL", "Every linked refund must be processed before earning");
    }
    ref(refund.id, "refund.id");
    idr(refund.amountIdr, "refund.amountIdr");
  }
  const processedRefundsIdr = sum(refunds.map(x => x.amountIdr), "refunds");
  if (processedRefundsIdr > subtotalIdr - discountIdr) {
    fail("REFUND_EXCEEDS_DISCOUNTED_SALE", "Processed refunds exceed discounted sale value");
  }

  const settlement = input.settlement;
  if (!settlement || settlement.tenantId !== tenantId || settlement.branchId !== branchId ||
      settlement.sourceId !== sourceId || settlement.status !== "reconciled" || !settlement.reconciledAt) {
    fail("SETTLEMENT_NOT_RECONCILED", "Source-linked settlement must be reconciled");
  }
  ref(settlement.id, "settlement.id");
  const grossIdr = idr(settlement.grossIdr, "settlement.grossIdr");
  const feeIdr = idr(settlement.feeIdr, "settlement.feeIdr");
  const netIdr = idr(settlement.netIdr, "settlement.netIdr");
  const receivedIdr = idr(settlement.receivedIdr, "settlement.receivedIdr");
  if (grossIdr !== subtotalIdr - discountIdr || netIdr !== grossIdr - feeIdr || receivedIdr !== netIdr) {
    fail("SETTLEMENT_AMOUNT_MISMATCH", "Settlement gross, fee, net and received amount do not reconcile to source");
  }

  const shift = input.shift;
  if (!shift || shift.tenantId !== tenantId || shift.branchId !== branchId ||
      shift.status !== "approved" || !Array.isArray(shift.sourceIds) ||
      shift.sourceIds.filter(x => x === sourceId).length !== 1) {
    fail("SHIFT_CLOSE_NOT_APPROVED", "Approved shift close must include this source exactly once");
  }
  ref(shift.id, "shift.id");
  const expectedSalesIdr = idr(shift.expectedSalesIdr, "shift.expectedSalesIdr");
  const receivedSalesIdr = idr(shift.receivedSalesIdr, "shift.receivedSalesIdr");
  if (expectedSalesIdr !== receivedSalesIdr) {
    fail("SHIFT_SALES_NOT_RECONCILED", "Expected and received shift sales do not reconcile");
  }

  const finance = input.finance;
  if (!finance || finance.tenantId !== tenantId || finance.branchId !== branchId ||
      finance.sourceType !== sourceType || finance.sourceId !== sourceId ||
      !["posted", "reconciled"].includes(finance.status) || !finance.sourceReconciledAt) {
    fail("FINANCE_SOURCE_NOT_RECONCILED", "Posted Finance batch and source reconciliation are required");
  }
  const financeDebitIdr = idr(finance.debitIdr, "finance.debitIdr");
  const financeCreditIdr = idr(finance.creditIdr, "finance.creditIdr");
  if (financeDebitIdr !== financeCreditIdr) {
    fail("FINANCE_BATCH_UNBALANCED", "Finance journal batch must balance");
  }
  const financeExpectedIdr = idr(input.financeExpectedIdr, "financeExpectedIdr");
  if (financeDebitIdr !== financeExpectedIdr) {
    fail("FINANCE_SOURCE_AMOUNT_MISMATCH", "Finance batch does not reconcile to approved source mapping");
  }

  const eligibleNetSalesIdr = subtotalIdr - discountIdr - processedRefundsIdr;
  return Object.freeze({
    status: "reconciled",
    tenantId, branchId, sourceType, sourceId,
    financialCloseId: ref(input.financialCloseId, "financialCloseId"),
    shiftReconciliationId: shift.id,
    shiftReconciliationStatus: "approved",
    settlementReconciliationId: settlement.id,
    settlementReconciliationStatus: "reconciled",
    financeJournalBatchId: ref(finance.batchId, "finance.batchId"),
    financeJournalStatus: finance.status,
    financeSourceReconciliationStatus: "reconciled",
    currency: "IDR",
    subtotalIdr, discountIdr, processedRefundsIdr,
    refundEvidence: Object.freeze(refunds.map(x => Object.freeze({
      id: x.id, status: x.status, amountIdr: x.amountIdr,
    }))),
    eligibleNetSalesIdr,
    closedAt: ref(source.closedAt, "source.closedAt"),
  });
}
