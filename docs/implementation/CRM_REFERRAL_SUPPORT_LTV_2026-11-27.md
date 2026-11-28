# CRM, Loyalty & Marketing — Referral, Support and LTV (2026-11-27)

## Feature IDs started
- D10-F06 — Referral program.
- D10-F08 — Feedback/reviews/support cases.
- D10-F09 — Repeat purchase and customer lifetime analysis.

## Implemented
`src/crm-referral-support-ltv-workflows.mjs` adds:
- referral qualification only from the referred customer's first paid, reconciled, non-refunded/non-chargeback net sale; same-tenant identity and self-referral rejection;
- transactional, idempotent referral reward persistence from authoritative identity and sale adapters;
- support-case creation gated by valid support-contact consent and approved severity-specific SLA;
- customer lifetime metrics from deduplicated reconciled paid net sales, excluding refunded/voided/chargeback transactions;
- authorized snapshot refresh with append-only audit.

Contract tests cover self-referral, cross-tenant identity, refunded qualification, SLA consent, reconciled source requirements, duplicate sales and authoritative snapshot writes.

## Remaining acceptance
- Canonical CRM schema for referrals, support cases, SLA policy versions and LTV snapshots.
- RLS and immutable event/attribution/audit history.
- Consent preference center and customer support contact lifecycle UI.
- Customer support case assignment, response/resolve/close, SLA timers and escalation worker.
- Referral code issuance, fraud/abuse detection, reward expiry/reversal and POS refund/chargeback compensation.
- Supabase adapters and authenticated Edge Function endpoints.
- POS/Order/Refund/Settlement/Finance integration and BI cohort/retention reconciliation.
- Staging E2E with tenant A/B and duplicate/late/refund cases.

Implementation-start only; no database migration or staging data mutation.
