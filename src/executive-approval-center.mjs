/**
 * Executive approval inbox policy and deterministic prioritization.
 * Persistence/claims/decisions must be executed atomically by trusted RPCs;
 * this module is the shared validation contract, not a client authorization layer.
 */
export const APPROVAL_POLICY_VERSION = "approval-policy.v1";

const asTime = (value, field) => {
  const time = Date.parse(value);
  if (!Number.isFinite(time)) throw new TypeError(`${field} must be an ISO timestamp`);
  return time;
};

export function rankPendingApprovals(items, now = new Date().toISOString()) {
  const instant = asTime(now, "now");
  return [...(items || [])]
    .filter((item) => item && item.status === "pending" && asTime(item.expires_at, "expires_at") > instant)
    .sort((a, b) => {
      const urgencyA = asTime(a.expires_at, "expires_at") - instant;
      const urgencyB = asTime(b.expires_at, "expires_at") - instant;
      if (urgencyA !== urgencyB) return urgencyA - urgencyB;
      const amountA = Number(a.amount_idr || 0);
      const amountB = Number(b.amount_idr || 0);
      if (amountA !== amountB) return amountB - amountA;
      return asTime(a.created_at, "created_at") - asTime(b.created_at, "created_at");
    });
}

export function assertApprovalClaim({ approval, actor, expectedVersion, now = new Date().toISOString() }) {
  if (!approval || !actor) throw new TypeError("approval and actor are required");
  if (approval.status !== "pending") throw new Error("approval_not_pending");
  if (approval.version !== expectedVersion) throw new Error("stale_approval_version");
  if (asTime(approval.expires_at, "expires_at") <= asTime(now, "now")) throw new Error("approval_expired");
  if (!actor.user_id || !Array.isArray(actor.allowed_branch_ids) ||
      !actor.allowed_branch_ids.includes(approval.branch_id)) {
    throw new Error("approval_branch_forbidden");
  }
  if (!Array.isArray(actor.allowed_domains) || !actor.allowed_domains.includes(approval.domain)) {
    throw new Error("approval_domain_forbidden");
  }
  if (!Array.isArray(approval.eligible_roles) || !approval.eligible_roles.includes(actor.role)) {
    throw new Error("approval_role_forbidden");
  }
  if (approval.created_by === actor.user_id && approval.separation_of_duties === true) {
    throw new Error("self_approval_forbidden");
  }
  if (approval.claimed_by && approval.claimed_by !== actor.user_id &&
      asTime(approval.claim_expires_at, "claim_expires_at") > asTime(now, "now")) {
    throw new Error("approval_already_claimed");
  }
  return Object.freeze({ approval_id: approval.id, actor_user_id: actor.user_id, expected_version: expectedVersion });
}

export function assertApprovalDecision({
  approval, actor, decision, reason, expectedVersion, now = new Date().toISOString(),
}) {
  if (!approval || !actor) throw new TypeError("approval and actor are required");
  if (!["approved", "rejected"].includes(decision)) throw new RangeError("decision must be approved or rejected");
  if (approval.status !== "pending") throw new Error("approval_not_pending");
  if (approval.version !== expectedVersion) throw new Error("stale_approval_version");
  if (asTime(approval.expires_at, "expires_at") <= asTime(now, "now")) throw new Error("approval_expired");
  if (approval.claimed_by !== actor.user_id ||
      asTime(approval.claim_expires_at, "claim_expires_at") <= asTime(now, "now")) {
    throw new Error("active_claim_required");
  }
  if (!actor.allowed_branch_ids?.includes(approval.branch_id)) throw new Error("approval_branch_forbidden");
  if (!actor.allowed_domains?.includes(approval.domain)) throw new Error("approval_domain_forbidden");
  if (!approval.eligible_roles?.includes(actor.role)) throw new Error("approval_role_forbidden");
  if (approval.created_by === actor.user_id && approval.separation_of_duties === true) {
    throw new Error("self_approval_forbidden");
  }
  const amount = Number(approval.amount_idr);
  if (!Number.isSafeInteger(amount) || amount < 0) throw new Error("approval_amount_invalid");
  const maxAmount = Number(actor.max_approval_amount_idr);
  if (!Number.isSafeInteger(maxAmount) || amount > maxAmount) throw new Error("approval_amount_limit_exceeded");
  if (decision === "rejected" && (typeof reason !== "string" || reason.trim().length < 8)) {
    throw new Error("rejection_reason_required");
  }
  return Object.freeze({
    approval_id: approval.id,
    actor_user_id: actor.user_id,
    decision,
    reason: typeof reason === "string" ? reason.trim().slice(0, 1000) : null,
    expected_version: expectedVersion,
    policy_version: APPROVAL_POLICY_VERSION,
  });
}
