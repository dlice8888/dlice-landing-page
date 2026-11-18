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
