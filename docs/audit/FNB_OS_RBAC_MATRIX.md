# FnB OS RBAC Matrix

**Snapshot:** 18 November 2026

## Verified role grants

| Actor | Tenant membership | Permission set | Branch assignment | Current assessment |
|---|---|---|---|---|
| Worker A | Active `branch_manager` in Tenant A; global profile `sales_admin` | orders, branches, inventory, pos, procurement, reports | 2 active assignments in same tenant | BLOCKED for ordinary-worker acceptance; extra same-tenant assignment is valid |
| Worker B | Active `branch_manager` in Tenant B; global profile `sales_admin` | orders, branches, inventory, pos, procurement, reports | 1 active assignment in same tenant | BLOCKED for ordinary-worker acceptance; profile classification must change through authorized Owner path |
| Owner profile | Active profile, role `owner`; Auth user exists | profile role alone is insufficient | no branch assignment required | BLOCKED; app_metadata boolean true absent; allowlist unverifiable |
| Sales admin profiles | Active/inactive records exist | global profile permissions are not tenant authorization | must rely on tenant membership + assignment | NOT VERIFIED |

## Permission engine behavior

- `resolveTenantScopedPermissions` filters to active memberships and intersects permissions; a permission granted in Tenant A is not inherited into Tenant B.
- A wildcard grant is neutral when intersecting with a narrower membership.
- Global `admin_profiles.permissions` and job-position defaults are not tenant authorization sources.
- Owner bypass requires all of: active profile, profile role `owner`, UUID in `DLICE_PLATFORM_OWNER_USER_IDS`, and Auth `app_metadata.platform_owner === true`.
- The source check is at `supabase/functions/dlice-orders/index.ts:92-100`; permission resolver is `supabase/functions/dlice-orders/tenant-permissions.ts`.

## Action-level matrix

| Action category | Worker branch_manager | Owner | Evidence status |
|---|---|---|---|
| Own-branch POS/orders/inventory | Intended grant when active membership + branch assignment + action permission match | Owner-only or scoped as defined per action | NOT VERIFIED at runtime |
| Cross-tenant read | Must deny | Only through explicit Owner-authorized path | BLOCKED P05/P07 |
| Cross-tenant write / stock transfer | Must deny before mutation | Explicit approval and tenant-safe RPC required | BLOCKED P08/P09 |
| Finance HQ / settlement | No implicit access from branch-manager defaults | Owner only where handler requires platform owner | NOT VERIFIED |
| Tenant bootstrap / create tenant | Deny | Requires verified platform Owner and service-role RPC | BLOCKED; PR #78 HOLD |
| Audit log access | Scoped, least privilege | Platform Owner scope | NOT VERIFIED |
| Public catalog/order routing | Disabled while routing gate false | Owner configuration does not bypass release gate | BLOCKED |

## Inventory read permission refinement

The deployed v69 `erp-list-inventory` path was blocked by the global uncertified-action denylist. PR #85 proposes allowing only this read action through the explicit `inventory` permission + required branch + active membership + exact active branch assignment checks. The returned catalog is derived from the requested branch's stock rows, not the global inventory master. The global inventory master write action `erp-save-inventory` remains gated. Runtime acceptance is still pending.

## Required additions

- Add an explicit role/permission/action inventory for every Edge Function action and RPC, including read/write scope and audit requirement.
- Add direct REST/RLS tests for each exposed table and direct RPC EXECUTE denial.
- Add multi-membership regression tests (intersection, wildcard, inactive membership, assignment removal).
- Do not change role metadata or assignment records by direct SQL to make test fixtures pass.

## Additional identity classification finding

The current staging schema allows only `admin_profiles.role IN ('sales_admin','owner')`. The two active `branch_manager` tenant members both have `sales_admin` global profile classification. Their tenant permissions are equal and are correctly resolved from tenant memberships, but they cannot yet be certified as ordinary non-admin workers under the stated acceptance requirement.

PR #86 adds a non-admin `branch_worker` classification, an Owner-only conversion endpoint that requires active non-admin membership plus active same-tenant branch assignment, and an Owner UI. It remains Draft/HOLD; its migration is source-only. No existing user was changed.


## Current RBAC acceptance status — 20 November 2026

The current role model for P03 expects distinct Auth identities, active tenant memberships, and branch assignment; the global profile role may be `sales_admin` while tenant membership role is `branch_manager`. The P03 static contract has been corrected and quality checks pass. The live P01–P09 workflow still cannot validate these relationships because Tenant A/B credentials and tenant/branch/user fixture variables resolve empty in the runner. Owner bypass remains blocked because the linked Auth user's boolean `app_metadata.platform_owner=true` is absent and the server-side UUID allowlist is not verified. No role or membership assignments were modified. See `FNB_OS_IMPLEMENTATION_DELTA_20261120.md`.
