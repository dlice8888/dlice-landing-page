# FnB OS Security Audit

**Snapshot:** 18 November 2026  
**Supabase target:** staging `higoadrzxnhzbbwhdbmh`  
**Production:** excluded

## Auth and tenant identity

- Two worker memberships are present in separate tenants. Both have role `branch_manager` and identical permission arrays: `orders, branches, inventory, pos, procurement, reports`.
- Memberships are active and worker identities are distinct in the staging inventory.
- Worker A has two active assignments in its own tenant; Worker B has one. No cross-tenant assignment rows were found. The previous exact-one-branch P03 assertion was stricter than the acceptance requirement; PR #87 now allows multiple same-tenant assignments while checking the configured branch and cross-tenant branch invisibility.
- One active Owner profile is linked to an Auth user, but the Auth user lacks `app_metadata.platform_owner=true` as a boolean. Read-only count of Auth users with that boolean true: 0.
- GitHub Environment variables/secrets and `DLICE_PLATFORM_OWNER_USER_IDS` could not be read through the connected integration. Their values were not queried or printed.

## Authorization source references

| Control | Source |
|---|---|
| Tenant release flag false | `supabase/functions/dlice-orders/index.ts:52` |
| Owner UUID allowlist | `supabase/functions/dlice-orders/index.ts:55-57` |
| Owner authorization conjunction | `supabase/functions/dlice-orders/index.ts:92-100` |
| Uncertified action denylist | `supabase/functions/dlice-orders/index.ts:60-89` |
| Public tenant routing flag false | `supabase/functions/dlice-orders/index.ts:135-144` |
| Active membership permission intersection | `supabase/functions/dlice-orders/tenant-permissions.ts` |

## Database security inventory

- 64 public base tables; all 64 have RLS enabled.
- 64 public policies; policy semantics and each table/action pairing still require per-policy tests.
- 29 public functions; 5 SECURITY DEFINER functions.
- The five SECURITY DEFINER stock functions (`erp_create_stock_count`, `erp_create_stock_transfer`, `erp_post_stock_count`, `erp_transition_stock_transfer`, `erp_update_stock_count_item`) currently show EXECUTE denied to `anon` and `authenticated`, granted to `service_role`.
- Direct table grants to `anon` and `authenticated` are limited to SELECT on `public.products`.
- No public views were returned by the read-only inventory query.
- Do not infer policy correctness from RLS enabled state alone.

## Advisor findings

- Security: leaked-password protection disabled (WARN).
- Performance: 26 unindexed foreign-key findings; 49 unused-index suggestions. Do not drop unused indexes without workload/query-plan review.
- No database DDL or Auth configuration was changed during this audit.

## Deployed Edge Function and inventory read gap

Staging `dlice-orders` is ACTIVE at version 69, `verify_jwt=false`, deployed source SHA-256 `d4acc79adc13048a993fe03987df9dbd245a5336336e87a567b0157320ed5d40`. Custom token validation is performed by `authClient.auth.getUser(token)` inside `getAdmin`; do not infer that `verify_jwt=false` means there is no authentication.

The deployed denylist at `index.ts:71` and guard at `454-455` blocked `erp-list-inventory` with HTTP 423 for non-platform-owner users while the release flag was false. The old handler at `1266-1275` queried the global `inventory_items` table. PR #85 is a candidate fix: explicit inventory permission, mandatory branch ID, active membership and exact active assignment check before any query, and branch_inventory-to-inventory_items join. It retains the global inventory master write denylist. Exact-head quality CI 44304941471 passed; the change has not been deployed to staging, so this is not runtime proof.

## P0 evidence status

| Test | Status | Reason |
|---|---|---|
| P01 Tenant A login | BLOCKED | Protected credential availability cannot be verified; no trusted run |
| P02 Tenant B login | BLOCKED | Protected credential availability cannot be verified; no trusted run |
| P03 distinct identity/membership/ordinary worker/permissions/branch | BLOCKED | No runtime run; both profiles remain sales_admin; PR #87 adds branch_worker and equal-permission checks |
| P04 A own-branch inventory read | BLOCKED | No authenticated runtime read |
| P05 A cross-tenant read denied | BLOCKED | No authenticated runtime negative test |
| P06 B own-branch inventory read | BLOCKED | No authenticated runtime read |
| P07 B cross-tenant read denied | BLOCKED | No authenticated runtime negative test |
| P08 A cross-tenant write denied | BLOCKED | No authenticated runtime negative test |
| P09 B cross-tenant write denied | BLOCKED | No authenticated runtime negative test |

Latest known staging runtime attempt `44208204366` was blocked at preflight before network access. Static quality run `44303062590` is not tenant runtime evidence.

## Required secure remediation

1. Review/merge PR #87's P03 correction; do not alter Worker A's same-tenant assignments merely to satisfy the obsolete exact-one assertion.
2. Verify canonical two-worker credentials and six fixture variables by presence/availability only in GitHub Environment `staging`.
3. Verify Owner Auth metadata through official Supabase Auth Admin, preserving other metadata, and independently verify UUID allowlist.
4. Run P01–P09 and supplemental direct REST/RPC tests on trusted staging; no SKIPPED or false PASS.
5. Keep both release flags false and PR #64 Draft/HOLD until independent security review and runtime evidence pass.

## Ordinary worker identity classification — additional P0

Fresh staging read-only evidence:
- Both non-owner tenant members have tenant membership role `branch_manager`, identical permission sets and active Auth accounts.
- Both linked `admin_profiles.role` values are `sales_admin`.
- The actual database check constraint `admin_profiles_role_check` permits only `sales_admin` and `owner`; no ordinary `branch_worker` identity type currently exists.
- The app's Owner bypass remains independent and requires the allowlisted UUID plus boolean Auth app metadata. Global profile permissions are not used for tenant permission resolution.

PR #86 introduces a source-only `branch_worker` classification and Owner-only conversion action requiring active non-admin tenant membership and active same-tenant assignment. It does not modify existing users or Auth metadata. Migration `20261118190000_add_branch_worker_profile_role.sql` is not applied. P03 remains BLOCKED until an authorized Owner action classifies real workers and the runtime probe verifies the identities.

## CORS runtime evidence

Staging runtime workflow [44307838539](https://github.com/dlice8888/dlice-landing-page/actions/runs/44307838539) executed three live OPTIONS probes:
- registered staging Preview origin: HTTP 200 and exact matching ACAO;
- foreign origin: HTTP 403 and no ACAO;
- no Origin header: HTTP 200 and no fallback ACAO.

All three CORS runtime probes passed. They are distinct from tenant authentication and cross-tenant P01–P09, which remain BLOCKED/NOT RUN.

## PR #83 exact-head verification — 2026-11-18

- PR #83 head: `b3121406d00fa395ff5073e4b67997f05d81ad0f`; draft, open, mergeable; Vercel Preview `dpl_EANn7yD2SrmKRodsqYZppJajqZAw` READY.
- Free quality run [44303062590](https://github.com/dlice8888/dlice-landing-page/actions/runs/44303062590) SUCCESS. The workflow includes staging secret workflow, tenant-isolation runtime evidence and public-routing gate checks. The log contains passing test groups of 5/5, 4/4, 11/11, 5/5 and 1/1.
- `branchB` is declared before the fail-closed preflight in `tests/staging/tenant-isolation-existing-identity.mjs`, eliminating the previously observed temporal-dead-zone path.
- Added subprocess regression cases for empty public key, Tenant A username, Tenant A password, Tenant B branch ID, whitespace-only public key/username/password and malformed branch UUID. Each expects exit code 2, BLOCKED, no stdout/network output, no credential/token disclosure and no ReferenceError.
- The workflow now references `secrets.STAGING_SUPABASE_PUBLIC_KEY` rather than a literal public key. The actual GitHub Environment secret's availability is still not independently readable; PR #83's quality run is not a tenant-isolation runtime proof.
- **P01–P09 remain BLOCKED / NOT RUN**; no claim of tenant isolation PASS is made.


## Fresh staging authentication and worker fixture check — 2026-11-18

Read-only Supabase inspection (project `higoadrzxnhzbbwhdbmh`):
- Two active non-owner identities have active `branch_manager` tenant memberships and six permissions each. Their profile classification is still `sales_admin`; no active `branch_worker` profile exists.
- One worker has one active branch assignment and the other has two. Each worker's active assignments remain within its own tenant; no cross-tenant assignment was found in the aggregate inventory. Do not remove the second same-tenant assignment merely to simplify testing.
- The live `admin_profiles_role_check` constraint still allows only `sales_admin` and `owner`. PR #86's migration remains source-only; no staging migration or profile conversion was performed.
- One active Owner profile exists, but the linked Auth metadata aggregate reports zero accounts with boolean `app_metadata.platform_owner=true`. The Owner UUID allowlist is not readable through the connected tools. Owner authorization therefore remains BLOCKED, not assumed from the profile row alone.

Latest staging workflow evidence:
- Tenant acceptance run [44207773570](https://github.com/dlice8888/dlice-landing-page/actions/runs/44207773570): P01–P09 all **BLOCKED**, 0 PASS, 0 FAILED, 9 BLOCKED, 0 SKIPPED. URL and public key preflight passed; both worker credential pairs and all tenant/branch/user fixture IDs were empty. No probe request executed.
- Existing-identity negative probe run [44208204366](https://github.com/dlice8888/dlice-landing-page/actions/runs/44208204366): **BLOCKED** because canonical Tenant A credentials or Tenant B branch fixture are not configured; log explicitly confirms no account was created.
- P0 HTTP run [44207773489](https://github.com/dlice8888/dlice-landing-page/actions/runs/44207773489): **BLOCKED** because the existing Owner QA username/password are missing; no business-flow bootstrap ran.

The GitHub integration does not expose Actions Environment secret/variable values or provide workflow-dispatch capability. Do not infer fixture values from database rows or create substitute accounts. P01–P09 and Owner authorization remain unverified until the authorized maintainer provisions the real fixture references and completes the official Owner Auth metadata/allowlist step.
