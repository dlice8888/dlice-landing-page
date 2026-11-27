# HR & Workforce — Recruitment, Training and Performance (2026-11-27)

## Feature IDs started
- D12-F08 — Training/certification and performance reviews.
- D12-F09 — Recruitment/onboarding/offboarding.

## Implemented
`src/hr-recruitment-training-performance-workflows.mjs` adds:
- governed recruitment transitions with employee creation and approved onboarding plan in one transaction on hire;
- employee offboarding gated by independent approval, complete session/access revocation and reconciled company-asset return;
- training/certification completion from approved courses with expiry and independent evidence verification;
- performance review publication only from approved, reconciled metrics and independent reviewer.

Contract tests cover invalid lifecycle transitions, onboarding creation, session revocation, training certification expiry/evidence and performance source reconciliation.

## Remaining acceptance
- Canonical employee, candidate, onboarding task, training course/certification and performance review schema with RLS and immutable event/audit.
- Concrete Supabase repository adapters and authenticated Edge Function routes.
- Recruitment UI, interview/offer approval, onboarding checklist completion and background check policy.
- Link offboarding to payroll final settlement, asset register, tenant membership removal, session/token revocation and access review.
- Training catalog, renewal reminders, certificate evidence private Storage lifecycle and role-based training matrix.
- Performance scorecard formula/version, calibrated reviewer/appeal workflow and Finance/BI labor metrics.
- Staging tenant/branch E2E including independent approvals and no remaining sessions.
