# Migration Source Recovery — 20261022140302

**Status:** source recovery candidate; not applied to staging or production.

## Source of truth

The migration history row was read from the actual staging database:

`supabase_migrations.schema_migrations.version = 20261022140302`  
`name = add_missing_fk_supporting_indexes`

The `statements` field contains the exact nine `CREATE INDEX IF NOT EXISTS` statements reproduced in:

`supabase/migrations/20261022140302_add_missing_fk_supporting_indexes.sql`

This recovers the original applied SQL from the database migration history rather than recreating it from memory or inferred schema.

## Scope

The nine indexes support foreign-key lookups for:
- branch checklist run completer and starter;
- stock-count item inventory references;
- stock-count counter and poster;
- stock-transfer item inventory references;
- stock-transfer receiver, requester and shipper.

The statements are idempotent and do not change row data or RLS/policies.

## Validation and rollout

- The source file is restored on an isolated branch only.
- CI disposable migration replay must apply the full migration set from zero.
- Compare the recovered file statement-for-statement with the staging migration-history row before considering parity closed.
- Because this version is already applied on staging, do not attempt to reapply it manually or change staging migration history.
- No staging DDL, production DDL, backup, or data mutation was performed by source recovery.

## Rollback

If a future migration review identifies a performance regression, rollback of these indexes is limited to dropping the nine indexes created here:
`DROP INDEX IF EXISTS public.branch_operation_checklist_runs_completed_by_idx;`
`DROP INDEX IF EXISTS public.branch_operation_checklist_runs_started_by_idx;`
`DROP INDEX IF EXISTS public.stock_count_items_inventory_item_id_idx;`
`DROP INDEX IF EXISTS public.stock_counts_counted_by_idx;`
`DROP INDEX IF EXISTS public.stock_counts_posted_by_idx;`
`DROP INDEX IF EXISTS public.stock_transfer_items_inventory_item_id_idx;`
`DROP INDEX IF EXISTS public.stock_transfers_received_by_idx;`
`DROP INDEX IF EXISTS public.stock_transfers_requested_by_idx;`
`DROP INDEX IF EXISTS public.stock_transfers_shipped_by_idx;`

Do not execute this rollback without query-plan evidence and explicit approval.
