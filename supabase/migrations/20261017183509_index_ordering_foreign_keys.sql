-- Cover foreign keys to keep joins/deletes efficient as D'lice order data grows.
create index if not exists order_items_order_id_idx on public.order_items(order_id);
create index if not exists order_items_product_id_idx on public.order_items(product_id);
create index if not exists order_reservations_order_id_idx on public.order_reservations(order_id);
create index if not exists order_status_history_order_id_idx on public.order_status_history(order_id);
create index if not exists order_status_history_changed_by_idx on public.order_status_history(changed_by);
create index if not exists payment_records_order_id_idx on public.payment_records(order_id);
create index if not exists payment_records_verified_by_idx on public.payment_records(verified_by);
create index if not exists admin_audit_logs_actor_user_id_idx on public.admin_audit_logs(actor_user_id);
create index if not exists payment_settings_updated_by_idx on public.payment_settings(updated_by);
