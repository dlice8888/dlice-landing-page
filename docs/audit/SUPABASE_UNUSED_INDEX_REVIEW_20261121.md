# Supabase unused secondary-index review — 2026-11-21

## Executive result

The Supabase Performance Advisor reports **49 unused indexes**. A fresh read-only catalog query confirms 49 public-schema indexes with zero scans since statistics reset on 2026-10-02, all of which are non-unique secondary indexes. They span 30 tables and occupy 488 kB combined.

This does **not** mean the indexes are safe to drop. The staging dataset is extremely small (7 orders, 6 payment records, 6 POS sales, 0 purchase orders, 0 production batches, 0 settlements and 0 journal entries). Zero scans under this workload are not evidence of redundancy at 150-branch scale.

Primary-key and unique/constraint indexes are excluded from the 49 Advisor findings; they must not be dropped as ordinary unused indexes.

## Required decision

**No DROP INDEX is proposed or executed in this audit.** Retain the 49 until:
1. Query workload is captured with pg_stat_statements and realistic branch-level traffic.
2. Each index is checked against foreign-key lookup paths, RLS policies, RPC filters, dashboard/report queries and partial-index predicates.
3. EXPLAIN (ANALYZE, BUFFERS) is collected before and after any candidate removal on a disposable database with representative data.
4. A 150-branch load test confirms no regression in p95 latency, write amplification, lock time or FK cascade performance.
5. Any removal is isolated in a reviewed migration with rollback/restore evidence.

## Inventory

| Table | Index | Size | Definition |
|---|---|---:|---|
| backup_restore_runs | backup_restore_runs_type_created_idx | 8192 bytes | `CREATE INDEX backup_restore_runs_type_created_idx ON public.backup_restore_runs USING btree (run_type, created_at DESC)` |
| branch_inventory | branch_inventory_inventory_item_id_idx | 16 kB | `CREATE INDEX branch_inventory_inventory_item_id_idx ON public.branch_inventory USING btree (inventory_item_id)` |
| branch_inventory | branch_inventory_warehouse_idx | 16 kB | `CREATE INDEX branch_inventory_warehouse_idx ON public.branch_inventory USING btree (warehouse_id, inventory_item_id)` |
| branch_product_capacity | branch_product_capacity_date_idx | 16 kB | `CREATE INDEX branch_product_capacity_date_idx ON public.branch_product_capacity USING btree (service_date, branch_id)` |
| branch_product_capacity | branch_product_capacity_product_id_idx | 16 kB | `CREATE INDEX branch_product_capacity_product_id_idx ON public.branch_product_capacity USING btree (product_id)` |
| cash_reconciliations | cash_reconciliations_shift_id_idx | 8192 bytes | `CREATE INDEX cash_reconciliations_shift_id_idx ON public.cash_reconciliations USING btree (shift_id)` |
| finance_journal_entries | finance_journal_date_branch_idx | 8192 bytes | `CREATE INDEX finance_journal_date_branch_idx ON public.finance_journal_entries USING btree (entry_date, branch_id, status)` |
| finance_journal_entries | finance_journal_entries_branch_id_idx | 8192 bytes | `CREATE INDEX finance_journal_entries_branch_id_idx ON public.finance_journal_entries USING btree (branch_id)` |
| finance_journal_entries | finance_journal_entries_fiscal_period_id_idx | 8192 bytes | `CREATE INDEX finance_journal_entries_fiscal_period_id_idx ON public.finance_journal_entries USING btree (fiscal_period_id)` |
| finance_journal_entries | finance_journal_entries_reverses_entry_id_idx | 8192 bytes | `CREATE INDEX finance_journal_entries_reverses_entry_id_idx ON public.finance_journal_entries USING btree (reverses_entry_id)` |
| integration_outbox | integration_outbox_retry_idx | 8192 bytes | `CREATE INDEX integration_outbox_retry_idx ON public.integration_outbox USING btree (status, next_attempt_at) WHERE (status = ANY (ARRAY['pending'::text, 'retry'::text]))` |
| inventory_waste_events | inventory_waste_branch_created_idx | 8192 bytes | `CREATE INDEX inventory_waste_branch_created_idx ON public.inventory_waste_events USING btree (branch_id, created_at DESC)` |
| offline_sync_receipts | offline_sync_branch_synced_idx | 16 kB | `CREATE INDEX offline_sync_branch_synced_idx ON public.offline_sync_receipts USING btree (branch_id, synced_at DESC)` |
| order_items | order_items_product_id_idx | 16 kB | `CREATE INDEX order_items_product_id_idx ON public.order_items USING btree (product_id)` |
| order_reservations | order_reservations_branch_date_status_idx | 16 kB | `CREATE INDEX order_reservations_branch_date_status_idx ON public.order_reservations USING btree (branch_id, service_date, status)` |
| order_stock_consumptions | order_stock_consumptions_branch_idx | 8192 bytes | `CREATE INDEX order_stock_consumptions_branch_idx ON public.order_stock_consumptions USING btree (branch_id, consumed_at DESC)` |
| orders | orders_branch_fulfillment_date_idx | 16 kB | `CREATE INDEX orders_branch_fulfillment_date_idx ON public.orders USING btree (branch_id, requested_date, fulfillment_status)` |
| pos_idempotency_requests | pos_idempotency_created_idx | 16 kB | `CREATE INDEX pos_idempotency_created_idx ON public.pos_idempotency_requests USING btree (created_at)` |
| pos_sales | pos_sales_shift_idx | 16 kB | `CREATE INDEX pos_sales_shift_idx ON public.pos_sales USING btree (shift_id, created_at)` |
| production_batches | production_batches_recipe_id_idx | 8192 bytes | `CREATE INDEX production_batches_recipe_id_idx ON public.production_batches USING btree (recipe_id)` |
| production_consumptions | production_consumptions_inventory_item_id_idx | 8192 bytes | `CREATE INDEX production_consumptions_inventory_item_id_idx ON public.production_consumptions USING btree (inventory_item_id)` |
| production_consumptions | production_consumptions_stock_movement_id_idx | 8192 bytes | `CREATE INDEX production_consumptions_stock_movement_id_idx ON public.production_consumptions USING btree (stock_movement_id)` |
| purchase_order_items | purchase_order_items_inventory_item_id_idx | 8192 bytes | `CREATE INDEX purchase_order_items_inventory_item_id_idx ON public.purchase_order_items USING btree (inventory_item_id)` |
| purchase_order_items | purchase_order_items_purchase_order_id_idx | 8192 bytes | `CREATE INDEX purchase_order_items_purchase_order_id_idx ON public.purchase_order_items USING btree (purchase_order_id)` |
| purchase_orders | purchase_orders_supplier_id_idx | 8192 bytes | `CREATE INDEX purchase_orders_supplier_id_idx ON public.purchase_orders USING btree (supplier_id)` |
| purchase_receipt_items | purchase_receipt_items_inventory_item_id_idx | 8192 bytes | `CREATE INDEX purchase_receipt_items_inventory_item_id_idx ON public.purchase_receipt_items USING btree (inventory_item_id)` |
| purchase_receipt_items | purchase_receipt_items_purchase_order_item_id_idx | 8192 bytes | `CREATE INDEX purchase_receipt_items_purchase_order_item_id_idx ON public.purchase_receipt_items USING btree (purchase_order_item_id)` |
| purchase_receipt_items | purchase_receipt_items_receipt_id_idx | 8192 bytes | `CREATE INDEX purchase_receipt_items_receipt_id_idx ON public.purchase_receipt_items USING btree (receipt_id)` |
| purchase_receipts | purchase_receipts_branch_id_idx | 8192 bytes | `CREATE INDEX purchase_receipts_branch_id_idx ON public.purchase_receipts USING btree (branch_id)` |
| purchase_receipts | purchase_receipts_po_idx | 8192 bytes | `CREATE INDEX purchase_receipts_po_idx ON public.purchase_receipts USING btree (purchase_order_id, received_at DESC)` |
| purchase_requisition_items | purchase_requisition_items_inventory_idx | 8192 bytes | `CREATE INDEX purchase_requisition_items_inventory_idx ON public.purchase_requisition_items USING btree (inventory_item_id)` |
| purchase_requisition_items | purchase_requisition_items_requisition_idx | 8192 bytes | `CREATE INDEX purchase_requisition_items_requisition_idx ON public.purchase_requisition_items USING btree (requisition_id)` |
| purchase_requisitions | purchase_requisitions_branch_created_idx | 8192 bytes | `CREATE INDEX purchase_requisitions_branch_created_idx ON public.purchase_requisitions USING btree (branch_id, created_at DESC)` |
| purchase_requisitions | purchase_requisitions_converted_po_idx | 8192 bytes | `CREATE INDEX purchase_requisitions_converted_po_idx ON public.purchase_requisitions USING btree (converted_purchase_order_id) WHERE (converted_purchase_order_id IS NOT NULL)` |
| purchase_requisitions | purchase_requisitions_status_created_idx | 8192 bytes | `CREATE INDEX purchase_requisitions_status_created_idx ON public.purchase_requisitions USING btree (status, created_at DESC)` |
| recipe_ingredients | recipe_ingredients_inventory_item_id_idx | 16 kB | `CREATE INDEX recipe_ingredients_inventory_item_id_idx ON public.recipe_ingredients USING btree (inventory_item_id)` |
| recipe_substitutions | recipe_substitutions_ingredient_active_idx | 8192 bytes | `CREATE INDEX recipe_substitutions_ingredient_active_idx ON public.recipe_substitutions USING btree (recipe_ingredient_id, is_active)` |
| refund_records | refund_records_branch_id_idx | 8192 bytes | `CREATE INDEX refund_records_branch_id_idx ON public.refund_records USING btree (branch_id)` |
| refund_records | refund_records_order_id_idx | 8192 bytes | `CREATE INDEX refund_records_order_id_idx ON public.refund_records USING btree (order_id)` |
| refund_records | refund_records_payment_record_id_idx | 8192 bytes | `CREATE INDEX refund_records_payment_record_id_idx ON public.refund_records USING btree (payment_record_id)` |
| refund_records | refund_records_pos_sale_id_idx | 8192 bytes | `CREATE INDEX refund_records_pos_sale_id_idx ON public.refund_records USING btree (pos_sale_id)` |
| refund_records | refund_records_status_date_idx | 8192 bytes | `CREATE INDEX refund_records_status_date_idx ON public.refund_records USING btree (status, requested_at DESC)` |
| shift_handover_records | shift_handover_branch_created_idx | 8192 bytes | `CREATE INDEX shift_handover_branch_created_idx ON public.shift_handover_records USING btree (branch_id, created_at DESC)` |
| stock_count_items | stock_count_items_count_idx | 8192 bytes | `CREATE INDEX stock_count_items_count_idx ON public.stock_count_items USING btree (stock_count_id)` |
| stock_count_items | stock_count_items_inventory_item_id_idx | 8192 bytes | `CREATE INDEX stock_count_items_inventory_item_id_idx ON public.stock_count_items USING btree (inventory_item_id)` |
| stock_movements | stock_movements_item_created_idx | 16 kB | `CREATE INDEX stock_movements_item_created_idx ON public.stock_movements USING btree (inventory_item_id, created_at DESC)` |
| stock_transfer_items | stock_transfer_items_inventory_item_id_idx | 8192 bytes | `CREATE INDEX stock_transfer_items_inventory_item_id_idx ON public.stock_transfer_items USING btree (inventory_item_id)` |
| stock_transfer_items | stock_transfer_items_transfer_idx | 8192 bytes | `CREATE INDEX stock_transfer_items_transfer_idx ON public.stock_transfer_items USING btree (transfer_id)` |
| tenant_invites | tenant_invites_tenant_status_idx | 8192 bytes | `CREATE INDEX tenant_invites_tenant_status_idx ON public.tenant_invites USING btree (tenant_id, status, expires_at)` |

## Interpretation

- The 49 entries are zero-scan, non-unique secondary indexes. Their zero-scan counter is cumulative only since the statistics reset date above.
- Several may support infrequent but critical operations such as stock transfer, refunds, procurement, backup/restore, finance close, tenant invitations, or retry queues.
- Some may become redundant after PR #122's proposed 24 FK covering indexes are applied. That overlap must be checked on the final schema before any drop.
- Adding 24 FK indexes increases write/storage overhead slightly but addresses 26 missing FK access paths. The two warnings not requiring new indexes are covered by existing composite/leading-column indexes or must be verified in PR #122's migration tests.

## Next work

1. Re-run Advisor and catalog inventory after PR #122's migration is applied to disposable staging.
2. Capture query plans for each of the 49 indexes under representative workloads.
3. Create a candidate list only for non-unique indexes that are both redundant and not required by FK, RLS, or critical query paths.
4. Benchmark candidate drops on a disposable branch, not shared staging.
5. Only then prepare a separate reviewed cleanup migration.