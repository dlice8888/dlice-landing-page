# Supabase staging performance remediation — 2026-11-21

## Scope and evidence

Project: `higoadrzxnhzbbwhdbmh` (staging). Supabase Performance Advisor observed:
- 26 foreign-key constraints without a covering index.
- 49 indexes with zero recorded scans.
- Advisor observation timestamp: 2026-11-21T05:15:00.261Z.
- PostgreSQL statistics reset: 2026-10-02 18:01:15 UTC (from `pg_stat_database.stats_reset`).

The linter's 26 findings are the source of truth for this remediation. An independent catalog query initially returned 31 because its comparison was stricter than the Advisor's covering-index rule; those five extra candidates are not included without reconciliation.

## FK remediation

26 FK warnings can be covered by 24 non-redundant indexes. The two standalone `tenant_id` constraints on `inventory_waste_events` and `shift_handover_records` are covered by their composite `(tenant_id, branch_id)` indexes, avoiding duplicate prefix indexes.

| Table | Indexed columns | Index |
|---|---|---|
| `backup_restore_runs` | `started_by` | `idx_backup_restore_runs_started_by` |
| `backup_restore_runs` | `tenant_id` | `idx_backup_restore_runs_tenant_id` |
| `branch_inventory` | `branch_id, warehouse_id` | `idx_branch_inventory_branch_warehouse_fk` |
| `branch_settings` | `updated_by` | `idx_branch_settings_updated_by` |
| `integration_connections` | `created_by` | `idx_integration_connections_created_by` |
| `integration_outbox` | `branch_id` | `idx_integration_outbox_branch_id` |
| `integration_outbox` | `connection_id` | `idx_integration_outbox_connection_id` |
| `integration_outbox` | `tenant_id, branch_id` | `idx_integration_outbox_tenant_branch` |
| `inventory_waste_events` | `created_by` | `idx_inventory_waste_events_created_by` |
| `inventory_waste_events` | `inventory_item_id` | `idx_inventory_waste_events_inventory_item_id` |
| `inventory_waste_events` | `tenant_id, branch_id` | `idx_inventory_waste_events_tenant_branch` |
| `kitchen_ticket_items` | `order_item_id` | `idx_kitchen_ticket_items_order_item_id` |
| `kitchen_ticket_items` | `pos_sale_item_id` | `idx_kitchen_ticket_items_pos_sale_item_id` |
| `kitchen_ticket_items` | `product_id` | `idx_kitchen_ticket_items_product_id` |
| `offline_sync_receipts` | `actor_user_id` | `idx_offline_sync_receipts_actor_user_id` |
| `pos_idempotency_requests` | `actor_user_id` | `idx_pos_idempotency_requests_actor_user_id` |
| `recipe_substitutions` | `approved_by` | `idx_recipe_substitutions_approved_by` |
| `recipe_substitutions` | `substitute_inventory_item_id` | `idx_recipe_substitutions_substitute_inventory_item_id` |
| `shift_handover_records` | `incoming_user_id` | `idx_shift_handover_records_incoming_user_id` |
| `shift_handover_records` | `outgoing_user_id` | `idx_shift_handover_records_outgoing_user_id` |
| `shift_handover_records` | `tenant_id, branch_id` | `idx_shift_handover_records_tenant_branch` |
| `tenant_invites` | `accepted_by` | `idx_tenant_invites_accepted_by` |
| `tenant_invites` | `invited_by` | `idx_tenant_invites_invited_by` |
| `warehouses` | `tenant_id, branch_id` | `idx_warehouses_tenant_branch` |

Migration: `supabase/migrations/20261121120000_add_fk_covering_indexes.sql`.
Test: `supabase/tests/foreign_key_covering_indexes.test.sql` (24 pgTAP assertions).

This PR does not apply the migration to shared staging or production. Disposable migration replay and pgTAP must pass first. After an authorized staging rollout, rerun Performance Advisor and confirm the FK finding count reaches zero.

## 49 zero-scan indexes — retain pending workload evidence

A zero `idx_scan` count is not proof an index is unnecessary. The staging workload has limited business data and the statistics window is approximately 50 days. Many listed indexes support workflows not yet exercised (orders, POS, stock, procurement, production, finance, refunds, offline replay, tenant invites and integrations). Dropping them now could regress features as soon as those workflows become active.

No unused index is dropped by this change. The complete current Advisor candidate list is:

1. Index \`orders_branch_fulfillment_date_idx\` on table \`public.orders\` has not been used
2. Index \`order_reservations_branch_date_status_idx\` on table \`public.order_reservations\` has not been used
3. Index \`stock_movements_item_created_idx\` on table \`public.stock_movements\` has not been used
4. Index \`pos_sales_shift_idx\` on table \`public.pos_sales\` has not been used
5. Index \`branch_product_capacity_date_idx\` on table \`public.branch_product_capacity\` has not been used
6. Index \`purchase_receipts_po_idx\` on table \`public.purchase_receipts\` has not been used
7. Index \`branch_inventory_inventory_item_id_idx\` on table \`public.branch_inventory\` has not been used
8. Index \`order_items_product_id_idx\` on table \`public.order_items\` has not been used
9. Index \`purchase_order_items_inventory_item_id_idx\` on table \`public.purchase_order_items\` has not been used
10. Index \`purchase_order_items_purchase_order_id_idx\` on table \`public.purchase_order_items\` has not been used
11. Index \`purchase_orders_supplier_id_idx\` on table \`public.purchase_orders\` has not been used
12. Index \`finance_journal_date_branch_idx\` on table \`public.finance_journal_entries\` has not been used
13. Index \`refund_records_status_date_idx\` on table \`public.refund_records\` has not been used
14. Index \`branch_product_capacity_product_id_idx\` on table \`public.branch_product_capacity\` has not been used
15. Index \`cash_reconciliations_shift_id_idx\` on table \`public.cash_reconciliations\` has not been used
16. Index \`finance_journal_entries_branch_id_idx\` on table \`public.finance_journal_entries\` has not been used
17. Index \`finance_journal_entries_fiscal_period_id_idx\` on table \`public.finance_journal_entries\` has not been used
18. Index \`finance_journal_entries_reverses_entry_id_idx\` on table \`public.finance_journal_entries\` has not been used
19. Index \`production_batches_recipe_id_idx\` on table \`public.production_batches\` has not been used
20. Index \`production_consumptions_inventory_item_id_idx\` on table \`public.production_consumptions\` has not been used
21. Index \`production_consumptions_stock_movement_id_idx\` on table \`public.production_consumptions\` has not been used
22. Index \`purchase_receipt_items_inventory_item_id_idx\` on table \`public.purchase_receipt_items\` has not been used
23. Index \`purchase_receipt_items_purchase_order_item_id_idx\` on table \`public.purchase_receipt_items\` has not been used
24. Index \`purchase_receipt_items_receipt_id_idx\` on table \`public.purchase_receipt_items\` has not been used
25. Index \`purchase_receipts_branch_id_idx\` on table \`public.purchase_receipts\` has not been used
26. Index \`recipe_ingredients_inventory_item_id_idx\` on table \`public.recipe_ingredients\` has not been used
27. Index \`refund_records_branch_id_idx\` on table \`public.refund_records\` has not been used
28. Index \`refund_records_order_id_idx\` on table \`public.refund_records\` has not been used
29. Index \`refund_records_payment_record_id_idx\` on table \`public.refund_records\` has not been used
30. Index \`refund_records_pos_sale_id_idx\` on table \`public.refund_records\` has not been used
31. Index \`stock_transfer_items_transfer_idx\` on table \`public.stock_transfer_items\` has not been used
32. Index \`stock_count_items_inventory_item_id_idx\` on table \`public.stock_count_items\` has not been used
33. Index \`stock_transfer_items_inventory_item_id_idx\` on table \`public.stock_transfer_items\` has not been used
34. Index \`stock_count_items_count_idx\` on table \`public.stock_count_items\` has not been used
35. Index \`purchase_requisitions_branch_created_idx\` on table \`public.purchase_requisitions\` has not been used
36. Index \`purchase_requisitions_status_created_idx\` on table \`public.purchase_requisitions\` has not been used
37. Index \`purchase_requisition_items_requisition_idx\` on table \`public.purchase_requisition_items\` has not been used
38. Index \`purchase_requisition_items_inventory_idx\` on table \`public.purchase_requisition_items\` has not been used
39. Index \`purchase_requisitions_converted_po_idx\` on table \`public.purchase_requisitions\` has not been used
40. Index \`recipe_substitutions_ingredient_active_idx\` on table \`public.recipe_substitutions\` has not been used
41. Index \`pos_idempotency_created_idx\` on table \`public.pos_idempotency_requests\` has not been used
42. Index \`offline_sync_branch_synced_idx\` on table \`public.offline_sync_receipts\` has not been used
43. Index \`order_stock_consumptions_branch_idx\` on table \`public.order_stock_consumptions\` has not been used
44. Index \`tenant_invites_tenant_status_idx\` on table \`public.tenant_invites\` has not been used
45. Index \`branch_inventory_warehouse_idx\` on table \`public.branch_inventory\` has not been used
46. Index \`shift_handover_branch_created_idx\` on table \`public.shift_handover_records\` has not been used
47. Index \`inventory_waste_branch_created_idx\` on table \`public.inventory_waste_events\` has not been used
48. Index \`integration_outbox_retry_idx\` on table \`public.integration_outbox\` has not been used
49. Index \`backup_restore_runs_type_created_idx\` on table \`public.backup_restore_runs\` has not been used

### Required evidence before any DROP INDEX proposal

1. Map each candidate to actual application SQL/RPC/RLS predicates and FK/unique constraints.
2. Inspect duplicate/overlapping indexes using ordered key columns, predicates, included columns and operator classes.
3. Capture representative `EXPLAIN (ANALYZE, BUFFERS)` for real workflows at realistic data volumes.
4. Run representative staging load tests covering POS, orders, stock, procurement, finance, refunds, offline sync and integration outbox.
5. Compare query latency, write amplification, WAL, storage and lock impact with/without candidate indexes on a disposable database.
6. Keep indexes used by FK enforcement, uniqueness, constraints, RLS access paths or planned-but-not-yet-live features.
7. Only then propose individual drops in a separate reversible/rollback-aware change, with independent review.

## Acceptance gates

- [ ] Disposable migration replay succeeds.
- [ ] All 24 pgTAP index-presence assertions pass.
- [ ] Supabase Performance Advisor reports zero unindexed foreign keys after authorized staging rollout.
- [ ] Query-plan and workflow regression tests pass.
- [ ] No index is removed solely because `idx_scan=0`.
- [ ] No shared staging/production migration is applied by this PR.


## Prefix-overlap review (read-only catalog check)

A catalog comparison found four non-unique indexes whose ordered key columns are a prefix of a unique index on the same table:

| Table | Candidate prefix index | Potential covering unique index |
|---|---|---|
| `branch_inventory` | `branch_inventory_branch_idx (branch_id)` | `branch_inventory_branch_id_inventory_item_id_key (branch_id, inventory_item_id)` |
| `branch_operation_checklist_runs` | `branch_operation_checklist_branch_date_idx (branch_id, business_date DESC, checklist_type)` | `branch_operation_checklist_run_unique (branch_id, business_date, checklist_type)` |
| `stock_count_items` | `stock_count_items_count_idx (stock_count_id)` | `stock_count_items_stock_count_id_inventory_item_id_key (stock_count_id, inventory_item_id)` |
| `stock_transfer_items` | `stock_transfer_items_transfer_idx (transfer_id)` | `stock_transfer_items_transfer_id_inventory_item_id_key (transfer_id, inventory_item_id)` |

These are **possible consolidation candidates, not approved drops**. The checklist index has a DESC key while the unique index is ASC; PostgreSQL can often scan B-trees backward, but actual query predicates/orderings still need plan verification. Before removing any prefix index, inspect all application/RPC/RLS queries and compare `EXPLAIN (ANALYZE, BUFFERS)` on realistic datasets. This PR deliberately retains all four.
