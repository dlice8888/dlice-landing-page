-- Add non-redundant leading-column indexes for the 26 FK warnings reported by
-- Supabase Performance Advisor on 2026-11-21.
-- Two single-column tenant_id FKs are covered by their corresponding
-- (tenant_id, branch_id) composite index, so 24 indexes cover 26 constraints.
-- This migration is intended for reviewed branch/disposable replay first.
CREATE INDEX IF NOT EXISTS idx_backup_restore_runs_started_by ON public.backup_restore_runs (started_by);
CREATE INDEX IF NOT EXISTS idx_backup_restore_runs_tenant_id ON public.backup_restore_runs (tenant_id);
CREATE INDEX IF NOT EXISTS idx_branch_inventory_branch_warehouse_fk ON public.branch_inventory (branch_id, warehouse_id);
CREATE INDEX IF NOT EXISTS idx_branch_settings_updated_by ON public.branch_settings (updated_by);
CREATE INDEX IF NOT EXISTS idx_integration_connections_created_by ON public.integration_connections (created_by);
CREATE INDEX IF NOT EXISTS idx_integration_outbox_branch_id ON public.integration_outbox (branch_id);
CREATE INDEX IF NOT EXISTS idx_integration_outbox_connection_id ON public.integration_outbox (connection_id);
CREATE INDEX IF NOT EXISTS idx_integration_outbox_tenant_branch ON public.integration_outbox (tenant_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_inventory_waste_events_created_by ON public.inventory_waste_events (created_by);
CREATE INDEX IF NOT EXISTS idx_inventory_waste_events_inventory_item_id ON public.inventory_waste_events (inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_waste_events_tenant_branch ON public.inventory_waste_events (tenant_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_ticket_items_order_item_id ON public.kitchen_ticket_items (order_item_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_ticket_items_pos_sale_item_id ON public.kitchen_ticket_items (pos_sale_item_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_ticket_items_product_id ON public.kitchen_ticket_items (product_id);
CREATE INDEX IF NOT EXISTS idx_offline_sync_receipts_actor_user_id ON public.offline_sync_receipts (actor_user_id);
CREATE INDEX IF NOT EXISTS idx_pos_idempotency_requests_actor_user_id ON public.pos_idempotency_requests (actor_user_id);
CREATE INDEX IF NOT EXISTS idx_recipe_substitutions_approved_by ON public.recipe_substitutions (approved_by);
CREATE INDEX IF NOT EXISTS idx_recipe_substitutions_substitute_inventory_item_id ON public.recipe_substitutions (substitute_inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_shift_handover_records_incoming_user_id ON public.shift_handover_records (incoming_user_id);
CREATE INDEX IF NOT EXISTS idx_shift_handover_records_outgoing_user_id ON public.shift_handover_records (outgoing_user_id);
CREATE INDEX IF NOT EXISTS idx_shift_handover_records_tenant_branch ON public.shift_handover_records (tenant_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_tenant_invites_accepted_by ON public.tenant_invites (accepted_by);
CREATE INDEX IF NOT EXISTS idx_tenant_invites_invited_by ON public.tenant_invites (invited_by);
CREATE INDEX IF NOT EXISTS idx_warehouses_tenant_branch ON public.warehouses (tenant_id, branch_id);
