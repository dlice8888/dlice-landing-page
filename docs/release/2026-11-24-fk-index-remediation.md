# Staging FK index remediation — 24 November 2026

## Purpose
Add leading-column indexes for 26 foreign-key constraints reported by the Supabase Performance Advisor in staging project `higoadrzxnhzbbwhdbmh`.

## Migration files
- `20261124121059_add_fk_covering_indexes.sql`: creates 24 indexes covering 26 FK constraints; composite leading-column indexes cover paired tenant/branch constraints.
- `20261124121111_remove_redundant_zero_scan_indexes.sql`: removes two single-column indexes only where an existing composite UNIQUE index retains the same leading key.

## Evidence and safety
- A read-only PostgreSQL catalog query on 24-Nov confirms 26 FK constraints without a matching leading-column index.
- A read-only index-statistics query shows zero scans for the two proposed removals; zero scans alone is not treated as proof. Structural coverage is asserted by the pgTAP test.
- The SQL test `supabase/tests/foreign_key_covering_indexes.test.sql` asserts all 24 indexes and both redundant-index removals/retained composite indexes (28 assertions).
- Prior PR #122 replay passed on its old head, but this rebased PR must pass a fresh exact-head disposable replay before merge.
- No shared staging migration is applied by this PR. Do not apply migrations to shared staging until disposable replay, dependency review and explicit staging approval are complete.
- No production DB or Vercel Production action. Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.

## Rollback consideration
If a shared staging application is separately approved and later must be reversed, do not blindly drop the indexes while workloads are active. Review dependent query plans and recreate the previous indexes before any destructive rollback. The migration itself is additive except for the two structurally redundant indexes described above.


## Staging application follow-up — 24 November 2026
The original 24-index migration and the two-index cleanup are applied under versions 20261124121059 and 20261124121111. A later checklist migration added the missing FK index for `branch_operation_checklist_runs.updated_by` as version 20261124121515. The latest Performance Advisor reports zero unindexed foreign keys. Unused-index suggestions remain informational; do not remove them without workload/query-plan evidence.
