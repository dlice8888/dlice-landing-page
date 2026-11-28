import test from "node:test";
import assert from "node:assert/strict";
import { listPendingApprovals, claimApproval, decideApproval } from "../../src/executive-approval-service.mjs";

const now = "2026-11-28T10:00:00.000Z";
const approval = {
  id: "ap-1", status: "pending", version: 4, branch_id: "b1", domain: "procurement",
  category: "purchase_order", amount_idr: 250000, expires_at: "2026-11-28T12:00:00.000Z",
  claim_expires_at: "2026-11-28T11:00:00.000Z", claimed_by: "u2",
  created_by: "u1", eligible_roles: ["manager"], separation_of_duties: true,
  source_entity_type: "purchase_order", source_entity_id: "po-1", source_version: 7,
  created_at: "2026-11-28T09:00:00.000Z", urgency: "high",
};
const actor = {
  user_id: "u2", role: "manager", allowed_branch_ids: ["b1"],
  allowed_domains: ["procurement"], allowed_roles: ["manager"],
  max_approval_amount_idr: 500000,
};

test("approval service builds scoped read model through repository adapter", async () => {
  const result = await listPendingApprovals({
    actor, now, repository: { async listPendingApprovals() { return [approval, approval]; } },
  });
  assert.equal(result.count, 1);
  assert.equal(result.items[0].source_entity_id, "po-1");
  assert.equal(result.policy_version, "approval-policy.v1");
});

test("claim service requires atomic repository confirmation and incremented version", async () => {
  const result = await claimApproval({
    approval: { ...approval, claimed_by: null, claim_expires_at: null }, actor, expectedVersion: 4, now,
    repository: { async claimApproval(command) {
      assert.equal(command.source_entity_id, "po-1");
      return { claimed: true, approval_id: "ap-1", version: 5, claim_expires_at: "2026-11-28T10:15:00.000Z" };
    } },
  });
  assert.equal(result.version, 5);
  await assert.rejects(() => claimApproval({
    approval: { ...approval, claimed_by: null, claim_expires_at: null }, actor, expectedVersion: 4, now,
    repository: { async claimApproval() { return { claimed: true, approval_id: "ap-1", version: 4 }; } },
  }), /approval_claim_not_confirmed/);
});

test("decision service requires idempotency and confirmed source entity version transition", async () => {
  const result = await decideApproval({
    approval, actor, decision: "approved", reason: "Quote and budget verified",
    expectedVersion: 4, idempotencyKey: "approval-decision-0001", now,
    repository: { async decideApproval(command) {
      assert.equal(command.source_entity_id, "po-1");
      assert.equal(command.source_version, 7);
      return {
        decision_id: "decision-1", approval_id: "ap-1",
        source_entity_type: "purchase_order", source_entity_id: "po-1",
        source_version_after: 8, source_status: "approved",
      };
    } },
  });
  assert.equal(result.source_version_after, 8);
  await assert.rejects(() => decideApproval({
    approval, actor, decision: "approved", reason: "Verified",
    expectedVersion: 4, idempotencyKey: "approval-decision-0002", now,
    repository: { async decideApproval() {
      return { decision_id: "decision-2", approval_id: "ap-1", source_entity_type: "purchase_order", source_entity_id: "po-1", source_version_after: 7 };
    } },
  }), /approval_source_transition_not_confirmed/);
  await assert.rejects(() => decideApproval({
    approval, actor, decision: "approved", reason: "Verified",
    expectedVersion: 4, idempotencyKey: "short", now, repository: { async decideApproval() { return {}; } },
  }), /approval_decision_idempotency_key_required/);
});

test("service fails closed when persistence adapter is missing", async () => {
  await assert.rejects(() => listPendingApprovals({ actor, now, repository: {} }), /approval_repository_adapter_missing/);
});
