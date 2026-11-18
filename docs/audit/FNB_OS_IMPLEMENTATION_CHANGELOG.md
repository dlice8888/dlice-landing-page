# FnB OS Implementation Changelog

**18 November 2026 — continuation from PR #83**

## Repository changes performed

- PR #83 branch: `fix/p0-tenant-isolation-preflight-20261118`.
- Commit `99a20914ad1b755d730cf91b66d204f429254754`: hardened the existing-identity probe preflight to reject blank/whitespace public key, Tenant A username/password, and missing/malformed Tenant B branch UUID before any network request; login failure logs use a constant error code rather than server-provided error text.
- Commit `b3121406d00fa395ff5073e4b67997f05d81ad0f`: added table-driven no-network regression coverage for eight missing/invalid input variants, including whitespace-only values.
- Exact-head Free quality workflow [44303062590](https://github.com/dlice8888/dlice-landing-page/actions/runs/44303062590) completed SUCCESS.
- Vercel PR Preview for the updated PR #83 head is READY.
- PR #83 remains Draft/HOLD and is not merged.

## Read-only staging verification

- Confirmed 2 tenants, 155 branches, 3 active tenant memberships, 64 public tables, 64 RLS-enabled tables, 64 policies, 29 public functions, and 5 SECURITY DEFINER functions.
- Confirmed two distinct worker memberships in different tenants with the same `branch_manager` permission set.
- Confirmed Worker A has 2 active same-tenant branch assignments while Worker B has 1; there are no cross-tenant assignment rows. PR #87 corrects the previous over-strict exact-one-branch assertion.
- Confirmed active Owner profile/Auth user exists but `app_metadata.platform_owner` boolean true is absent.
- Confirmed 46 staging migration records vs 45 source migration files; source for `20261022140302` is missing.
- Confirmed PR #64 migration version `20261028120000` is not applied.
- Confirmed 26 unindexed foreign-key and 49 unused-index advisor findings; leaked-password protection warning remains.

## Not performed

No Auth metadata, branch assignment, GitHub Environment secret/variable, database schema/data, migration, release flag, branch protection, PR merge/close, production deployment or production data change was performed.


## Additional P0 implementation slice — PR #85

- Discovered deployed v69 inventory-read denial: `erp-list-inventory` was included in the tenant-wide denylist, making worker own-branch positive probes return 423 before branch authorization.
- Created Draft PR [#85](https://github.com/dlice8888/dlice-landing-page/pull/85), head `63575c051112b7ec621afc4f96a1beef62238c2b`.
- Candidate handler requires `inventory` permission, branch ID, active tenant membership and exact active assignment before any data query; it returns item details only through the selected branch's `branch_inventory` rows and retains the global inventory-master write gate.
- Exact-head Free quality workflow [44304941471](https://github.com/dlice8888/dlice-landing-page/actions/runs/44304941471) passed; tenant runtime probe contract 6/6 and service-role scope contract 4/4 passed; Deno permission tests 2/2 passed in that workflow.
- Candidate has not been deployed to staging. P04/P06 remain BLOCKED/NOT RUN until reviewed and merged to staging and then exercised through trusted runtime acceptance.

## Additional P0 worker identity work — PR #86

- Fresh staging role inventory showed the two candidate `branch_manager` tenant members are both globally classified as `sales_admin`; current role constraint permits only `sales_admin` and `owner`.
- Created Draft PR [#86](https://github.com/dlice8888/dlice-landing-page/pull/86), head `eeda0bdd715dc5477969be3196c6800d6a23eac2`.
- Added source migration `20261118190000_add_branch_worker_profile_role.sql`, Owner-only role conversion with active membership/assignment checks, Owner UI, and quality contract test.
- No migration was applied and no profile, Auth metadata, membership or assignment was changed. Exact-head GitHub Actions CI was not yet returned at this snapshot; Vercel Preview is available.

## P03 evidence hardening — PR #87

- Updated the P03 runtime probe to require two distinct Auth users, active memberships in separate tenants, `branch_worker` global profile classification, equal `branch_manager` tenant roles, and equal non-empty tenant permission sets.
- Corrected the prior exact-one-branch assertion: multiple same-tenant branch assignments are valid; the expected QA branch must be present and the other tenant's branch must remain invisible.
- Added linked profile role to the self-only membership response.
- Masked user, tenant and branch identifiers in every P01–P09 and supplemental runtime evidence record.
- Exact-head Free quality workflow [44307838730](https://github.com/dlice8888/dlice-landing-page/actions/runs/44307838730) passed 7/7 tenant runtime contract tests. No staging runtime probes were executed.

## Production deployment exception and restoration

- One documentation-only GitHub file update accidentally omitted the explicit audit branch and wrote the matrix artifact to default branch `main`.
- Vercel created production-target deployment `dpl_FV4dAmvTdERXQupSkcvqvReXqqXP` for commit `eddc1cf31f8e64e7afa23011a31cea4f2c45c9f1`.
- The file was immediately deleted from `main`; restoration commit `ab47e1ba5c5201e8ad2553c8552fcfd3dcac33a4` triggered deployment `dpl_4Fvtp6RvMwukCWFndERhgNh4Zv3e`.
- Verified the restored main tree SHA `427d9413b4e6fe070ba76a93baab533ccb528570` exactly equals the pre-incident parent tree SHA. Verified `dlice.vercel.app` points to the restoration deployment and the accidental audit matrix file is absent from main.
- No application code, database, Auth metadata or production data was changed. Production deployment did occur; this is explicitly recorded as an exception. No further production deployment is authorized.

## Migration source parity recovery — PR #88

- Queried the actual staging migration history row `20261022140302`, name `add_missing_fk_supporting_indexes`.
- Recovered all nine original index statements and added them to isolated PR [#88](https://github.com/dlice8888/dlice-landing-page/pull/88).
- Normalized source SQL exactly matches the applied staging migration-history SQL.
- Added a migration contract test and release/rollback note. Quality and disposable replay were still pending at the snapshot; no staging migration was reapplied.

## PR #83 exact-head verification — 2026-11-18

- PR #83 head: `b3121406d00fa395ff5073e4b67997f05d81ad0f`; draft, open, mergeable; Vercel Preview `dpl_EANn7yD2SrmKRodsqYZppJajqZAw` READY.
- Free quality run [44303062590](https://github.com/dlice8888/dlice-landing-page/actions/runs/44303062590) SUCCESS. The workflow includes staging secret workflow, tenant-isolation runtime evidence and public-routing gate checks. The log contains passing test groups of 5/5, 4/4, 11/11, 5/5 and 1/1.
- `branchB` is declared before the fail-closed preflight in `tests/staging/tenant-isolation-existing-identity.mjs`, eliminating the previously observed temporal-dead-zone path.
- Added subprocess regression cases for empty public key, Tenant A username, Tenant A password, Tenant B branch ID, whitespace-only public key/username/password and malformed branch UUID. Each expects exit code 2, BLOCKED, no stdout/network output, no credential/token disclosure and no ReferenceError.
- The workflow now references `secrets.STAGING_SUPABASE_PUBLIC_KEY` rather than a literal public key. The actual GitHub Environment secret's availability is still not independently readable; PR #83's quality run is not a tenant-isolation runtime proof.
- **P01–P09 remain BLOCKED / NOT RUN**; no claim of tenant isolation PASS is made.


## Fresh staging evidence checkpoint — 2026-11-18

- Read-only Supabase inspection reconfirmed two active candidate workers: both currently `sales_admin` profiles with `branch_manager` memberships and six permissions; active assignment counts are one and two, each within one tenant. No worker role or assignment was changed.
- The live profile role constraint still excludes `branch_worker`; PR #86 migration remains unapplied. The Owner profile exists, but the linked Auth user set contains zero boolean `platform_owner=true` values; allowlist not independently readable.
- Tenant acceptance run [44207773570](https://github.com/dlice8888/dlice-landing-page/actions/runs/44207773570) returned 9 BLOCKED / 0 SKIPPED because worker credentials and canonical fixture IDs were empty. No P01–P09 request executed.
- Existing-identity probe [44208204366](https://github.com/dlice8888/dlice-landing-page/actions/runs/44208204366) blocked without account creation. P0 HTTP bootstrap [44207773489](https://github.com/dlice8888/dlice-landing-page/actions/runs/44207773489) blocked by missing Owner QA credentials.
- No staging or production mutation occurred. No credentials or full identity identifiers were copied into this report.
