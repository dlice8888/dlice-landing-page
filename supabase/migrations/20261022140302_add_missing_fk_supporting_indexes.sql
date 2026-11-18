CREATE INDEX IF NOT EXISTS branch_operation_checklist_runs_completed_by_idx
  ON public.branch_operation_checklist_runs (completed_by);
CREATE INDEX IF NOT EXISTS branch_operation_checklist_runs_started_by_idx
  ON public.branch_operation_checklist_runs (started_by);
CREATE INDEX IF NOT EXISTS stock_count_items_inventory_item_id_idx
  ON public.stock_count_items (inventory_item_id);
CREATE INDEX IF NOT EXISTS stock_counts_counted_by_idx
  ON public.stock_counts (counted_by);
CREATE INDEX IF NOT EXISTS stock_counts_posted_by_idx
  ON public.stock_counts (posted_by);
CREATE INDEX IF NOT EXISTS stock_transfer_items_inventory_item_id_idx
  ON public.stock_transfer_items (inventory_item_id);
CREATE INDEX IF NOT EXISTS stock_transfers_received_by_idx
  ON public.stock_transfers (received_by);
CREATE INDEX IF NOT EXISTS stock_transfers_requested_by_idx
  ON public.stock_transfers (requested_by);
CREATE INDEX IF NOT EXISTS stock_transfers_shipped_by_idx
  ON public.stock_transfers (shipped_by);
