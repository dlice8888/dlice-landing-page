-- Applied to staging as migration 20261020202158.
create or replace function public.erp_guard_refund_amount() returns trigger language plpgsql set search_path=public as $$
declare max_amount bigint; already_refunded bigint;
begin
 if tg_op='UPDATE' and old.status in ('processed','rejected') then
  if new.status<>old.status or new.amount_idr<>old.amount_idr or new.reason<>old.reason or new.payment_record_id is distinct from old.payment_record_id or new.pos_sale_id is distinct from old.pos_sale_id or new.order_id is distinct from old.order_id or new.branch_id is distinct from old.branch_id or new.requested_by<>old.requested_by or new.reviewed_by is distinct from old.reviewed_by or new.processed_by is distinct from old.processed_by or new.external_reference is distinct from old.external_reference then raise exception 'final_refund_status_immutable'; end if;
  return new;
 end if;
 if new.status not in ('requested','approved','processed') then return new; end if;
 if new.payment_record_id is not null then
  perform 1 from public.payment_records where id=new.payment_record_id for update;
  select amount_idr into max_amount from public.payment_records where id=new.payment_record_id;
  select coalesce(sum(amount_idr),0) into already_refunded from public.refund_records where payment_record_id=new.payment_record_id and status in ('requested','approved','processed') and id is distinct from new.id;
 elsif new.pos_sale_id is not null then
  perform 1 from public.pos_sales where id=new.pos_sale_id for update;
  select total_idr into max_amount from public.pos_sales where id=new.pos_sale_id;
  select coalesce(sum(amount_idr),0) into already_refunded from public.refund_records where pos_sale_id=new.pos_sale_id and status in ('requested','approved','processed') and id is distinct from new.id;
 elsif new.order_id is not null then
  perform 1 from public.orders where id=new.order_id for update;
  select product_subtotal_idr into max_amount from public.orders where id=new.order_id;
  select coalesce(sum(amount_idr),0) into already_refunded from public.refund_records where order_id=new.order_id and status in ('requested','approved','processed') and id is distinct from new.id;
 end if;
 if max_amount is null or new.amount_idr>max_amount-already_refunded then raise exception 'refund_exceeds_remaining_balance'; end if;
 return new;
end $$;
