-- Cover foreign-key columns used for deletes, joins and audit lookups in the multi-branch ERP.
create index if not exists branch_assignments_job_position_id_idx on public.branch_assignments(job_position_id);
create index if not exists branch_assignments_assigned_by_idx on public.branch_assignments(assigned_by);
create index if not exists branch_expenses_created_by_idx on public.branch_expenses(created_by);
create index if not exists branch_expenses_reviewed_by_idx on public.branch_expenses(reviewed_by);
create index if not exists branch_inventory_inventory_item_id_idx on public.branch_inventory(inventory_item_id);
create index if not exists inventory_items_created_by_idx on public.inventory_items(created_by);
create index if not exists pos_sale_items_product_id_idx on public.pos_sale_items(product_id);
create index if not exists pos_sale_items_sale_id_idx on public.pos_sale_items(sale_id);
create index if not exists pos_sales_cashier_user_id_idx on public.pos_sales(cashier_user_id);
create index if not exists pos_shifts_opened_by_idx on public.pos_shifts(opened_by);
create index if not exists pos_shifts_closed_by_idx on public.pos_shifts(closed_by);
create index if not exists purchase_order_items_inventory_item_id_idx on public.purchase_order_items(inventory_item_id);
create index if not exists purchase_order_items_purchase_order_id_idx on public.purchase_order_items(purchase_order_id);
create index if not exists purchase_orders_approved_by_idx on public.purchase_orders(approved_by);
create index if not exists purchase_orders_requested_by_idx on public.purchase_orders(requested_by);
create index if not exists purchase_orders_supplier_id_idx on public.purchase_orders(supplier_id);
create index if not exists stock_movements_created_by_idx on public.stock_movements(created_by);
