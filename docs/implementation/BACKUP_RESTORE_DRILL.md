# Disposable backup and restore rehearsal

## Purpose
Exercise a PostgreSQL 17 custom-format dump, restore into a fresh database, checksum parity, RLS restoration, and Tenant A/B read isolation using a disposable GitHub-hosted runner. The workflow has no Supabase project URL, credentials, production resources, or paid database branch.

## Scenario
1. Create an isolated source database with two tenant fixtures and 151 branches (150 for Tenant A and one for Tenant B).
2. Create one committed operational event per branch, then calculate the snapshot row count and deterministic checksum.
3. Create a custom-format pg_dump.
4. Add one intentional post-snapshot event to the source database.
5. Restore the dump into a fresh target database using pg_restore.
6. Verify exact pre-snapshot row count and checksum, RLS enabled on both tables, Tenant A sees only its 150 branches/events, Tenant B sees only its own branch/event, and cross-tenant reads return zero rows.
7. Record backup size and elapsed local restore drill time.

## Acceptance
- All rows committed before the snapshot are present after restore (zero pre-snapshot loss).
- The intentionally post-snapshot row is absent from the restored snapshot.
- Schema constraints, composite tenant/branch FK, index, and RLS policies survive restore.
- Tenant A/B isolation holds after restore.
- Workflow exits non-zero on any mismatch and always destroys both temporary databases.

## Limitations
This is a local disposable PostgreSQL restore rehearsal. It is not evidence of Supabase managed backup availability, point-in-time recovery, platform RPO/RTO, Storage backup, Auth backup, or a production restore. Those remain separate acceptance requirements and must not be claimed from this workflow.
