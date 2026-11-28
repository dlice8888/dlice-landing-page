/**
 * Cash drawer ledger invariants. Persistence must use atomic, idempotent RPCs.
 * This module computes expected cash from immutable movement/tender inputs.
 */
const amount = (value, field) => {
  if (!Number.isSafeInteger(value) || value < 0) throw new TypeError(field + "_invalid");
  return value;
};
const key = (value) => typeof value === "string" && value.trim().length >= 12;

export function validateCashDrawerMovement({
  shift, actorUserId, assignedBranchIds, direction, amountIdr, reason, idempotencyKey,
}) {
  if (!shift || shift.status !== "open") throw new Error("cash_drawer_shift_not_open");
  if (!assignedBranchIds?.includes(shift.branch_id)) throw new Error("cash_drawer_branch_forbidden");
  if (shift.opened_by !== actorUserId) throw new Error("cash_drawer_actor_forbidden");
  if (!["in", "out"].includes(direction)) throw new TypeError("cash_drawer_direction_invalid");
  const value = amount(amountIdr, "cash_drawer_amount");
  if (value === 0) throw new RangeError("cash_drawer_amount_must_be_positive");
  if (typeof reason !== "string" || reason.trim().length < 3) throw new Error("cash_drawer_reason_required");
  if (!key(idempotencyKey)) throw new Error("cash_drawer_idempotency_key_required");
  return Object.freeze({
    shift_id: shift.id, branch_id: shift.branch_id, actor_user_id: actorUserId,
    direction, amount_idr: value, reason: reason.trim().slice(0, 300),
    idempotency_key: idempotencyKey,
  });
}

export function reconcileCashDrawer({
  shift, cashSalesIdr, cashRefundsIdr = 0, movements = [], countedCashIdr,
  pendingSaleCount = 0, varianceApprovalThresholdIdr = Number.MAX_SAFE_INTEGER,
  varianceApproved = false, varianceApprovedBy, actorUserId, assignedBranchIds,
}) {
  if (!shift || shift.status !== "open") throw new Error("cash_drawer_shift_not_open");
  if (!assignedBranchIds?.includes(shift.branch_id)) throw new Error("cash_drawer_branch_forbidden");
  if (shift.opened_by !== actorUserId) throw new Error("cash_drawer_actor_forbidden");
  if (pendingSaleCount !== 0) throw new Error("cash_drawer_pending_sales");
  const opening = amount(shift.opening_cash_idr, "opening_cash");
  const sales = amount(cashSalesIdr, "cash_sales");
  const refunds = amount(cashRefundsIdr, "cash_refunds");
  let cashIn = 0, cashOut = 0;
  const seen = new Set();
  for (const movement of movements) {
    if (!movement?.id || seen.has(movement.id)) throw new Error("cash_drawer_duplicate_movement");
    seen.add(movement.id);
    if (movement.shift_id !== shift.id || movement.branch_id !== shift.branch_id) throw new Error("cash_drawer_movement_scope_mismatch");
    if (movement.status !== "posted") continue;
    const value = amount(movement.amount_idr, "movement_amount");
    if (movement.direction === "in") cashIn += value;
    else if (movement.direction === "out") cashOut += value;
    else throw new Error("cash_drawer_direction_invalid");
  }
  const expected = opening + sales + cashIn - cashOut - refunds;
  if (!Number.isSafeInteger(expected) || expected < 0) throw new RangeError("cash_drawer_expected_out_of_range");
  const counted = amount(countedCashIdr, "counted_cash");
  const variance = counted - expected;
  const threshold = amount(varianceApprovalThresholdIdr, "variance_threshold");
  if (Math.abs(variance) > threshold && (!varianceApproved || !varianceApprovedBy || varianceApprovedBy === actorUserId)) throw new Error("cash_drawer_variance_approval_required");
  return Object.freeze({
    shift_id: shift.id, expected_cash_idr: expected, counted_cash_idr: counted,
    variance_idr: variance, cash_in_idr: cashIn, cash_out_idr: cashOut,
    cash_sales_idr: sales, cash_refunds_idr: refunds,
    requires_approval: Math.abs(variance) > threshold,
    variance_approved_by: Math.abs(variance) > threshold ? varianceApprovedBy : null,
  });
}
