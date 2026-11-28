import test from "node:test";
import assert from "node:assert/strict";
import {
  buildApprovalInbox, assertApprovalClaim, assertApprovalDecision,
  assertApprovalDelegation,
} from "../../src/executive-approval-center.mjs";

const now = "2026-11-28T10:00:00.000Z";
const base = {
  id: "a1", status: "pending", version: 4, expires_at: "2026-11-28T11:00:00.000Z",
  claim_expires_at: "2026-11-28T10:30:00.000Z", branch_id: "b1",
  domain: "procurement", eligible_roles: ["owner", "procurement_manager"],
  created_by: "requester", separation_of_duties: true, amount_idr: 250000,
  source_entity_type: "purchase_requisition", source_entity_id: "pr-1", source_version: 7,
  urgency: "high", created_at: "2026-11-28T09:00:00.000Z",
};
const actor = {
  user_id: "approver", role: "procurement_manager", allowed_branch_ids: ["b1"],
  allowed_domains: ["procurement"], max_approval_amount_idr: 500000,
};

test("approval inbox filters scope, expiry, duplicate ids and ranks urgency/value", () => {
  const rows = [
    base,
    { ...base, id: "a2", urgency: "critical", amount_idr: 100 },
    { ...base, id: "a3", branch_id: "b2" },
    { ...base, id: "a4", expires_at: now },
    { ...base, id: "a5", domain: "hr" },
    { ...base, id: "a1", amount_idr: 999999 },
  ];
  const inbox = buildApprovalInbox({
    items: rows,
    actor: { ...actor, allowed_roles: ["procurement_manager"] },
    now,
  });
  assert.deepEqual(inbox.map((item) => item.id), ["a2", "a1"]);
  assert.equal(inbox[1].source_entity_id, "pr-1");
});

test("claim is branch scoped, versioned, expiring and rejects a competing claimant", () => {
  assert.deepEqual(
    assertApprovalClaim({ approval: base, actor, expectedVersion: 4, now }),
    { approval_id: "a1", actor_user_id: "approver", expected_version: 4 },
  );
  assert.throws(() => assertApprovalClaim({ approval: base, actor, expectedVersion: 3, now }), /stale_approval_version/);
  assert.throws(() => assertApprovalClaim({ approval: base, actor: { ...actor, allowed_branch_ids: ["b2"] }, expectedVersion: 4, now }), /approval_branch_forbidden/);
  assert.throws(() => assertApprovalClaim({ approval: { ...base, expires_at: now }, actor, expectedVersion: 4, now }), /approval_expired/);
  assert.throws(() => assertApprovalClaim({ approval: { ...base, claimed_by: "other" }, actor, expectedVersion: 4, now }), /approval_already_claimed/);
});

test("decision requires active claim, reason on rejection, amount authority and separation of duties", () => {
  const claimed = { ...base, claimed_by: "approver" };
  assert.equal(assertApprovalDecision({
    approval: claimed, actor, decision: "approved", reason: "Validated supplier quote",
    expectedVersion: 4, now,
  }).source_version, 7);
  assert.throws(() => assertApprovalDecision({
    approval: claimed, actor, decision: "rejected", reason: "no",
    expectedVersion: 4, now,
  }), /rejection_reason_required/);
  assert.throws(() => assertApprovalDecision({
    approval: { ...claimed, created_by: "approver" }, actor, decision: "approved",
    reason: "Conflict", expectedVersion: 4, now,
  }), /self_approval_forbidden/);
  assert.throws(() => assertApprovalDecision({
    approval: claimed, actor: { ...actor, max_approval_amount_idr: 100 },
    decision: "approved", reason: "Over limit", expectedVersion: 4, now,
  }), /approval_amount_limit_exceeded/);
  assert.throws(() => assertApprovalDecision({
    approval: { ...claimed, claim_expires_at: now }, actor,
    decision: "approved", reason: "Expired claim", expectedVersion: 4, now,
  }), /active_claim_required/);
});

test("delegated approval requires active matching grant and expiry is enforced", () => {
  const delegated = { ...base, delegated_from: "manager" };
  const delegate = {
    ...actor,
    delegations: [{
      delegator_user_id: "manager", delegate_user_id: "approver",
      domain: "procurement", branch_id: "b1", active: true,
      expires_at: "2026-11-28T10:30:00.000Z",
    }],
  };
  assert.equal(assertApprovalDelegation({ actor: delegate, approval: delegated, now }), true);
  assert.throws(() => assertApprovalDelegation({
    actor: { ...delegate, delegations: [] }, approval: delegated, now,
  }), /approval_delegation_invalid/);
  assert.throws(() => assertApprovalDelegation({
    actor: { ...delegate, delegations: [{ ...delegate.delegations[0], expires_at: now }] },
    approval: delegated, now,
  }), /approval_delegation_invalid/);
});

test("approval decision rejects stale concurrent writers and never rewrites source status", () => {
  const claimed = { ...base, claimed_by: "approver" };
  assert.throws(() => assertApprovalDecision({
    approval: claimed, actor, decision: "approved", reason: "Approved",
    expectedVersion: 3, now,
  }), /stale_approval_version/);
  const command = assertApprovalDecision({
    approval: claimed, actor, decision: "approved", reason: "Approved",
    expectedVersion: 4, now,
  });
  assert.equal(command.approval_id, "a1");
  assert.equal(command.source_entity_id, undefined);
  assert.equal(command.source_version, undefined);
  assert.equal(base.status, "pending");
});

test("delegated claimant must hold an active matching grant before claim", () => {
  const delegated = { ...base, delegated_from: "manager" };
  assert.throws(() => assertApprovalClaim({
    approval: delegated, actor, expectedVersion: 4, now,
  }), /approval_delegation_invalid/);
  const delegatedActor = {
    ...actor,
    delegations: [{
      delegator_user_id: "manager", delegate_user_id: "approver",
      domain: "procurement", branch_id: "b1", active: true,
      expires_at: "2026-11-28T10:30:00.000Z",
    }],
  };
  assert.equal(assertApprovalClaim({
    approval: delegated, actor: delegatedActor, expectedVersion: 4, now,
  }).approval_id, "a1");
});

test("decision command preserves source identity and optimistic source version", () => {
  const claimed = { ...base, claimed_by: "approver" };
  const command = assertApprovalDecision({
    approval: claimed, actor, decision: "approved",
    reason: "Evidence checked", expectedVersion: 4, now,
  });
  assert.equal(command.source_entity_type, "purchase_requisition");
  assert.equal(command.source_entity_id, "pr-1");
  assert.equal(command.source_version, 7);
  assert.equal(command.policy_version, "approval-policy.v1");
});

test("approval eligibility applies amount/category policy and excludes another active claimant", () => {
  const item = { ...base, category: "purchase_order", claimed_by: "approver" };
  const scopedActor = {
    ...actor, allowed_roles: ["procurement_manager"], allowed_categories: ["purchase_order"],
  };
  assert.equal(assertApprovalEligibility({ approval: item, actor: scopedActor, now }).source_version, 7);
  assert.throws(() => assertApprovalEligibility({
    approval: item, actor: { ...scopedActor, max_approval_amount_idr: 10 }, now,
  }), /approval_amount_limit_exceeded/);
  assert.throws(() => assertApprovalEligibility({
    approval: item, actor: { ...scopedActor, allowed_categories: ["expense"] }, now,
  }), /approval_category_forbidden/);
  assert.throws(() => assertApprovalEligibility({
    approval: { ...item, claimed_by: "another", claim_expires_at: "2026-11-28T10:45:00.000Z" },
    actor: scopedActor, now,
  }), /approval_already_claimed/);
});

test("approval urgency rank is deterministic across urgency, amount and expiry", () => {
  const rows = [
    { ...base, id: "low", urgency: "low", amount_idr: 900000 },
    { ...base, id: "critical", urgency: "critical", amount_idr: 100 },
    { ...base, id: "high", urgency: "high", amount_idr: 500000 },
  ];
  assert.deepEqual(rankPendingApprovals(rows, now).map((item) => item.id), ["critical", "high", "low"]);
});
