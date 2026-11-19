# Branch Worker Profile Role — Technical Design

**Status:** Migration applied to Supabase staging as version `20261119155309`. Owner-only role classification handler and UI are present in the staging source; authenticated runtime acceptance remains pending.

## Why this change exists

The profile role is an identity classification, while tenant permissions must remain derived from active tenant memberships and branch assignments. The additive migration allows `branch_worker` alongside `sales_admin` and `owner`; it does not assign that role or grant any permissions.

## Current staging facts

- `admin_profiles_role_check` permits `sales_admin`, `branch_worker`, and `owner`.
- Current profile counts remain one `owner` and three `sales_admin`; no profile rows or Auth metadata were changed by this migration.
- The Edge Function contains the Owner-only `admin-set-profile-role` action, and `erp.html` contains the corresponding staff-role UI.
- Tenant-scoped permissions continue to derive from active `tenant_memberships` and branch assignments; global profile permissions do not grant tenant access.
- Existing Owner authorization requirements remain unchanged: active Owner profile, UUID allowlist, and boolean Auth `app_metadata.platform_owner=true`.
- Tenant A/B runtime isolation remains unverified; this migration does not satisfy or bypass P01–P09.

## Remaining acceptance

1. Verify an authorized Platform Owner can classify a properly assigned non-admin member as `branch_worker`.
2. Verify a worker cannot call the role-change action and an Owner profile cannot be downgraded.
3. Verify users without active tenant membership or valid same-tenant branch assignment are rejected.
4. Verify any cross-tenant assignment blocks classification.
5. Verify worker permissions remain the intersection of active tenant membership permissions.
6. Run authenticated role/branch-scope tests before treating Branch Worker as an accepted operational role.

## Migration provenance

- Applied migration version: `20261119155309`
- Source file: `supabase/migrations/20261119155309_add_branch_worker_profile_role.sql`
- Change: extend `admin_profiles_role_check` to include `branch_worker`; no row updates or Auth metadata changes.
