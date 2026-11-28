import test from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeCustomerIdentity, validateCustomerCreate, recordConsent,
  hasCurrentMarketingConsent, appendLoyaltyEntry, validateRewardRedemption,
  evaluateCampaignAudience,
} from '../../src/crm-loyalty-domain.mjs';

test('customer identity requires tenant and a valid normalized contact', () => {
  assert.equal(validateCustomerCreate({ phone: '08123456789' }).code, 'TENANT_REQUIRED');
  assert.equal(validateCustomerCreate({ tenant_id: 't1' }).code, 'CUSTOMER_CONTACT_REQUIRED');
  assert.equal(normalizeCustomerIdentity({ phone: '0812-3456-7890' }).identity.phone, '6281234567890');
  assert.equal(normalizeCustomerIdentity({ email: 'BAD' }).code, 'INVALID_EMAIL');
  assert.equal(validateCustomerCreate({ tenant_id: 't1', branch_id: 'b1', phone: '08123456789' }).customer.status, 'prospect');
});

test('consent is tenant-bound, purpose-specific, and withdrawal overrides earlier grant', () => {
  assert.equal(recordConsent({ tenant_id: 't1', customer_tenant_id: 't2' }).code, 'TENANT_SCOPE_MISMATCH');
  const grant = recordConsent({ tenant_id: 't1', customer_tenant_id: 't1', customer_id: 'c1', purpose: 'marketing_whatsapp', channel: 'whatsapp', decision: 'granted', policy_version: 'v1', occurred_at: '2026-01-01T00:00:00Z' });
  const withdrawal = recordConsent({ tenant_id: 't1', customer_tenant_id: 't1', customer_id: 'c1', purpose: 'marketing_whatsapp', channel: 'whatsapp', decision: 'withdrawn', policy_version: 'v1', occurred_at: '2026-02-01T00:00:00Z' });
  assert.equal(hasCurrentMarketingConsent([grant.consent_event], 'c1', 't1', 'marketing_whatsapp', '2026-01-15T00:00:00Z'), true);
  assert.equal(hasCurrentMarketingConsent([grant.consent_event, withdrawal.consent_event], 'c1', 't1', 'marketing_whatsapp', '2026-02-02T00:00:00Z'), false);
});

test('loyalty ledger rejects duplicate keys, invalid signs, and overspending', () => {
  const earn = appendLoyaltyEntry({ tenant_id: 't1', customer_tenant_id: 't1', customer_id: 'c1', entry_id: 'e1', kind: 'earn', points: 100, idempotency_key: 'k1', source_reference: 'order-1' });
  assert.equal(earn.ok, true);
  assert.equal(appendLoyaltyEntry({ tenant_id: 't1', customer_tenant_id: 't1', customer_id: 'c1', entry_id: 'e2', kind: 'earn', points: 10, idempotency_key: 'k1', source_reference: 'order-2', existingEntries: [earn.entry] }).code, 'DUPLICATE_IDEMPOTENCY_KEY');
  assert.equal(appendLoyaltyEntry({ tenant_id: 't1', customer_tenant_id: 't1', customer_id: 'c1', entry_id: 'e2', kind: 'redeem', points: -101, idempotency_key: 'k2', source_reference: 'voucher-1', existingEntries: [earn.entry] }).code, 'INSUFFICIENT_POINTS');
  assert.equal(appendLoyaltyEntry({ tenant_id: 't1', customer_tenant_id: 't1', customer_id: 'c1', entry_id: 'e3', kind: 'adjustment', points: -101, idempotency_key: 'k3', source_reference: 'manual-adjustment', existingEntries: [earn.entry] }).code, 'INSUFFICIENT_POINTS');
  assert.equal(appendLoyaltyEntry({ tenant_id: 't1', customer_tenant_id: 't2', customer_id: 'c1', entry_id: 'e2', kind: 'earn', points: 10, idempotency_key: 'k2', source_reference: 'order-2' }).code, 'TENANT_SCOPE_MISMATCH');
});

test('ledger reversals must exactly offset one existing entry and cannot be repeated', () => {
  const earn = appendLoyaltyEntry({ tenant_id: 't1', customer_tenant_id: 't1', customer_id: 'c1', entry_id: 'e1', kind: 'earn', points: 50, idempotency_key: 'k1', source_reference: 'order-1' });
  const reversal = appendLoyaltyEntry({ tenant_id: 't1', customer_tenant_id: 't1', customer_id: 'c1', entry_id: 'e2', kind: 'reversal', points: -50, idempotency_key: 'k2', source_reference: 'refund-1', reverses_entry_id: 'e1', existingEntries: [earn.entry] });
  assert.equal(reversal.ok, true);
  assert.equal(appendLoyaltyEntry({ tenant_id: 't1', customer_tenant_id: 't1', customer_id: 'c1', entry_id: 'e3', kind: 'reversal', points: -50, idempotency_key: 'k3', source_reference: 'refund-2', reverses_entry_id: 'e1', existingEntries: [earn.entry, reversal.entry] }).code, 'ENTRY_ALREADY_REVERSED');
});

test('reward redemption validates points, tenant, and effective dates', () => {
  const input = { tenant_id: 't1', customer_tenant_id: 't1', customer_id: 'c1', reward_id: 'r1', voucher_id: 'v1', idempotency_key: 'redeem-1', points_cost: 40, balance: 100, starts_at: '2026-01-01T00:00:00Z', expires_at: '2027-01-01T00:00:00Z', now: '2026-06-01T00:00:00Z' };
  assert.equal(validateRewardRedemption(input).redemption.status, 'reserved');
  assert.equal(validateRewardRedemption({ ...input, balance: 10 }).code, 'INSUFFICIENT_POINTS');
  assert.equal(validateRewardRedemption({ ...input, customer_tenant_id: 't2' }).code, 'TENANT_SCOPE_MISMATCH');
  assert.equal(validateRewardRedemption({ ...input, existingRedemptions: [{ tenant_id: 't1', voucher_id: 'v1', idempotency_key: 'old' }] }).code, 'DUPLICATE_REDEMPTION');
});

test('campaign audience requires active customer and current channel consent', () => {
  const customer = { id: 'c1', tenant_id: 't1', branch_id: 'b1', status: 'active', marketing_status: 'active' };
  const consent = recordConsent({ tenant_id: 't1', customer_tenant_id: 't1', customer_id: 'c1', purpose: 'marketing_whatsapp', channel: 'whatsapp', decision: 'granted', policy_version: 'v1', occurred_at: '2026-01-01T00:00:00Z' }).consent_event;
  const campaign = { tenant_id: 't1', customer, consentEvents: [consent], requiredConsent: 'marketing_whatsapp', branch_id: 'b1', starts_at: '2026-01-01T00:00:00Z', ends_at: '2027-01-01T00:00:00Z', now: '2026-06-01T00:00:00Z' };
  assert.equal(evaluateCampaignAudience(campaign).eligible, true);
  assert.equal(evaluateCampaignAudience({ ...campaign, branch_id: 'b2' }).eligible, false);
  assert.equal(evaluateCampaignAudience({ ...campaign, consentEvents: [] }).reason, 'CONSENT_REQUIRED');
});
