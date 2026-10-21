# D’lice staging — admin/ERP authorization audit (2026-10-21)

## Scope and safety boundary

- Target: Supabase staging project `higoadrzxnhzbbwhdbmh`, GitHub PR #24 branch `fix/staging-security-timezone-20261021`, and Vercel Preview only.
- Production was not modified.
- PR #24 remains a draft. Do not merge until negative tests, checkout/timezone/CORS acceptance, desktop/mobile review, and owner approval are complete.

## Authorization changes in the current branch

- Staff profile permissions are now authoritative when explicitly present; job-position defaults are only a fallback for profiles without a permission array. This avoids silently re-adding permissions that the Owner removed from a staff profile.
- Non-owner order listing is scoped to active branch assignments.
- Proof URL retrieval, operational status changes, payment verification, payment notification retry, and notification-sent updates now check the order’s branch assignment.
- Refund processing now checks branch scope, except for Owner/Finance Head Office access.
- ERP overview totals across all branches are Owner-only.
- Job-position listing now requires HR, Staff, or Branch permission.
- Branch-capacity listing without an explicit branch is restricted to the caller’s active branch assignments.
- Writes to global master data (product-wide capacity, inventory item master, recipes, and recipe activation) require Owner or the relevant Head Office permission.
- The `production` permission is now assignable from the Owner’s staff-permission panel.

These are code changes, not proof that all negative cases have passed. The latest source still requires the end-to-end matrix below.

## Database controls verified in staging

- 27 internal ERP tables have RLS enabled and an explicit restrictive deny policy for `anon` and `authenticated`.
- Direct SELECT grants on those 27 tables: **0**; SQL privilege check confirmed all 27 lack direct client SELECT access.
- Migration `20261021150339_deny_direct_client_access_on_internal_tables` is recorded.
- Branch-timezone checkout migration `20261021151246_branch_timezone_checkout_cutoff` is recorded and the live `create_order_with_reservations(jsonb,jsonb,text)` function uses the selected branch timezone for same-day date/cutoff checks and saves it on new orders.
- Migration `20261021151524_index_remaining_erp_foreign_keys` adds indexes for the exact 34 FK constraints that staging Performance Advisor reported without a leading covering index. Advisor output now reports unused indexes rather than missing FK indexes; staging has little representative workload, so do not drop indexes solely because they have not yet been exercised.

## Required negative-access acceptance matrix

| Caller / case | Expected result |
|---|---|
| No bearer token calls any admin/ERP action | HTTP 401; no data changes |
| Inactive admin profile or invalid/expired token | HTTP 401; no data changes |
| Staff missing the action permission | HTTP 403; no data changes |
| Staff assigned to branch A requests branch B order/proof/refund/shift/inventory/capacity | HTTP 403 or empty branch-scoped result; no data changes |
| Staff has permission but no active branch assignment | No branch data and all writes denied |
| Branch staff tries to change global master inventory, global product capacity, or global recipe | HTTP 403 unless Owner/Head Office permission is present |
| Branch staff attempts Owner-only branch/staff/assignment/payment-settings/fiscal-period actions | HTTP 403 |
| Refund requester tries to approve own refund; requester/reviewer tries to process it | HTTP 403 |
| Anonymous direct SELECT/INSERT/UPDATE/DELETE on internal ERP tables | Permission denied / no rows changed |
| Owner accesses authorized global action | Allowed, subject to input validation and business-state guards |

Use separate test identities for Owner, permitted branch staff, staff without the relevant permission, staff assigned to a different branch, inactive staff, and unauthenticated callers. Record response status and before/after row counts for every write attempt. Do not use production credentials or production data.

## Checkout and timezone acceptance

Run with active online-order test branches configured for `Asia/Jakarta`, `Asia/Makassar`, and `Asia/Jayapura`:

1. Same-day checkout before cutoff (17:59 local) succeeds when all other conditions and capacity allow.
2. Same-day checkout at/after cutoff (18:00 local) fails with `same_day_cutoff_passed`.
3. A requested date before the branch-local date fails with `date_in_past`.
4. New orders store the selected branch timezone; transaction codes use that timezone.
5. Pickup/delivery enablement, address validation, global and branch capacity, reservation expiry, and multi-item checkout remain enforced.
6. Allowed preview origin receives matching CORS headers; unlisted HTTPS origin receives HTTP 403 on OPTIONS and POST; no wildcard Vercel preview hostname is accepted.

Do not test by creating live customer orders without clearly identified staging fixtures and cleanup.

## Remaining blockers before merge

- `DLICE_ALLOWED_ORIGINS` must be set in **staging Supabase Edge Function secrets only** before deploying the new function. For this Preview build, use the exact origins `https://dlice-landing-page-f8xsnrxxx-dlice8888-7332.vercel.app` and `https://dlice-landing-page-git-fix-staging-securi-5147fa-dlice8888-7332.vercel.app` (comma-separated, no trailing slashes) as the `DLICE_ALLOWED_ORIGINS` value in staging Supabase Edge Function Secrets. Do not put this secret in GitHub or Vercel environment variables.
- Redeploy `dlice-orders` to staging after the secret is saved, then test CORS and the matrix above. The active runtime has not yet been replaced by the audited branch code.
- Supabase Security Advisor still reports `auth_leaked_password_protection`. The feature is plan-dependent (Supabase documents availability on Pro and above); do not upgrade or add paid services under the no-cost constraint. Confirm whether it is available on the current staging plan.
- Test the current Preview on desktop and mobile after the backend CORS configuration is ready. The Vercel deployment being READY only confirms the build/deployment, not browser acceptance.
- Re-run CI and Security/Performance Advisor on the final PR head, attach test evidence, request review, and obtain explicit Owner approval before merge.
