/** POS shift and drawer invariants. Mutations must be performed by atomic server RPCs. */
const money = (v, name) => {
  if (!Number.isSafeInteger(v) || v < 0) throw new TypeError(name + "_invalid");
  return v;
};
export function calculateExpectedDrawer({ openingCashIdr, cashSalesIdr, cashInIdr=0, cashOutIdr=0, cashRefundsIdr=0 }) {
  const opening=money(openingCashIdr,"opening_cash"), sales=money(cashSalesIdr,"cash_sales");
  const cashIn=money(cashInIdr,"cash_in"), cashOut=money(cashOutIdr,"cash_out"), refunds=money(cashRefundsIdr,"cash_refunds");
  const expected=opening+sales+cashIn-cashOut-refunds;
  if (!Number.isSafeInteger(expected) || expected < 0) throw new RangeError("drawer_expected_out_of_range");
  return expected;
}
export function assertShiftOpenAllowed({ existingOpenShift, actorUserId, assignedBranchIds, branchId, openingCashIdr }) {
  if (!actorUserId || !branchId || !Array.isArray(assignedBranchIds) || !assignedBranchIds.includes(branchId)) throw new Error("shift_branch_forbidden");
  if (existingOpenShift) throw new Error("shift_already_open");
  money(openingCashIdr,"opening_cash");
  return Object.freeze({ branch_id:branchId, opened_by:actorUserId, opening_cash_idr:openingCashIdr });
}
export function assertShiftCloseAllowed({ shift, actorUserId, assignedBranchIds, pendingSaleCount=0, countedCashIdr, varianceApprovalRequired=false, varianceApproved=false }) {
  if (!shift || shift.status!=="open") throw new Error("shift_not_open");
  if (!assignedBranchIds?.includes(shift.branch_id)) throw new Error("shift_branch_forbidden");
  if (shift.opened_by!==actorUserId && !varianceApprovalRequired) throw new Error("shift_actor_forbidden");
  if (!Number.isSafeInteger(pendingSaleCount) || pendingSaleCount<0) throw new TypeError("pending_sale_count_invalid");
  if (pendingSaleCount>0) throw new Error("shift_has_pending_sales");
  const expected=money(shift.expected_cash_idr,"expected_cash");
  const counted=money(countedCashIdr,"counted_cash");
  const variance=counted-expected;
  if (varianceApprovalRequired && !varianceApproved) throw new Error("variance_approval_required");
  return Object.freeze({ shift_id:shift.id, closed_by:actorUserId, expected_cash_idr:expected, counted_cash_idr:counted, cash_variance_idr:variance });
}
