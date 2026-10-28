# Staging-to-production schema parity plan

Status: prepared, not executed. Production remains unchanged.

## Observed baseline (2026-10-28)
- Staging migration history contains 42 entries through 2026-10-27.
- Production migration history contains 4 entries through 2026-10-17.
- Staging has tenant/branch ERP tables and active dlice-orders function version 60.
- Production has the older ordering schema and dlice-orders function version 3.
- This is migration drift, not permission to copy staging data or rewrite migration history.

## Required release sequence
1. Freeze a release candidate from reviewed main; record commit SHA and migration checksums.
2. Export schema-only snapshots of staging and production in a controlled environment. Never export production rows or secrets into staging.
3. Produce a migration-by-migration dependency map from production history to the reviewed release candidate. Do not mark old migrations as applied merely to silence drift.
4. Rehearse every missing migration in an ephemeral PostgreSQL database initialized from the actual production schema snapshot. Run migration replay and regression suites.
5. Review data migrations separately. Each must be idempotent where possible, bounded, and have a rollback or forward-recovery plan. Do not assume DDL rollback is sufficient.
6. Apply only approved additive/compatible migrations to staging, after backup and explicit change record. Re-run auth, RLS, CORS, POS/KDS, procurement, stock ledger, finance and tenant-negative E2E tests.
7. Verify application compatibility for the old and new schema before deploying application code.
8. Schedule production promotion with owner approval, a verified backup/restore point, maintenance/rollback plan, and post-deploy smoke tests. This document does not authorize production changes.

## Release gates
- All migrations replay from a clean database with no skipped dependency.
- All tenant-boundary tests pass through JWT/PostgREST/RPC/Edge Function, not just direct SQL.
- RLS and function grants reviewed; no service-role bypass is reachable from untrusted input.
- KDS/POS and procurement E2E reconcile order/payment, tickets, stock ledger, receipts and audit events.
- Production schema diff contains only reviewed expected changes.
- No secret values or customer/production rows are included in CI artifacts.

## Current blockers
- Tenant-scoped schema and policies are not consistent across all domain tables.
- The Edge Function TENANT_ISOLATION_RELEASED flag remains false and many legacy admin actions remain uncertified.
- No authorized second-tenant user pair has completed runtime negative tests.
- Production migration history has not been reconciled with the full staging schema.
