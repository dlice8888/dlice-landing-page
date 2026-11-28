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
  const urgency = { critical: 0, high: 1, normal: 2, low: 3 };
  return [...(items || [])]
    .filter((item) => item && item.status === "pending" && asTime(item.expires_at, "expires_at") > instant)
    .sort((a, b) =>
      (urgency[a.urgency] ?? urgency.normal) - (urgency[b.urgency] ?? urgency.normal) ||
      Number(b.amount_idr || 0) - Number(a.amount_idr || 0) ||
      asTime(a.expires_at, "expires_at") - asTime(b.expires_at, "expires_at") ||
      asTime(a.created_at, "created_at") - asTime(b.created_at, "created_at")
    );
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
  assertApprovalDelegation({ actor, approval, now });
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
  assertApprovalDelegation({ actor, approval, now });
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
    source_entity_type: approval.source_entity_type,
    source_entity_id: approval.source_entity_id,
    source_version: approval.source_version,
    policy_version: APPROVAL_POLICY_VERSION,
  });
}

/**
 * Build a branch/domain/role-scoped inbox projection from source references.
 * This projection never owns or mutates the source entity's business status.
 */
export function buildApprovalInbox({ items, actor, now = new Date().toISOString() }) {
  if (!actor?.user_id || !Array.isArray(actor.allowed_branch_ids) ||
      !Array.isArray(actor.allowed_domains) || !Array.isArray(actor.allowed_roles)) {
    throw new TypeError("approval_actor_scope_required");
  }
  const instant = asTime(now, "now");
  const seen = new Set();
  const urgency = { critical: 0, high: 1, normal: 2, low: 3 };
  return [...(items || [])].filter((item) => {
    if (!item?.id || seen.has(item.id)) return false;
    seen.add(item.id);
    if (item.status !== "pending" || !item.expires_at || asTime(item.expires_at, "expires_at") <= instant) return false;
    try { assertApprovalEligibility({ approval: item, actor, now }); }
    catch { return false; }
    return true;
  }).sort((a, b) =>
    (urgency[a.urgency] ?? urgency.normal) - (urgency[b.urgency] ?? urgency.normal) ||
    Number(b.amount_idr || 0) - Number(a.amount_idr || 0) ||
    asTime(a.expires_at, "expires_at") - asTime(b.expires_at, "expires_at")
  ).map((item) => Object.freeze({
    id: item.id, domain: item.domain, category: item.category,
    branch_id: item.branch_id, amount_idr: item.amount_idr,
    urgency: item.urgency || "normal", expires_at: item.expires_at,
    created_by: item.created_by, claimed_by: item.claimed_by || null,
    source_entity_type: item.source_entity_type,
    source_entity_id: item.source_entity_id,
    source_version: item.source_version,
    evidence: Array.isArray(item.evidence) ? item.evidence : [],
  }));
}

export function assertApprovalDelegation({ actor, approval, now = new Date().toISOString() }) {
  if (!approval?.delegated_from) return true;
  const instant = asTime(now, "now");
  const valid = (actor?.delegations || []).some((grant) =>
    grant.delegator_user_id === approval.delegated_from &&
    grant.delegate_user_id === actor.user_id &&
    grant.domain === approval.domain &&
    grant.branch_id === approval.branch_id &&
    grant.active === true &&
    (!grant.expires_at || asTime(grant.expires_at, "delegation_expires_at") > instant)
  );
  if (!valid) throw new Error("approval_delegation_invalid");
  return true;
}


/**
 * Shared server-side eligibility predicate for inbox visibility and claim.
 * The database RPC must repeat these checks under row lock; this helper is
 * not a substitute for authorization or concurrency control.
 */
export function assertApprovalEligibility({ approval, actor, now = new Date().toISOString() }) {
  if (!approval || !actor?.user_id) throw new TypeError("approval_and_actor_required");
  if (approval.status !== "pending") throw new Error("approval_not_pending");
  if (asTime(approval.expires_at, "expires_at") <= asTime(now, "now")) throw new Error("approval_expired");
  if (!actor.allowed_branch_ids?.includes(approval.branch_id)) throw new Error("approval_branch_forbidden");
  if (!actor.allowed_domains?.includes(approval.domain)) throw new Error("approval_domain_forbidden");
  if (!actor.allowed_roles?.includes(actor.role) ||
      !approval.eligible_roles?.includes(actor.role)) throw new Error("approval_role_forbidden");
  if (approval.category && Array.isArray(actor.allowed_categories) &&
      !actor.allowed_categories.includes(approval.category)) throw new Error("approval_category_forbidden");
  const amount = Number(approval.amount_idr);
  const maximum = Number(actor.max_approval_amount_idr);
  if (!Number.isSafeInteger(amount) || amount < 0) throw new Error("approval_amount_invalid");
  if (!Number.isSafeInteger(maximum) || amount > maximum) throw new Error("approval_amount_limit_exceeded");
  if (approval.created_by === actor.user_id && approval.separation_of_duties === true) {
    throw new Error("self_approval_forbidden");
  }
  assertApprovalDelegation({ actor, approval, now });
  if (approval.claimed_by && approval.claimed_by !== actor.user_id &&
      approval.claim_expires_at && asTime(approval.claim_expires_at, "claim_expires_at") > asTime(now, "now")) {
    throw new Error("approval_already_claimed");
  }
  return Object.freeze({
    approval_id: approval.id,
    source_entity_type: approval.source_entity_type,
    source_entity_id: approval.source_entity_id,
    source_version: approval.source_version,
    policy_version: APPROVAL_POLICY_VERSION,
  });
}
