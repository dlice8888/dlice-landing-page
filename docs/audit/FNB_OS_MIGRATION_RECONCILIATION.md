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

## Fresh source/history reconciliation — 2026-11-20

This section supersedes the 2026-11-19 source/history counts above.

- Live staging migration history: **48 applied versions**.
- Current staging source: **52 SQL migration files**.
- Applied versions missing from source: **0**.
- Duplicate source versions: **0**.
- Source versions not yet applied to live staging: **4**:
  - 20261119160000_revoke_default_public_function_execute.sql
  - 20261120100000_atomic_owner_and_tenant_bootstrap.sql
  - 20261120110000_command_center_summary.sql
  - 20261120120000_atomic_branch_checklist_audit.sql
- No live staging or production migration was applied during this checkpoint.

The exact staging-head disposable replay is workflow run [44579674275](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674275), commit 4a13e70ce29e3fe117b6b6e7705089fa4241298a. Its log confirms all **52** repository migrations applied to a clean local Supabase database and **67 pgTAP assertions across 4 SQL test files passed**. This is clean-database replay evidence, not live staging application evidence.

Supabase Advisor recheck:
- Security: leaked-password protection disabled (WARN).
- Performance: 26 unindexed foreign keys and 49 unused-index suggestions (INFO; unused-index signals need workload-aware review, not automatic deletion).
- Health: no findings.

The 26 unindexed foreign keys require a table/column/index coverage review before a new index migration is authored. Do not blindly add indexes where an existing composite index may already cover the FK prefix. The ACL migration is included in the successful disposable replay; it is still pending on live staging and must not be described as applied there.


## Superseding reconciliation — 21 November 2026, 19:42 WIB

Fresh read-only queries against the current `staging` branch and Supabase project confirm:

- Staging Git branch head: `78f929dac2b05f436aaa7f50005310166f8a4779`.
- Applied Supabase migration history: **49** versions, latest `20261119182606_revoke_default_public_function_execute`.
- Staging source directory: **52** SQL files.
- Applied versions missing from source: **0**.
- Source files not yet applied to staging: exactly **3** — `20261120100000_atomic_owner_and_tenant_bootstrap.sql`, `20261120110000_command_center_summary.sql`, and `20261120120000_atomic_branch_checklist_audit.sql`.
- No staging migration was applied during this audit.

### Additional open-PR migration candidates — do not apply yet

| PR | Migration file | Version | Current evidence |
|---:|---|---|---|
| #120 | `20261121100000_atomic_admin_permission_audit.sql` | 20261121100000 | Disposable replay PASS on exact PR head; review pending |
| #123 | `20261121130000_atomic_online_order_idempotency.sql` | 20261121130000 | Disposable replay PASS; version collision with #126 |
| #126 | `20261121130000_atomic_tenant_invite_lifecycle.sql` | 20261121130000 | Disposable replay PASS; version collision with #123 |
| #125 / #127 | `20261121140000_order_expiry_payment_lifecycle.sql` | 20261121140000 | Blob SHA `c1d1de05b61055a0003a889d70b5e41a298caffd` is identical in both PRs; #127 descends from #125 |
| #127 | `20261121150000_atomic_customer_payment_proof.sql` | 20261121150000 | Disposable replay PASS; runtime E2E pending |
| #120 | `20261121160000_atomic_admin_profile_mutation_audit.sql` | 20261121160000 | Disposable replay PASS; review pending |
| #127 | `20261121180000_supersede_stale_payment_attempts.sql` | 20261121180000 | Disposable replay PASS; runtime E2E pending |

**P0 migration collision:** PR #123 and PR #126 both introduce version `20261121130000` with different SQL and different blob SHAs. They cannot both be integrated unchanged. Use the Supabase CLI migration generator to assign a unique version to one migration, then replay the combined candidate set. Do not hand-invent or silently rename the migration timestamp.

**Invitation overlap:** PR #120 and #126 both add invitation mutation functions with different names/signatures and modify the same Edge Function routes. The final combined branch must retain one canonical issue/accept flow, one audit model and a single set of RPC signatures before merge.

### Required closeout

1. Resolve the #123/#126 version collision and #120/#126 invitation RPC overlap.
2. Rebuild a single combined candidate branch in dependency order; run full disposable replay from zero and all pgTAP suites.
3. Reconcile the three existing staging-source-only migrations with their approved rollout plan.
4. Obtain independent migration/security review, backup/rollback plan and explicit staging approval.
5. Only then use the authorized staging migration workflow; never apply candidates directly or to production.
