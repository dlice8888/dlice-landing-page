/**
 * CRM and loyalty domain rules.
 *
 * Pure domain layer: callers must persist commands transactionally on the server.
 * Never treat these helpers as authentication, tenant authorization, or a database.
 */

const fail = (code, details = {}) => ({ ok: false, code, ...details });
const ok = (value) => ({ ok: true, ...value });
const nonBlank = (value) => typeof value === "string" && value.trim().length > 0;
const isInteger = (value) => Number.isSafeInteger(value);
const validDate = (value) => typeof value === "string" && !Number.isNaN(Date.parse(value));

export function normalizeCustomerIdentity({ phone, email } = {}) {
  const normalizedPhone = nonBlank(phone) ? phone.replace(/[^0-9]/g, "").replace(/^0/, "62").replace(/^8/, "628") : null;
  const normalizedEmail = nonBlank(email) ? email.trim().toLowerCase() : null;
  if (!normalizedPhone && !normalizedEmail) return fail("CUSTOMER_CONTACT_REQUIRED");
  if (normalizedPhone && (normalizedPhone.length < 9 || normalizedPhone.length > 15)) return fail("INVALID_PHONE");
  if (normalizedEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) return fail("INVALID_EMAIL");
  return ok({ identity: { phone: normalizedPhone, email: normalizedEmail } });
}

export function validateCustomerCreate(input = {}) {
  if (!nonBlank(input.tenant_id)) return fail("TENANT_REQUIRED");
  const identity = normalizeCustomerIdentity(input);
  if (!identity.ok) return identity;
  if (input.branch_id !== null && input.branch_id !== undefined && !nonBlank(input.branch_id)) return fail("INVALID_BRANCH_SCOPE");
  return ok({
    customer: {
      tenant_id: input.tenant_id,
      branch_id: input.branch_id ?? null,
      display_name: nonBlank(input.display_name) ? input.display_name.trim().slice(0, 120) : null,
      identity: identity.identity,
      status: "prospect",
      marketing_status: "unknown",
    },
  });
}

export function recordConsent({ tenant_id, customer_tenant_id, customer_id, purpose, channel, decision, policy_version, occurred_at } = {}) {
  if (!nonBlank(tenant_id) || tenant_id !== customer_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (!nonBlank(customer_id) || !["marketing_email", "marketing_sms", "marketing_whatsapp", "personalization"].includes(purpose)) return fail("INVALID_CONSENT_SCOPE");
  if (!["granted", "withdrawn"].includes(decision) || !nonBlank(channel) || !nonBlank(policy_version) || !validDate(occurred_at)) return fail("INVALID_CONSENT_RECORD");
  return ok({ consent_event: Object.freeze({
    tenant_id, customer_id, purpose, channel, decision, policy_version,
    occurred_at: new Date(occurred_at).toISOString(),
  }) });
}

export function hasCurrentMarketingConsent(consentEvents = [], customerId, tenantId, channel, at = new Date().toISOString()) {
  if (!validDate(at)) return false;
  const eligible = consentEvents
    .filter((event) => event.customer_id === customerId && event.tenant_id === tenantId &&
      event.purpose === channel && validDate(event.occurred_at) && Date.parse(event.occurred_at) <= Date.parse(at))
    .sort((a, b) => Date.parse(b.occurred_at) - Date.parse(a.occurred_at));
  return eligible[0]?.decision === "granted";
}

export function appendLoyaltyEntry({ tenant_id, customer_tenant_id, customer_id, entry_id, kind, points, idempotency_key, source_reference, reverses_entry_id, existingEntries = [] } = {}) {
  if (!nonBlank(tenant_id) || tenant_id !== customer_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (![customer_id, entry_id, idempotency_key, source_reference].every(nonBlank)) return fail("LEDGER_REFERENCE_REQUIRED");
  if (!["earn", "redeem", "adjustment", "reversal"].includes(kind)) return fail("INVALID_LEDGER_KIND");
  if (!isInteger(points) || points === 0) return fail("INVALID_POINTS");
  if (existingEntries.some((entry) => entry.tenant_id === tenant_id && entry.idempotency_key === idempotency_key)) return fail("DUPLICATE_IDEMPOTENCY_KEY");
  if (existingEntries.some((entry) => entry.tenant_id === tenant_id && entry.entry_id === entry_id)) return fail("DUPLICATE_LEDGER_ENTRY");
  if (kind === "earn" && points < 0) return fail("EARN_POINTS_MUST_BE_POSITIVE");
  if (kind === "redeem" && points >= 0) return fail("REDEEM_POINTS_MUST_BE_NEGATIVE");
  if (kind === "reversal") {
    const original = existingEntries.find((entry) => entry.tenant_id === tenant_id && entry.entry_id === reverses_entry_id && entry.customer_id === customer_id);
    if (!original || original.kind === "reversal") return fail("REVERSAL_TARGET_NOT_FOUND");
    if (existingEntries.some((entry) => entry.kind === "reversal" && entry.reverses_entry_id === reverses_entry_id)) return fail("ENTRY_ALREADY_REVERSED");
    if (points !== -original.points) return fail("REVERSAL_AMOUNT_MISMATCH");
  } else if (reverses_entry_id) return fail("UNEXPECTED_REVERSAL_REFERENCE");
  const balance = existingEntries.filter((entry) => entry.tenant_id === tenant_id && entry.customer_id === customer_id)
    .reduce((sum, entry) => sum + entry.points, 0);
  if (kind === "redeem" && balance + points < 0) return fail("INSUFFICIENT_POINTS", { balance, requested: -points });
  return ok({ entry: Object.freeze({
    tenant_id, customer_id, entry_id, kind, points, idempotency_key,
    source_reference, reverses_entry_id: reverses_entry_id ?? null,
  }), balance_after: balance + points });
}

export function validateRewardRedemption({ tenant_id, customer_tenant_id, customer_id, reward_id, voucher_id, idempotency_key, points_cost, balance, starts_at, expires_at, now, existingRedemptions = [] } = {}) {
  if (!nonBlank(tenant_id) || tenant_id !== customer_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (![customer_id, reward_id, voucher_id, idempotency_key].every(nonBlank)) return fail("REDEMPTION_REFERENCE_REQUIRED");
  if (!isInteger(points_cost) || points_cost <= 0 || !isInteger(balance) || balance < 0) return fail("INVALID_REDEMPTION_AMOUNT");
  if (existingRedemptions.some((item) => item.tenant_id === tenant_id && (item.idempotency_key === idempotency_key || item.voucher_id === voucher_id))) return fail("DUPLICATE_REDEMPTION");
  if (balance < points_cost) return fail("INSUFFICIENT_POINTS", { balance, points_cost });
  if (!validDate(starts_at) || !validDate(expires_at) || !validDate(now) || Date.parse(expires_at) <= Date.parse(starts_at)) return fail("INVALID_REWARD_WINDOW");
  if (Date.parse(now) < Date.parse(starts_at) || Date.parse(now) >= Date.parse(expires_at)) return fail("REWARD_NOT_ACTIVE");
  return ok({ redemption: Object.freeze({
    tenant_id, customer_id, reward_id, voucher_id, idempotency_key,
    points_cost, status: "reserved",
  }) });
}

export function evaluateCampaignAudience({ tenant_id, customer, consentEvents = [], requiredConsent = "marketing_whatsapp", branch_id, starts_at, ends_at, now } = {}) {
  if (!nonBlank(tenant_id) || customer?.tenant_id !== tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (!customer || customer.status !== "active" || customer.marketing_status === "suppressed") return ok({ eligible: false, reason: "CUSTOMER_NOT_MARKETABLE" });
  if (branch_id && customer.branch_id && customer.branch_id !== branch_id) return ok({ eligible: false, reason: "BRANCH_SCOPE_MISMATCH" });
  if (!validDate(starts_at) || !validDate(ends_at) || !validDate(now) || Date.parse(ends_at) <= Date.parse(starts_at)) return fail("INVALID_CAMPAIGN_WINDOW");
  if (Date.parse(now) < Date.parse(starts_at) || Date.parse(now) >= Date.parse(ends_at)) return ok({ eligible: false, reason: "CAMPAIGN_NOT_ACTIVE" });
  const consented = hasCurrentMarketingConsent(consentEvents, customer.id, tenant_id, requiredConsent, now);
  return ok({ eligible: consented, reason: consented ? "ELIGIBLE" : "CONSENT_REQUIRED" });
}
