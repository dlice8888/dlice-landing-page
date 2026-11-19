# Branch Worker Profile Role — Technical Design

**Status:** Migration applied to Supabase staging as version `20261119155309`. Role-classification API/UI work remains separate and is not yet accepted as complete.

## Why this change exists

Staging previously constrained `admin_profiles.role` to `sales_admin` and `owner`. The applied additive migration now also permits `branch_worker` as an identity classification. It does not assign that role to any user and does not grant tenant permissions.

## Current staging facts

- `admin_profiles_role_check` now permits `sales_admin`, `branch_worker`, and `owner`.
- Current profile counts remain one `owner` and three `sales_admin`; no existing profile was modified by this migration.
- Tenant-scoped permissions continue to derive from active `tenant_memberships` and branch assignments.
- The existing Owner authorization requirements remain unchanged: active Owner profile, UUID allowlist, and boolean Auth `app_metadata.platform_owner=true`.
- Tenant A/B runtime isolation remains unverified; this migration does not satisfy or bypass P01–P09.

## Remaining implementation and acceptance

1. Implement and verify Owner-only role classification through the authenticated Edge Function.
2. Ensure a user cannot self-promote or downgrade an Owner.
3. Require active non-Owner/non-Admin membership and valid same-tenant branch assignments before assigning `branch_worker`.
4. Reject any cross-tenant branch assignment.
5. Verify worker permissions remain the intersection of active tenant membership permissions.
6. Run authenticated role/branch-scope tests before treating Branch Worker as an available operational role.

## Migration provenance

- Applied migration version: `20261119155309`
- Source file: `supabase/migrations/20261119155309_add_branch_worker_profile_role.sql`
- Change: extend `admin_profiles_role_check` to include `branch_worker`; no row updates or Auth metadata changes.
