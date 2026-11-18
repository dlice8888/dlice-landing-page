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
