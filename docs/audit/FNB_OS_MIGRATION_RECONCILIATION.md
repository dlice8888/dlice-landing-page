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

The applied migration history row was queried directly and returned name `add_missing_fk_supporting_indexes` with one stored SQL string containing nine `CREATE INDEX IF NOT EXISTS` statements. PR #88 restores `20261022140302_add_missing_fk_supporting_indexes.sql`; normalized SQL comparison is an exact match to the applied history statement. The source file is not yet on staging; PR #88 quality and disposable replay are pending. Do not reapply the migration to staging because it is already recorded as applied.

A fresh read-only `pg_indexes` query confirmed all nine recovered indexes currently exist in staging with the expected table/column definitions. This validates the applied index objects independently of the migration-history row; source parity remains open until PR #88 is merged and disposable replay passes.
