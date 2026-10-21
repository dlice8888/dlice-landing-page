# Staging security and timezone follow-up — 2026-10-21

## Scope and safety

This is a staging-only follow-up on top of `feat/staging-ux-cx-final-reconcile-20261021`. It does not deploy the Edge Function, apply the migration to Supabase, merge a PR, or change production.

## Changes prepared for review

- Replaces permissive Vercel preview hostname matching with exact-origin allowlisting. Stable origins remain explicit; temporary preview origins must be listed in the Supabase Edge Function secret `DLICE_ALLOWED_ORIGINS` as a comma-separated list of complete HTTPS origins. Do not use wildcard suffixes.
- Rejects disallowed origins on `OPTIONS` preflight as well as normal requests.
- Formats transaction codes using the stored order timezone, with a safe `Asia/Jakarta` fallback. Customer-facing date/time copy now says “waktu lokal cabang” instead of assuming WITA.
- Adds migration `20261021220000_branch_timezone_checkout_cutoff.sql`: defaults new orders to `Asia/Jakarta`, then uses the selected branch's validated timezone for the same-day cutoff and stores that timezone on the new order. Existing historical orders are intentionally not rewritten.

## Staging evidence collected

- 40 public tables have RLS enabled.
- 27 tables have no RLS policies. This is not automatically a vulnerability: direct table privileges were inspected separately.
- The only direct table privilege found for `anon` and `authenticated` is `SELECT` on `public.products`; no direct INSERT/UPDATE/DELETE grants were found for these roles on public tables. ERP/order tables are service-role-only at the table-grant layer.
- Security Advisor still reports leaked-password protection disabled. Enable it in Supabase Auth settings and verify login/reset behavior before release.
- Performance Advisor still reports 34 unindexed foreign keys. Review each finding against existing indexes and actual query patterns; avoid blind duplicate indexes.

## Required validation before merge

1. Set `DLICE_ALLOWED_ORIGINS` in the **staging** Supabase Edge Function secrets to the exact stable staging/preview origin(s) currently used. Verify preflight succeeds for approved origins and fails for an unapproved origin. Do not set this secret on production as part of this PR.
2. Apply the migration to a disposable/local database or staging only after review; verify a WIB branch and WITA/WIT branch each use their own local date for the 18:00 cutoff and persist the correct `orders.timezone`.
3. Test transaction-code dates around 16:59/17:00 WIB and midnight boundaries, plus a WITA branch. Confirm existing order identifiers remain unchanged.
4. Review every `dlice-orders` action for explicit authorization: public catalog/checkout/tracking-token actions must be narrowly scoped; all admin/ERP actions must require a valid active profile and permission checks. `verify_jwt=false` remains deliberate only if this full custom authorization audit passes; this PR does not claim that audit is complete.
5. Re-run GitHub CI and Supabase security/performance advisors. Investigate the leaked-password warning and 34 FK-index findings; do not add blanket RLS policies to the 27 tables without a role/access model.
6. Run customer order/payment-proof and role-based ERP acceptance tests in staging. Keep all production resources unchanged until the Owner approves.

## Known limitation

The changes are committed to a review branch only. The SQL migration has not been applied and the Edge Function has not been redeployed, so the live staging runtime does not yet include these fixes.
