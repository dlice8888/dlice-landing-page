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
- Confirmed Worker A has 2 active same-tenant branch assignments while Worker B has 1; P03 exact-one-branch assertion remains a blocker.
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
