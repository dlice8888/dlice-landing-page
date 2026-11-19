# FnB OS Migration Reconciliation

**Snapshot:** 18 November 2026  
**Database:** Supabase staging `higoadrzxnhzbbwhdbmh`

## Migration parity

- Supabase migration history contains **46** applied entries.
- Repository `staging` contains **45** migration source files.
- The source file for applied migration version `20261022140302` is absent from the inspected `supabase/migrations` directory. This is a source/history parity defect and must be recovered from the authoritative migration artifact or reconciled with an approved no-op/tombstone strategy; do not invent SQL.
- Latest applied staging migration is `20261027140145_revoke_client_execute_on_trigger_only_functions`.
- PR #64 migration `20261028120000_enforce_same_tenant_stock_transfers.sql` is **not** in staging migration history and has not been applied to staging or production.

## Current database inventory

| Item | Staging result |
|---|---:|
| Public base tables | 64 |
| Tables with RLS | 64 |
| Tables without RLS | 0 |
| Public policies | 64 |
| Public functions | 29 |
| SECURITY DEFINER functions | 5 |
| Unindexed foreign keys (advisor) | 26 |
| Unused index suggestions (advisor) | 49 |

## ACL findings

The five SECURITY DEFINER stock functions are executable by `service_role` and denied to `anon` and `authenticated` in the current privilege query. Direct `anon`/`authenticated` table grants in public are limited to SELECT on `public.products`.

## Required migration workflow

1. Recover the missing `20261022140302` source from a trusted backup/commit/artifact and compare checksum with applied SQL if available.
2. Map every open PR migration path and blob SHA; resolve duplicates before review.
3. Run disposable PostgreSQL replay from zero and from the current staging baseline; include pgTAP, rollback and grants/RLS checks.
4. Run Supabase advisors and inspect query plans for any index changes.
5. Obtain independent migration/security review and backup/rollback plan.
6. Apply only to staging through the authorized migration workflow after explicit authorization; never apply PR #64 migration while acceptance is incomplete.
7. Verify migration history, schema diff, policies, grants, functions and data invariants after application.

No staging DDL, migration application, production migration, or database data mutation occurred during this audit.

## New source-only migration candidate

PR #86 adds `supabase/migrations/20261118190000_add_branch_worker_profile_role.sql` to extend `admin_profiles_role_check` with the `branch_worker` identity classification. This migration is not applied to staging or production. It requires disposable replay, independent review, backup/rollback planning and explicit staging authorization. It is unrelated to PR #64's tenant stock-transfer migration and does not authorize that migration.

## Disposable replay result — PR #86

The new `20261118190000_add_branch_worker_profile_role.sql` migration was replayed successfully on the disposable local Supabase database in workflow run [44306779612](https://github.com/dlice8888/dlice-landing-page/actions/runs/44306779612). The log confirms all repository migrations, including this migration, applied to the disposable database. This does not apply the migration to staging. Independent review, backup/rollback plan and explicit staging authorization remain required.

## Exact source recovery candidate — PR #88

The applied migration history row was queried directly and returned name `add_missing_fk_supporting_indexes` with one stored SQL string containing nine `CREATE INDEX IF NOT EXISTS` statements. PR #88 restores `20261022140302_add_missing_fk_supporting_indexes.sql`; normalized SQL comparison is an exact match to the applied history statement. A fresh `pg_indexes` query confirms all nine indexes exist in staging. PR #88 quality workflow 44309825502 passed 1/1, and disposable local replay 44309825526 passed with all 46 repository migrations applied. The source file is not yet merged to staging. Do not reapply the migration to staging because it is already recorded as applied.

A fresh read-only `pg_indexes` query confirmed all nine recovered indexes currently exist in staging with the expected table/column definitions. This validates the applied index objects independently of the migration-history row; source parity remains open until PR #88 is merged and disposable replay passes.

## Disposable replay completed — PR #88

- Exact-head quality run [44309825502](https://github.com/dlice8888/dlice-landing-page/actions/runs/44309825502) succeeded; recovered migration contract 1/1 passed.
- Disposable full migration replay [44309825526](https://github.com/dlice8888/dlice-landing-page/actions/runs/44309825526), job `134821567927`, succeeded. Logs explicitly show `20261022140302_add_missing_fk_supporting_indexes.sql` applied and the complete repository migration set finished.
- Initial replay attempt hit Docker registry rate limiting and port 54322 collision; retry succeeded. This was infra flakiness, not a migration SQL failure.
- PR #88 remains open and Draft; no staging migration was re-applied. Source restoration is validated, but staging migration parity remains a release gate until reviewed/merged through normal controls.

## Superseding live migration reconciliation — 2026-11-19

This section supersedes the earlier 46/45 migration count and source-mismatch details above.

- Supabase staging migration history: 47 applied rows.
- staging source tree: 47 SQL migration files.
- main source tree: 2 SQL migration files.
- The staging and database sets are not identical: applied version 20261118165519 named 20261118193000_revoke_public_stock_workflow_rpc_execute is absent from the staging migration directory. Its exact SQL source exists in PR #94 at supabase/migrations/20261118165519_20261118193000_revoke_public_stock_workflow_rpc_execute.sql.
- Staging contains 20261118190000_add_branch_worker_profile_role.sql, but no corresponding version exists in applied migration history. It remains source-only and must not be applied merely to make counts match.
- Main baseline filenames (20261018000000, 20261018001000) differ from the applied staging baseline (20261017183506, 20261017183509). Production is a separate project and is currently INACTIVE; its migration history could not be inspected. No staging-to-production bulk replay or filename renumbering is safe.
- Read-only staging ACL verification reconfirmed all five stock workflow SECURITY DEFINER functions have anon=false, authenticated=false, service_role=true.
- Read-only RLS verification: 64/64 public base tables have RLS enabled and 64/64 have a policy. Client table grants are constrained by deny/service-role-only policies; products intentionally allows SELECT of active products. This is configuration evidence, not a replacement for runtime adversarial tests.
- Supabase Security Advisor: leaked-password protection disabled (WARN). Performance Advisor: 26 unindexed foreign keys (INFO). No schema or migration changes were made during these checks.

Required next actions: recover the exact PR #94 migration source into the staging source-of-truth through review without reapplying it; decide separately whether the un-applied branch_worker role migration is still required by the approved identity model; then build a production-specific migration plan only after the inactive production project is safely available for read-only history/schema comparison.

## Superseding status — 20 November 2026

See `FNB_OS_IMPLEMENTATION_DELTA_20261120.md` for the current result. The previously missing applied migration source `20261022140302_add_missing_fk_supporting_indexes.sql` has been recovered from the live staging migration-history `statements` field and verified to match exactly after trimming surrounding whitespace. Current staging has 52 source files and 48 applied migration-history rows: four pending migrations, zero applied versions without source, and zero duplicate versions. No pending migration has been applied to shared staging.
