import {
  APPROVAL_POLICY_VERSION,
  assertApprovalClaim,
  assertApprovalDecision,
  buildApprovalInbox,
} from "./executive-approval-center.mjs";

const requireAdapter = (repository, method) => {
  if (typeof repository?.[method] !== "function") throw new Error("approval_repository_adapter_missing:" + method);
  return repository[method].bind(repository);
};

/**
 * Application service for a persisted approval read model.
 * The repository must implement these methods with authenticated server context,
 * row locks/optimistic versions, idempotency and source-entity transaction updates.
 */
export async function listPendingApprovals({ repository, actor, filters = {}, now = new Date().toISOString() }) {
  const list = requireAdapter(repository, "listPendingApprovals");
  const rows = await list({ actorUserId: actor?.user_id, filters, policyVersion: APPROVAL_POLICY_VERSION });
  const items = buildApprovalInbox({ items: rows, actor, now });
  return Object.freeze({ policy_version: APPROVAL_POLICY_VERSION, count: items.length, items });
}

export async function claimApproval({ repository, approval, actor, expectedVersion, now = new Date().toISOString() }) {
  const claim = requireAdapter(repository, "claimApproval");
  const policy = assertApprovalClaim({ approval, actor, expectedVersion, now });
  const result = await claim({
    ...policy,
    source_entity_type: approval.source_entity_type,
    source_entity_id: approval.source_entity_id,
    source_version: approval.source_version,
    policy_version: APPROVAL_POLICY_VERSION,
  });
  if (!result?.claimed || result.approval_id !== approval.id ||
      !Number.isSafeInteger(result.version) || result.version <= expectedVersion ||
      !result.claim_expires_at) throw new Error("approval_claim_not_confirmed");
  return Object.freeze(result);
}

export async function decideApproval({
  repository, approval, actor, decision, reason, expectedVersion, idempotencyKey,
  now = new Date().toISOString(),
}) {
  const decide = requireAdapter(repository, "decideApproval");
  if (typeof idempotencyKey !== "string" || idempotencyKey.trim().length < 16) {
    throw new Error("approval_decision_idempotency_key_required");
  }
  const command = assertApprovalDecision({ approval, actor, decision, reason, expectedVersion, now });
  const result = await decide({ ...command, idempotency_key: idempotencyKey.trim() });
  if (!result?.decision_id || result.approval_id !== approval.id ||
      result.source_entity_type !== approval.source_entity_type ||
      result.source_entity_id !== approval.source_entity_id ||
      !Number.isSafeInteger(result.source_version_after) ||
      result.source_version_after <= Number(approval.source_version)) {
    throw new Error("approval_source_transition_not_confirmed");
  }
  return Object.freeze(result);
}
