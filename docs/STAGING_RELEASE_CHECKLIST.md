# D’lice staging-to-production release gate

This checklist is mandatory for PRs that touch orders, payments, authentication, database policies, Edge Functions, secrets, or environment routing.

## Non-negotiable environment boundaries

| Surface | Staging | Production |
| --- | --- | --- |
| Supabase | `higoadrzxnhzbbwhdbmh` | `gdjlkrmlsurcdbwnmqgg` |
| Website | Vercel Preview URL only | `https://dlice.vercel.app/` |
| Database migrations | Apply and verify here first | Only after Owner approval and successful staging acceptance |
| Auth security settings | Test-account validation first | Repeat only during approved release |
| Secrets | Staging-only values | Production-only values; never copied to Preview/Development |

The Edge Function must fail closed if its required URL/key variables are missing. Never use a production URL as a fallback. Frontend code must not contain service-role/secret keys.

## Required PR evidence

- [ ] GitHub Actions `Free quality checks` passes on the exact head commit.
- [ ] SQL migrations are reviewed in order, are additive/backwards-compatible where possible, and include a rollback or forward-fix plan.
- [ ] Staging Supabase migrations and Edge Function version match the branch under test.
- [ ] RLS is enabled for exposed tables; sensitive data access is mediated by Edge Functions and service-role grants only where intended.
- [ ] No broad RLS policy is added merely to silence an advisor. Confirm table grants and row policies together.
- [ ] Advisor findings are triaged with reasons; do not delete indexes only because `idx_scan=0` on a small/young database.
- [ ] Checkout/payment/fulfillment E2E checklist is completed on staging with test data.
- [ ] Mobile landing, product image loading, checkout summary, upload errors, and tracking are checked at narrow viewport widths.
- [ ] Request/response logs do not include passwords, tokens, full payment proof, full WhatsApp numbers, or other unnecessary customer data.
- [ ] Tenant-isolation runtime workflow uses only the six canonical staging secrets, verifies the expected A/B user and branch fixtures, and records all nine required probes with identity, tenant/branch scope, operation, expected/actual result, HTTP status, sanitized evidence, duration, and `PASS`/`FAIL`/`BLOCKED` status. No required probe may be skipped or blocked.
- [ ] No new paid service, billing-enabled API, or paid Vercel feature was introduced.

## Staging acceptance sequence

1. Enable Supabase Auth leaked-password protection manually in staging (Authentication → Security/Password Security); use test credentials only.
2. Run the authenticated tenant-isolation workflow from the trusted `staging` branch or a manual dispatch. Tenant A and Tenant B must log in with their own canonical credentials; verify expected Auth IDs, active memberships, and branch assignments before tenant-scoped probes. The gate must fail closed on missing/empty configuration or fixture mismatch, print no credentials or JWTs, and keep `TENANT_ISOLATION_RELEASED=false` until all required probes pass.
3. Test Owner login, invalid login, account/IP rate limiting, staff permission boundaries, logout and expired session behavior.
4. Test valid/invalid order tracking by transaction code + full WhatsApp number and by private token. Invalid lookups must not reveal order data.
5. Create a multi-item order. Check server-calculated prices, receipt version, transaction code format, date/time (WITA), pickup/delivery, and address validation.
6. Test capacity conflict and simultaneous checkout; one capacity slot must not be oversold.
7. Test receipt confirmation, bank/QRIS instructions, proof upload/re-upload, proof version matching, payment verification, and notification idempotency.
8. Test each allowed operational status transition. Unpaid orders cannot enter fulfillment; cancellation/delivery issue needs a reason; required notification must be marked sent before fulfillment transitions.
9. Confirm customer tracking reflects payment and operational statuses separately.
10. Confirm privacy-safe daily funnel counts change and no customer identifiers appear in analytics rows.
11. Re-run Supabase security/performance advisors and review Vercel preview response headers.

## Promotion procedure

1. Keep the PR in draft until all mandatory tests pass; attach results and the exact tested commit SHA.
2. Owner reviews the diff, migrations, environment matrix, security findings, and rollback plan.
3. Owner explicitly approves production release. Do not merge or deploy to production automatically based on a preview's READY status.
4. Apply production migrations in version order only after confirming they are backward compatible and backed by a tested recovery plan.
5. Deploy the reviewed code, verify production health and order flow, and retain the previous working deployment for rollback.
6. If any critical order/payment/tracking test fails, stop rollout and revert code or apply a reviewed forward-fix. Never try untested schema rollback against live orders.

## GitHub Actions staging tenant-isolation fixtures

The trusted `staging` Environment must contain these six secrets (values are never printed by the workflow):

- `STAGING_SUPABASE_URL`
- `STAGING_SUPABASE_PUBLIC_KEY`
- `STAGING_TENANT_A_USERNAME`
- `STAGING_TENANT_A_PASSWORD`
- `STAGING_TENANT_B_USERNAME`
- `STAGING_TENANT_B_PASSWORD`

Keep fixture identifiers in Environment variables, not in workflow YAML:

| Variable | Verified staging fixture |
| --- | --- |
| `STAGING_TENANT_A_ID` | `00000000-0000-4000-8000-000000000001` |
| `STAGING_TENANT_B_ID` | `00000000-0000-4000-8000-000000000002` |
| `STAGING_TENANT_A_BRANCH_ID` | `90000000-0000-4000-8000-000000000001` |
| `STAGING_TENANT_B_BRANCH_ID` | `90000000-0000-4000-8000-000000000004` |
| `STAGING_TENANT_A_USER_ID` | `b930897c-f8fb-443b-9056-e70c08b31446` |
| `STAGING_TENANT_B_USER_ID` | `e1de1ffc-9fae-412f-9dd7-0993b54cb631` |

These are non-secret fixture identifiers verified against the current staging database. The runtime workflow must fail closed when any variable is missing or mismatched; do not restore hard-coded fallbacks or use the Owner account as Tenant A.

## Environment variable policy

- `SUPABASE_URL`: environment-specific Supabase project URL; staging must point to staging and production to production.
- `SUPABASE_PUBLISHABLE_KEY` / legacy `SUPABASE_ANON_KEY`: public client key only; never a service-role key.
- `SUPABASE_SERVICE_ROLE_KEY` or `SUPABASE_SECRET_KEYS`: Edge Function secrets only, configured separately in each Supabase project.
- `DLICE_OWNER_BOOTSTRAP_SECRET`: short-lived bootstrap secret; do not print, commit, paste into issue/PR, or reuse between environments. Rotate/remove after bootstrap.
- `VERCEL_TOKEN`: never add to repository variables accessible to untrusted PRs; use only a protected environment secret if a future deployment workflow requires it.

Before changing Vercel env targets, list variable names and target scopes without decrypting values. Do not remove or replace a variable until the affected deployment's code path and environment have been verified. Keep production settings untouched during staging work.

## Monitoring and cost

Use the existing Supabase advisor/logging, Vercel deployment/build/runtime logs, and the aggregate funnel dashboard. Do not add paid telemetry, scheduled jobs, external analytics SDKs, or a billing-based Google Places API. Review quotas periodically; "free" still consumes included request, storage, database, and build quotas.

## Outstanding account-level controls

Some controls cannot be enforced by repository code alone:
- Leaked-password protection requires a Supabase Auth dashboard toggle in each environment.
- Platform Owner authorization requires a server-managed Auth `app_metadata.platform_owner=true` boolean and a matching `DLICE_PLATFORM_OWNER_USER_IDS` Edge Function allowlist entry; update through the authorized Auth Admin path, never by direct SQL against `auth.users`.
- GitHub branch protection / required status checks need repository settings or permissions not exposed by this workflow.
- Vercel preview deployment protection must be enabled/verified in project settings. Do not turn on a protection mode that blocks the Owner's testing without configuring a safe access path first.
- Five-star Google Maps review carousel is intentionally not fabricated; only show reviews from a verified, permitted source. The existing Google Maps link is the no-cost fallback.


## 2026-10-25 — POS idempotency fingerprint fix

- Staging runtime found SQLSTATE 42883 in `erp_create_pos_sale_idempotent`: `digest(text, text)` is installed under the Supabase `extensions` schema, but the RPC pins `search_path = public`.
- Migration `20261025115812_fix_pos_idempotency_digest_schema.sql` qualifies the call as `extensions.digest(...)` without relaxing transaction idempotency or authorization.
- Applied and recorded on staging project `higoadrzxnhzbbwhdbmh`; a SHA-256 smoke query passed.
- Production was not changed. Staging E2E must pass the POS/payment → KDS → recipe stock → offline replay → report reconciliation checks before acceptance.
