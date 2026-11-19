# Staging migration parity audit

**Date:** 2026-11-17  
**Target:** Supabase staging `higoadrzxnhzbbwhdbmh`  
**Mutation scope:** Read-only only.

## Migration tracking

- Staging reports 46 migration records, latest version `20261027140145`.
- Version `20261022140302` / `add_missing_fk_supporting_indexes` is present in the database migration tracking table.
- Expected SQL source is absent from the inspected staging/main refs and one historical audit branch; GitHub code search returned no matching file.
- Original commit, source blob, SHA-256, and dependency evidence are not available.

**Decision: BLOCKED.** Database tracking does not replace the original migration source. Do not reconstruct or replay guessed SQL.

## Schema/security snapshot

| Check | Observed | Status |
|---|---:|---|
| Public base tables | 64 | Observed |
| Public tables with RLS enabled | 64 | PASS |
| Public tables with RLS disabled | 0 | PASS |
| Public policies | 64 | Observed |
| Public SQL functions | 29 | Observed |
| Public SECURITY DEFINER functions | 5 | Review required |

These counts do not prove every policy or privileged function is semantically safe. The five SECURITY DEFINER functions require code/ACL review.

## Supabase advisors

- Security advisor: 1 warning — leaked-password protection disabled.
- Performance advisor: 26 unindexed foreign-key findings.
- Performance advisor: 49 unused-index findings.

Unused-index warnings are workload-dependent and must not trigger blind index deletion. Unindexed-FK findings require query/workload review and migration-source reconciliation before any schema change. The missing migration must not be guessed as the fix.

## Next steps

1. Recover the original SQL from retained Git objects, PR artifacts, repository backups, or trusted CI artifacts.
2. Verify original commit, file path, blob SHA, SHA-256, SQL contents, dependency order, and applied state.
3. Rehearse the exact migration chain on disposable PostgreSQL.
4. Compare indexes, constraints, policies, triggers, and functions against the staging schema.
5. Review all five SECURITY DEFINER functions and their EXECUTE grants.
6. Triage the 26 unindexed foreign keys and 49 unused indexes using real query plans and workload evidence.
7. Obtain independent approval before any shared staging schema mutation.

No migration was applied and no production database was changed during this audit.


## Superseding result — 20 November 2026

The source for applied version `20261022140302` has now been recovered from the live staging migration-history statements and verified against the stored SQL. Current staging has 52 source files and 48 applied versions, with four pending migrations, zero DB versions missing source, and zero duplicate source versions. The old 46/45 count and missing-source status above are the 17 November historical snapshot. See `docs/audit/FNB_OS_IMPLEMENTATION_DELTA_20261120.md`.
