# Branch Worker Profile Role — Technical Design

**Status:** Draft implementation on `fix/tenant-worker-profile-role-20261118`  
**Target:** staging only; migration is not applied.

## Why this change exists

Staging currently constrains `admin_profiles.role` to only `sales_admin` and `owner`. The two active non-owner tenant members both have global profile role `sales_admin`, even though their tenant membership role is `branch_manager`. That does not satisfy the acceptance requirement for two ordinary workers who are not Owner/Admin.

## Design

- Add `branch_worker` as an identity classification only. It does not grant permissions.
- Continue to derive all operational permissions from active `tenant_memberships` using `resolveTenantScopedPermissions`.
- Keep the Owner bypass unchanged: profile role `owner`, UUID in `DLICE_PLATFORM_OWNER_USER_IDS`, and Auth `app_metadata.platform_owner === true` must all hold.
- Add an Owner-only `admin-set-profile-role` action. It cannot change an Owner profile. Converting a user to `branch_worker` requires at least one active non-Owner/non-Admin tenant membership and at least one active branch assignment whose branch tenant is in the user's active memberships. Any cross-tenant assignment blocks the change.
- Add a visible Owner UI control to classify a profile as `Sales Admin` or `Branch Worker`. The UI calls the same Owner-only endpoint; it does not write Auth metadata or database records directly.
- Add a migration to extend the profile-role check constraint. This file is source-only until disposable replay, review, backup/rollback planning and explicit staging authorization are complete.

## Current staging facts

- The check constraint is `admin_profiles_role_check` and currently permits only `sales_admin` and `owner`.
- Two active tenant memberships have `branch_manager` role and equal permission arrays, but both linked profiles are `sales_admin`.
- One worker currently has two active same-tenant branch assignments; the other has one. There are no cross-tenant active assignment rows.
- No user/profile data was changed as part of this PR.

## Acceptance

1. A platform Owner can classify a properly assigned non-admin member as `branch_worker`.
2. A worker cannot call the role-change action.
3. An Owner profile cannot be downgraded by this action.
4. A user with no active tenant membership or no active same-tenant branch assignment cannot be classified as a worker.
5. A cross-tenant assignment blocks classification.
6. Branch-worker permissions remain the intersection of active tenant membership permissions; profile permissions never grant tenant access.
7. Migration replay succeeds on a disposable database and is reviewed before any staging application.

## References

- `supabase/functions/dlice-orders/index.ts:92-112` — identity, Owner bypass and tenant permission resolution.
- `supabase/functions/dlice-orders/index.ts:608-675` — Owner-only staff management actions.
- `supabase/functions/dlice-orders/index.ts:804-812` — exact branch access check.
- `supabase/migrations/20261118190000_add_branch_worker_profile_role.sql` — source migration.
- `erp.html:84` — Owner staff list UI.
