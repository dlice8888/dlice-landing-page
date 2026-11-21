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
3. Verify Owner Auth metadata through official Supabase Auth Admin, preserving other metadata, and verify the UUID allowlist through a protected runtime configuration check.
4. Run P01–P09 and supplemental direct REST/RPC tests on trusted staging; no SKIPPED or false PASS.
5. Keep both release flags false and PR #64 Draft/HOLD until the complete automated adversarial test matrix and runtime evidence pass.

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
- The workflow now references `secrets.STAGING_SUPABASE_PUBLIC_KEY` rather than a literal public key. The GitHub Environment secret availability cannot be queried through the connected integration; PR #83's quality run is not a tenant-isolation runtime proof.
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


### Canonical QA branch assignment cross-check
A second read-only query confirmed the configured branch fixtures already exist and are actively assigned: tenant `dlice-default` has `QA-DLICE-A` (the same worker also has `DLC-B001`), and tenant `dlice-qa-isolation-b` has `QA-TENANT-B`. Both memberships have role `branch_manager`, six permissions, and the same permission-set fingerprint. The two candidate users are distinct membership rows in different tenants. This confirms branch assignment data is present; it does not provide passwords or prove either login. Populate the canonical GitHub variables from the existing records—do not create substitute tenants, branches, users, or assignments.


## Correction to the prior staging fixture status — 2026-11-18

The earlier wording that Tenant A/B credentials and all six fixture variables were currently "empty/missing" was too broad and is superseded by this correction.

- The user-provided GitHub Environment `staging` inventory already lists the four canonical Tenant A/B username/password secrets and all six Tenant A/B tenant/branch/user variables. The staging acceptance workflow at the exact run commit declares `environment: staging` and references those same names. Therefore the inventory names are present; do not instruct the user to recreate them.
- The historical run [44207773570](https://github.com/dlice8888/dlice-landing-page/actions/runs/44207773570), created 2026-11-18 00:26 UTC, logged empty values for those ten inputs at execution time. This proves that run did not receive their values; it does not establish that the current Environment inventory is empty. The connected GitHub tool cannot inspect decrypted secret values or Environment-scoped variable values, so the reason for the resolution discrepancy is not yet established.
- Read-only Supabase verification now confirms all six configured fixture UUIDs exist in their respective tables and match the intended records exactly: Tenant A `dlice-default` / branch `QA-DLICE-A` / existing user A; Tenant B `dlice-qa-isolation-b` / branch `QA-TENANT-B` / existing user B. No fixture IDs need to be recreated or replaced.
- Both users have active `branch_manager` tenant memberships, six equal permissions, and active assignments within their own tenant. User A has two active same-tenant branches (`DLC-B001` and `QA-DLICE-A`); user B has one (`QA-TENANT-B`). The P03 runtime script on staging still requires exactly one branch for each identity, which incorrectly rejects User A's valid same-tenant second assignment. This is a code/test defect, not a missing assignment.

Next diagnostic: execute a fresh `Staging Tenant Isolation Acceptance` workflow_dispatch on branch `staging` without changing/recreating configuration. If the ten inputs still resolve empty, inspect the exact GitHub Environment scope/name and access settings with repository administration access. Before treating P03 as valid, correct its one-branch-only assertion to require the configured QA branch and reject only cross-tenant visibility. Inventory action authorization must also be repaired/deployed before P04/P06 can prove own-branch reads.


## Superseding security audit — 21 November 2026, 19:42 WIB

### Tenant fixture identities

Read-only Supabase Auth and application-table joins confirm two real QA users:
- Tenant A: `qa_dlice_staging_no_permission`, active `sales_admin` profile, empty global profile permission array, active `branch_manager` membership in `dlice-default`, six tenant membership permissions, active `QA-DLICE-A` branch assignment.
- Tenant B: `qa_dlice_staging_branch_a`, active `sales_admin` profile, seven global profile permissions, active `branch_manager` membership in `dlice-qa-isolation-b`, the same six tenant membership permissions, active `QA-TENANT-B` branch assignment.
- The runtime resolver deliberately derives tenant permissions from active tenant memberships, not global profile permissions. These fixtures match the PR #126 fixture resolver. No Auth user, password, metadata, membership or assignment was changed.
- Existing Owner profile and tenant_owner membership are active, but Auth `app_metadata.platform_owner` is absent; the platform-owner allowlist cannot be queried through the connected integration. Owner bypass remains unavailable.

### Password mutation control

PR #120 includes the same HIBP k-anonymity guard as PR #124 on the three application-managed flows: initial Owner bootstrap, staff creation and staff password reset. It hashes locally, sends only the first five SHA-1 characters, uses padding, rejects compromised passwords and fails closed if the HIBP service is unavailable.

This does **not** prevent direct calls to Supabase Auth password-update endpoints. Supabase native leaked-password protection is disabled on the current Free plan and the documented Password Verification Hook applies to password verification/sign-in, not password-change requests (and is plan-limited). No supported Free-plan hook closes the direct Auth password-change bypass. Classify leaked-password protection as PARTIAL: official application password paths have an HIBP k-anonymity guard and passing tests, but native Auth leaked-password protection is disabled and direct Auth password updates remain an uncovered bypass. Do not claim universal enforcement or DONE. The staff reset path now writes a durable audit intent before Auth Admin updateUserById, then finalizes success/failure. If finalization fails, the pending intent remains for reconciliation. Auth and Postgres still cannot share a single distributed transaction; this is an explicit intent/outcome saga, not a claim of cross-service atomicity.

### GitHub release protection

Ruleset #27559290 is active on all branches but has zero required approvals, zero required status checks and zero required deployment environments. Eleven bypass actors have `always` bypass and the connected identity can bypass. Project acceptance is test-evidence-only and does not require separate independent PR review. However, the active repository ruleset still has require_code_owner_review=true and require_last_push_approval=true; these repository settings remain enabled and cannot be edited through the connected GitHub integration. It also has zero required status checks, zero required deployment environments and 11 always-bypass actors. Deployment protections and explicit staging authorization remain separate controls. No ruleset mutation was made.

### Runtime boundary

P01–P09 are NOT RUN. PR #126's passwordless workflow requires a protected staging Environment service-role secret and can execute only from `refs/heads/staging` after the workflow is integrated there. No JWT, password, API key or secret was exposed in this audit.


## Current verification update — 21 November 2026

- PR #120 exact head 471f4a330a4da0cb13afe60ddeeb520e28dc0e88 passes all six applicable workflows, including disposable migration replay. Permission, staff creation, role, active-state and password reset audit paths now have code/DB tests; password reset uses a durable intent/outcome event.
- PR #124 is closed/superseded by #120.
- Two existing Auth identities are distinct and have active memberships. Tenant A active assignments: QA-DLICE-A and DLC-B001. Tenant B active assignment: QA-TENANT-B. Both last signed in 2026-10-25; no current passwordless session was minted in this execution.
- P01–P09 are NOT RUN. Staging Environment protection and STAGING_SUPABASE_SERVICE_ROLE_KEY presence are NOT VERIFIED. The secret value was not read or exposed; no workflow dispatch action is available through the connected GitHub integration.
- No staging migration, Auth metadata, password, Edge Function or production state was changed.

## Current tenant fixture and runtime status — 21 November 2026, 20:58 WIB

Read-only Supabase staging queries confirmed the existing Tenant A and Tenant B Auth identities:
- Tenant A: active sales_admin profile, active branch_manager membership in dlice-default, six membership permissions, active QA-DLICE-A branch.
- Tenant B: active sales_admin profile, active branch_manager membership in dlice-qa-isolation-b, six membership permissions, active QA-TENANT-B branch.
- Both Auth emails are confirmed and the user IDs are distinct. No account/password/metadata/membership mutation occurred.

PR #126 now implements the passwordless Supabase Auth Admin magic-link path for these existing identities. It requires STAGING_SUPABASE_SERVICE_ROLE_KEY in the protected staging Environment. Secret presence and Environment protection are NOT VERIFIED; the connected GitHub integration exposes no workflow-dispatch action. P01–P09 are NOT RUN.

Supplemental read-only SQL impersonation using each Auth subject verified auth.uid() and auth.role() and returned zero direct branch-table rows for own and foreign QA branch reads (4/4). This is not a live Auth session or Edge Function authorization test. The stock-transfer RPC remains inaccessible to anon/authenticated and executable by service_role only.

Keep TENANT_ISOLATION_RELEASED=false and PUBLIC_TENANT_ROUTING_RELEASED=false until all live runtime acceptance passes.

## Branch assignment fixture verification — 21 November 2026, 21:03 WIB

Read-only SQL confirmed the exact runtime fixture assignments used by the passwordless harness:
- Tenant A existing Auth identity has active assignment to `QA-DLICE-A`, starts 2026-11-14, no end date.
- Tenant B existing Auth identity has active assignment to `QA-TENANT-B`, starts 2026-10-25, no end date.
- Both assignments satisfy today's date and the deployed `branchAccess` helper's active/date predicates.

This is fixture evidence only. No Auth login or Edge Function HTTP probe was executed.

## Deployed runtime contract inspection — 21 November 2026, 21:06 WIB

Supabase reports `dlice-orders` ACTIVE at version 70 (source SHA-256 `597a371d2c05cbfa7b0e04a749e422bf826667b4539ce2b44ffe0a2efb0ff9f6`). The deployed source still hard-codes both `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.

Runtime source inspection (not an HTTP execution) confirms:
- `erp-list-inventory` requires `branchAccess(branch_id)` before reading `branch_inventory`; item metadata is limited to inventory item IDs already present in the authorized branch's balances.
- `erp-create-stock-transfer` requires active access to both source and destination branches, validates an idempotency key, and calls the server-only stock-transfer RPC.
- `erp-transition-stock-transfer` checks same-tenant source/destination for approval unless the actor is the platform owner; other transitions require branch access.
- `admin-set-permissions`, `admin-create-staff` and `admin-reset-staff-password` remain in the uncertified-action denylist and return 423 to non-platform-owner users while tenant isolation remains unreleased.
- Deployed v70 still has the legacy multi-step invitation handler. The atomic invitation route in PR #120/#126 is candidate code and has not been deployed.

Both existing QA branch assignments satisfy the deployed helper's active/date predicates. These source and fixture checks do not replace actual HTTP probes; P01–P09 remain NOT RUN.

