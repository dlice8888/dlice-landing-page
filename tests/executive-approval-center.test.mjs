import test from "node:test";
import assert from "node:assert/strict";
import { assertApprovalClaim, assertApprovalDecision, rankPendingApprovals } from "../src/executive-approval-center.mjs";

const now = "2026-11-28T10:00:00.000Z";
const approval = {
  id: "ap-1", branch_id: "b1", domain: "finance", status: "pending",
  version: 3, expires_at: "2026-11-28T12:00:00.000Z",
  created_at: "2026-11-28T09:00:00.000Z", created_by: "maker",
  eligible_roles: ["tenant_owner", "finance_approver"], separation_of_duties: true,
  claimed_by: "approver", claim_expires_at: "2026-11-28T11:00:00.000Z",
  amount_idr: 500000,
};
const actor = {
  user_id: "approver", role: "finance_approver", allowed_branch_ids: ["b1"],
  allowed_domains: ["finance"], max_approval_amount_idr: 1000000,
};

test("approval inbox ranks expiry urgency, then amount, then age", () => {
  const rows = [
    { id: "later", status: "pending", expires_at: "2026-11-28T14:00:00Z", amount_idr: 900000, created_at: "2026-11-28T08:00:00Z" },
    { id: "urgent-low", status: "pending", expires_at: "2026-11-28T10:30:00Z", amount_idr: 1000, created_at: "2026-11-28T09:00:00Z" },
    { id: "urgent-high", status: "pending", expires_at: "2026-11-28T10:30:00Z", amount_idr: 9000, created_at: "2026-11-28T09:30:00Z" },
    { id: "expired", status: "pending", expires_at: "2026-11-28T09:59:00Z", amount_idr: 9999999, created_at: "2026-11-28T08:00:00Z" },
  ];
  assert.deepEqual(rankPendingApprovals(rows, now).map((x) => x.id), ["urgent-high", "urgent-low", "later"]);
});

test("claim rejects self-approval, wrong branch, stale version and active competing claim", () => {
  assert.throws(() => assertApprovalClaim({ approval: { ...approval, created_by: actor.user_id }, actor, expectedVersion: 3, now }), /self_approval_forbidden/);
  assert.throws(() => assertApprovalClaim({ approval, actor: { ...actor, allowed_branch_ids: ["b2"] }, expectedVersion: 3, now }), /approval_branch_forbidden/);
  assert.throws(() => assertApprovalClaim({ approval, actor, expectedVersion: 2, now }), /stale_approval_version/);
  assert.throws(() => assertApprovalClaim({ approval: { ...approval, claimed_by: "other" }, actor, expectedVersion: 3, now }), /approval_already_claimed/);
});

test("decision requires live claim, policy scope, role, amount limit and rejection reason", () => {
  assert.throws(() => assertApprovalDecision({ approval, actor: { ...actor, max_approval_amount_idr: 1000 }, decision: "approved", expectedVersion: 3, now }), /approval_amount_limit_exceeded/);
  assert.throws(() => assertApprovalDecision({ approval, actor: { ...actor, allowed_domains: ["hr"] }, decision: "approved", expectedVersion: 3, now }), /approval_domain_forbidden/);
  assert.throws(() => assertApprovalDecision({ approval, actor, decision: "rejected", reason: "no", expectedVersion: 3, now }), /rejection_reason_required/);
  const result = assertApprovalDecision({ approval, actor, decision: "approved", expectedVersion: 3, now });
  assert.equal(result.approval_id, "ap-1");
  assert.equal(result.policy_version, "approval-policy.v1");
});

test("decision rejects expired approval and stale concurrent update", () => {
  assert.throws(() => assertApprovalDecision({ approval, actor, decision: "approved", expectedVersion: 2, now }), /stale_approval_version/);
  assert.throws(() => assertApprovalDecision({ approval: { ...approval, expires_at: now }, actor, decision: "approved", expectedVersion: 3, now }), /approval_expired/);
});
