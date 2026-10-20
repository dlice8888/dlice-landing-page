-- Applied to staging as migration 20261020201654.
create unique index if not exists payment_settlement_one_match_per_payment_idx on public.payment_settlement_items(payment_record_id) where payment_record_id is not null;
create unique index if not exists payment_settlement_one_match_per_pos_sale_idx on public.payment_settlement_items(pos_sale_id) where pos_sale_id is not null;
create unique index if not exists finance_journal_one_active_source_idx on public.finance_journal_entries(source_type,source_id) where source_id is not null and status<>'reversed';
create or replace function public.erp_guard_journal_period() returns trigger language plpgsql set search_path=public as $$
declare p public.fiscal_periods%rowtype;
begin
 if new.status='posted' and new.fiscal_period_id is not null then
  select * into p from public.fiscal_periods where id=new.fiscal_period_id for share;
  if not found then raise exception 'fiscal_period_not_found'; end if;
  if p.status='closed' then raise exception 'fiscal_period_closed'; end if;
  if new.entry_date<p.starts_on or new.entry_date>p.ends_on then raise exception 'journal_date_outside_period'; end if;
 end if;
 if tg_op='UPDATE' and old.status='posted' and (new.source_type<>old.source_type or new.source_id is distinct from old.source_id or new.amount_idr<>old.amount_idr or new.debit_account<>old.debit_account or new.credit_account<>old.credit_account or new.entry_date<>old.entry_date) then
  raise exception 'posted_journal_is_immutable_use_reversal';
 end if;
 return new;
end $$;
drop trigger if exists trg_erp_guard_journal_period on public.finance_journal_entries;
create trigger trg_erp_guard_journal_period before insert or update on public.finance_journal_entries for each row execute function public.erp_guard_journal_period();
create or replace function public.erp_guard_refund_amount() returns trigger language plpgsql set search_path=public as $$
declare max_amount bigint; already_refunded bigint;
begin
 if tg_op='UPDATE' and old.status in ('processed','rejected') then
  if new.status<>old.status or new.amount_idr<>old.amount_idr or new.reason<>old.reason or new.payment_record_id is distinct from old.payment_record_id or new.pos_sale_id is distinct from old.pos_sale_id or new.order_id is distinct from old.order_id then raise exception 'final_refund_status_immutable'; end if;
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
drop trigger if exists trg_erp_guard_refund_amount on public.refund_records;
create trigger trg_erp_guard_refund_amount before insert or update of amount_idr,status on public.refund_records for each row execute function public.erp_guard_refund_amount();
