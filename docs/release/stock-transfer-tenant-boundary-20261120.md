# Stock transfer tenant boundary — rollout and review note

Date: 2026-11-20
Target branch: `staging`
Migration: `20261120130000_enforce_same_tenant_stock_transfers.sql`

## Policy source
The D’Lice PRD defines one tenant per organization (the 150 D’Lice branches are not 150 tenants), stock transfers between warehouses/branches, and the lifecycle:

`Draft → Approved → Picked → Shipped → Received → Reconciled`

The PRD requires tenant isolation and cross-tenant denial. It does not authorize a Platform Owner/HQ exception for cross-tenant stock transfers. This migration and the API guard apply the same-tenant invariant to every actor.

## Change summary
- Edge Function `erp-create-stock-transfer` validates that source and destination branches belong to the same tenant before invoking the service-role RPC.
- Edge Function `erp-transition-stock-transfer` revalidates tenant ownership for every transition; Platform Owner does not bypass this boundary.
- Database trigger `trg_stock_transfer_same_tenant` rejects cross-tenant insert or branch reassignment in `stock_transfers`.
- A second trigger blocks changing a branch's `tenant_id` after it has stock-transfer history, preventing later branch re-parenting from invalidating the transfer's tenant boundary.
- Trigger function EXECUTE is revoked from `PUBLIC`, `anon`, and `authenticated`; it is invoked only by the table trigger.
- No table schema, inventory ledger, or business data is rewritten by this migration.

## Migration ordering
Current Supabase staging migration history ends at `20261119182606`. Current staging source already contains:
1. `20261120100000_atomic_owner_and_tenant_bootstrap.sql`
2. `20261120110000_command_center_summary.sql`
3. `20261120120000_atomic_branch_checklist_audit.sql`

This migration uses forward-only version `20261120130000`, after those three source migrations. Do not backdate, reorder, or rewrite applied migration history. Do not apply this migration until the three preceding migrations are reviewed and the complete disposable migration replay passes.

## Pre-application staging evidence
Read-only query on 2026-11-20:
- Existing stock transfer rows: 0
- Existing cross-tenant stock transfer rows: 0
- Existing same-tenant transfer rows: 0
- Existing same-tenant stock-transfer trigger: absent

No data backfill is required based on the current inventory. Re-run this query immediately before application.

## Validation evidence
- Dedicated disposable PostgreSQL regression covers same-tenant insert success, cross-tenant insert rejection, cross-tenant source/destination update rejection, no partial writes, and direct client EXECUTE denial.
- API contract tests require same-tenant validation before the RPC on create and every transition, including Platform Owner.
- Full disposable Supabase migration replay must pass on the exact PR head.
- The existing platform-owner cross-tenant exception contract was updated to match the PRD; do not reintroduce that exception.

## Release gates
- Keep `TENANT_ISOLATION_RELEASED=false`.
- Keep `PUBLIC_TENANT_ROUTING_RELEASED=false`.
- P01–P09 must execute against two real, distinct Auth users with active tenant memberships and branch assignments; no BLOCKED or SKIPPED probes.
- POS/KDS/Stock and Procurement E2E, regression suite, backup/restore, and independent security review remain required.
- No production migration, Edge Function deployment, Vercel promotion, or alias change is authorized by this PR.

## Rollback / incident handling
This is an additive trigger and trigger function. Do not use a destructive rollback automatically. If the guard causes an incident, stop the stock-transfer action at the Edge Function release gate, preserve the migration history, collect the failing transaction evidence, and prepare a separately reviewed forward-only correction. Do not drop the trigger or permit cross-tenant writes as an emergency workaround.

## Acceptance
Merge to staging only after all PR checks pass, an independent reviewer approves, the PRD policy is accepted, and the P01–P09 tenant runtime gate is unblocked. Applying the migration to shared staging is a separate explicit step after merge and review.
