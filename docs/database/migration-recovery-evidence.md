# Migration source recovery evidence

**Audit date:** 2026-11-17  
**Supabase target:** staging project `higoadrzxnhzbbwhdbmh` only  
**Migration:** `20261022140302_add_missing_fk_supporting_indexes`

## Database evidence

Read-only Supabase migration history returned the following row:

- Version: `20261022140302`
- Name: `add_missing_fk_supporting_indexes`

The full staging migration history returned 46 records, with the latest version `20261027140145`.

## Repository source checks

The following checks were performed:

- Fetch expected source path from `staging`: HTTP 404.
- Fetch expected source path from `main`: HTTP 404.
- GitHub code search for `20261022140302` in `dlice8888/dlice-landing-page`: zero results.

No original commit SHA, branch, PR, blob SHA, or content checksum has been established.

## Status

**BLOCKED — source migration not recovered.**

The database tracking row is not a substitute for the original SQL source. Do not generate replacement SQL from current schema, do not infer index definitions, and do not apply or replay a guessed migration.

## Required recovery path

1. Search all refs and Git history, including deleted blobs and historical PR heads.
2. Check repository backups and retained CI artifacts.
3. Compare any candidate source against the database's actual index definitions and migration record.
4. Record original commit, blob SHA, SHA-256 content hash, dependency order, and whether already applied.
5. Only after source integrity is proven, rehearse the complete migration chain on a disposable database.
6. Obtain independent review before any shared staging migration action.

No database schema, migration history, or production resource was changed during this audit.


## Recovery completed — 20 November 2026

The exact migration source for version `20261022140302` is now present in staging at `supabase/migrations/20261022140302_add_missing_fk_supporting_indexes.sql`. Its concatenated SQL statements match the live `supabase_migrations.schema_migrations.statements` value exactly after trimming surrounding whitespace. It was not reapplied; its version is already recorded as applied. Current full migration parity is 52 files / 48 applied / 4 pending / 0 missing source / 0 duplicate. See `docs/audit/FNB_OS_IMPLEMENTATION_DELTA_20261120.md`.
