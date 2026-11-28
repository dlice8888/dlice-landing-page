import test from "node:test";
import assert from "node:assert/strict";
import { validateCashDrawerMovement, reconcileCashDrawer } from "../../src/pos-cash-drawer.mjs";

const shift = { id: "shift-1", branch_id: "branch-1", opened_by: "cashier-1", status: "open", opening_cash_idr: 100000 };
const scope = ["branch-1"];

test("cash drawer movements require owned open shift, reason and idempotency key", () => {
  const command = validateCashDrawerMovement({
    shift, actorUserId: "cashier-1", assignedBranchIds: scope,
    direction: "in", amountIdr: 20000, reason: "Petty cash return",
    idempotencyKey: "cash-move-000001",
  });
  assert.equal(command.amount_idr, 20000);
  assert.throws(() => validateCashDrawerMovement({
    shift, actorUserId: "cashier-2", assignedBranchIds: scope,
    direction: "out", amountIdr: 1000, reason: "Expense", idempotencyKey: "cash-move-000002",
  }), /cash_drawer_actor_forbidden/);
  assert.throws(() => validateCashDrawerMovement({
    shift, actorUserId: "cashier-1", assignedBranchIds: ["branch-2"],
    direction: "out", amountIdr: 1000, reason: "Expense", idempotencyKey: "cash-move-000003",
  }), /cash_drawer_branch_forbidden/);
  assert.throws(() => validateCashDrawerMovement({
    shift, actorUserId: "cashier-1", assignedBranchIds: scope,
    direction: "out", amountIdr: 1000, reason: "x", idempotencyKey: "short",
  }), /cash_drawer_reason_required|cash_drawer_idempotency_key_required/);
});

test("drawer reconciliation replays tender and movements and records positive or negative variance", () => {
  const result = reconcileCashDrawer({
    shift, cashSalesIdr: 250000, cashRefundsIdr: 10000,
    movements: [
      { id: "m1", shift_id: shift.id, branch_id: shift.branch_id, direction: "in", amount_idr: 20000 },
      { id: "m2", shift_id: shift.id, branch_id: shift.branch_id, direction: "out", amount_idr: 5000 },
    ],
    countedCashIdr: 354000, actorUserId: "cashier-1", assignedBranchIds: scope,
    varianceApprovalThresholdIdr: 1000,
  });
  assert.equal(result.expected_cash_idr, 355000);
  assert.equal(result.variance_idr, -1000);
  assert.throws(() => reconcileCashDrawer({
    shift, cashSalesIdr: 250000, cashRefundsIdr: 10000,
    movements: [{ id: "m1", shift_id: shift.id, branch_id: shift.branch_id, direction: "in", amount_idr: 20000 }],
    countedCashIdr: 400000, actorUserId: "cashier-1", assignedBranchIds: scope,
    varianceApprovalThresholdIdr: 1000,
  }), /cash_drawer_variance_approval_required/);
});

test("drawer close rejects duplicate or cross-shift movements and pending sales", () => {
  const movement = { id: "m1", shift_id: shift.id, branch_id: shift.branch_id, direction: "in", amount_idr: 1000 };
  const common = {
    shift, cashSalesIdr: 0, movements: [movement], countedCashIdr: 101000,
    actorUserId: "cashier-1", assignedBranchIds: scope,
  };
  assert.throws(() => reconcileCashDrawer({ ...common, movements: [movement, movement] }), /cash_drawer_duplicate_movement/);
  assert.throws(() => reconcileCashDrawer({ ...common, pendingSaleCount: 1 }), /cash_drawer_pending_sales/);
  assert.throws(() => reconcileCashDrawer({
    ...common, movements: [{ ...movement, shift_id: "other" }],
  }), /cash_drawer_movement_scope_mismatch/);
});
