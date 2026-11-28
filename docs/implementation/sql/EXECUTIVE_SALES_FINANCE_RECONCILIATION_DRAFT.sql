-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Apply after EXECUTIVE_SALES_APPROVAL_DRAFT.sql in a disposable replay.
-- Adds tender and posted-journal parity to the Executive sales read model.
begin;

create or replace view public.executive_pos_sales_fact
with (security_invoker=true)
as
select
  b.tenant_id,
  s.branch_id,
  b.code as branch_code,
  b.name as branch_name,
  b.timezone,
  b.business_day_cutoff,
  s.id as sale_id,
  s.transaction_code,
  s.shift_id,
  s.cashier_user_id,
  s.created_at,
  ((s.created_at at time zone b.timezone)::date
    - case when (s.created_at at time zone b.timezone)::time < b.business_day_cutoff then 1 else 0 end) as business_date,
  s.subtotal_idr as gross_idr,
  s.discount_idr,
  s.total_idr as sale_total_idr,
  coalesce(r.refund_idr,0)::bigint as processed_refund_idr,
  greatest(s.total_idr-coalesce(r.refund_idr,0),0)::bigint as net_sales_idr,
  s.payment_method,
  s.payment_status,
  coalesce(st.settled_idr,0)::bigint as matched_settlement_idr,
  coalesce(j.journal_entry_count,0)::bigint as finance_journal_entry_count,
  coalesce(j.journal_entry_ids,'[]'::jsonb) as finance_journal_entry_ids,
  coalesce(td.tender_allocated_idr,0)::bigint as tender_allocated_idr,
  coalesce(j.sale_journal_idr,0)::bigint-coalesce(j.refund_journal_idr,0)::bigint as finance_journal_net_idr,
  (coalesce(j.sale_journal_idr,0)::bigint-coalesce(j.refund_journal_idr,0)::bigint)
    - greatest(s.total_idr-coalesce(r.refund_idr,0),0)::bigint as finance_variance_idr,
  coalesce(td.tender_allocated_idr,0)::bigint-s.total_idr as tender_variance_idr
from public.pos_sales s
join public.branches b on b.id=s.branch_id
left join lateral (
  select sum(rr.amount_idr)::bigint as refund_idr,
    coalesce(array_agg(rr.id),'{}'::uuid[]) as refund_ids
  from public.refund_records rr
  where rr.pos_sale_id=s.id and rr.branch_id=s.branch_id and rr.status='processed'
) r on true
left join lateral (
  select sum(si.amount_idr)::bigint as settled_idr
  from public.payment_settlement_items si
  join public.payment_settlements ps on ps.id=si.settlement_id
  where si.pos_sale_id=s.id and ps.status='matched'
) st on true
left join lateral (
  select sum(t.amount_idr)::bigint as tender_allocated_idr
  from public.pos_sale_tenders t where t.sale_id=s.id and t.branch_id=s.branch_id
) td on true
left join lateral (
  select count(*)::bigint as journal_entry_count,
    coalesce(sum(fje.amount_idr) filter(where fje.source_id=s.id and fje.status='posted'),0)::bigint as sale_journal_idr,
    coalesce(sum(fje.amount_idr) filter(where fje.source_id=any(r.refund_ids) and fje.status='posted'),0)::bigint as refund_journal_idr,
    coalesce(jsonb_agg(jsonb_build_object('id',fje.id,'source_type',fje.source_type,'source_id',fje.source_id,
      'amount_idr',fje.amount_idr,'status',fje.status) order by fje.created_at),'[]'::jsonb) as journal_entry_ids
  from public.finance_journal_entries fje
  where (fje.source_id=s.id or fje.source_id=any(r.refund_ids))
) j on true
where s.payment_status in ('paid','refunded');

create or replace function public.executive_sales_monitor_snapshot(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_period_type text,p_period_start date,p_period_end date
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_role text; v_platform_owner boolean:=false; v_allowed uuid[]; v_requested uuid[];
 v_rows jsonb; v_daily jsonb; v_totals jsonb; v_finance jsonb; v_snapshot_id uuid; v_count integer;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='EXECUTIVE_SERVICE_ROLE_REQUIRED'; end if;
 if p_actor_user_id is null or p_tenant_id is null or p_period_start is null or p_period_end is null
  or p_period_end<p_period_start or p_period_type not in ('day','week','month') then
  raise exception using errcode='22023',message='EXECUTIVE_SALES_INPUT_INVALID';
 end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if not found then raise exception using errcode='42501',message='EXECUTIVE_TENANT_MEMBERSHIP_REQUIRED'; end if;
 select case when jsonb_typeof(u.raw_app_meta_data->'platform_owner')='boolean'
  then (u.raw_app_meta_data->>'platform_owner')::boolean else false end
 into v_platform_owner from auth.users u where u.id=p_actor_user_id;
 if not exists(select 1 from public.admin_profiles ap where ap.user_id=p_actor_user_id and ap.is_active=true)
  then raise exception using errcode='42501',message='EXECUTIVE_ACTIVE_PROFILE_REQUIRED'; end if;
 if v_role in ('tenant_owner','tenant_admin','group_hq','head_ops') or coalesce(v_platform_owner,false) then
  select coalesce(array_agg(b.id order by b.code),'{}'::uuid[]) into v_allowed from public.branches b where b.tenant_id=p_tenant_id;
 else
  select coalesce(array_agg(distinct b.id),'{}'::uuid[]) into v_allowed from public.branches b
   join public.branch_assignments ba on ba.branch_id=b.id
   where b.tenant_id=p_tenant_id and ba.user_id=p_actor_user_id and ba.employment_status='active'
    and ba.starts_on<=current_date and (ba.ends_on is null or ba.ends_on>=current_date);
 end if;
 v_requested:=case when coalesce(cardinality(p_branch_ids),0)=0 then v_allowed else p_branch_ids end;
 if cardinality(v_requested)=0 or not(v_requested<@v_allowed) then raise exception using errcode='42501',message='EXECUTIVE_BRANCH_SCOPE_DENIED'; end if;
 if exists(select 1 from unnest(v_requested) x group by x having count(*)>1) then raise exception using errcode='22023',message='EXECUTIVE_BRANCH_DUPLICATE'; end if;

 select coalesce(jsonb_agg(to_jsonb(f) order by f.business_date,f.created_at,f.sale_id),'[]'::jsonb),count(*)
 into v_rows,v_count from public.executive_pos_sales_fact f
 where f.tenant_id=p_tenant_id and f.branch_id=any(v_requested) and f.business_date between p_period_start and p_period_end;

 select coalesce(jsonb_agg(jsonb_build_object('business_date',d.business_date,'gross_idr',d.gross_idr,
  'discount_idr',d.discount_idr,'refund_idr',d.refund_idr,'net_sales_idr',d.net_sales_idr,
  'matched_settlement_idr',d.matched_settlement_idr,'tender_allocated_idr',d.tender_allocated_idr,
  'finance_journal_net_idr',d.finance_journal_net_idr,'finance_variance_idr',d.finance_variance_idr,
  'tender_variance_idr',d.tender_variance_idr,'transaction_count',d.transaction_count)
  order by d.business_date),'[]'::jsonb) into v_daily
 from (select business_date,sum(gross_idr)::bigint gross_idr,sum(discount_idr)::bigint discount_idr,
  sum(processed_refund_idr)::bigint refund_idr,sum(net_sales_idr)::bigint net_sales_idr,
  sum(matched_settlement_idr)::bigint matched_settlement_idr,sum(tender_allocated_idr)::bigint tender_allocated_idr,
  sum(finance_journal_net_idr)::bigint finance_journal_net_idr,sum(finance_variance_idr)::bigint finance_variance_idr,
  sum(tender_variance_idr)::bigint tender_variance_idr,count(*)::integer transaction_count
  from public.executive_pos_sales_fact where tenant_id=p_tenant_id and branch_id=any(v_requested)
   and business_date between p_period_start and p_period_end group by business_date) d;

 select jsonb_build_object('gross_idr',coalesce(sum(gross_idr),0),'discount_idr',coalesce(sum(discount_idr),0),
  'refund_idr',coalesce(sum(processed_refund_idr),0),'net_sales_idr',coalesce(sum(net_sales_idr),0),
  'matched_settlement_idr',coalesce(sum(matched_settlement_idr),0),'tender_allocated_idr',coalesce(sum(tender_allocated_idr),0),
  'finance_journal_net_idr',coalesce(sum(finance_journal_net_idr),0),'finance_variance_idr',coalesce(sum(finance_variance_idr),0),
  'tender_variance_idr',coalesce(sum(tender_variance_idr),0),'transaction_count',count(*))
 into v_totals from public.executive_pos_sales_fact
 where tenant_id=p_tenant_id and branch_id=any(v_requested) and business_date between p_period_start and p_period_end;

 select jsonb_build_object('sale_count',count(*),
  'sale_without_journal_count',count(*) filter(where finance_journal_entry_count=0),
  'linked_journal_entry_count',coalesce(sum(finance_journal_entry_count),0),
  'net_sales_idr',coalesce(sum(net_sales_idr),0),
  'posted_journal_net_idr',coalesce(sum(finance_journal_net_idr),0),
  'journal_variance_idr',coalesce(sum(finance_variance_idr),0),
  'tender_variance_idr',coalesce(sum(tender_variance_idr),0),
  'matched_settlement_idr',coalesce(sum(matched_settlement_idr),0),
  'status',case when count(*)=0 then 'no_transactions'
   when count(*) filter(where finance_journal_entry_count=0)>0 or coalesce(sum(finance_variance_idr),0)<>0
     or coalesce(sum(tender_variance_idr),0)<>0 then 'needs_reconciliation'
   else 'reconciled' end)
 into v_finance from public.executive_pos_sales_fact
 where tenant_id=p_tenant_id and branch_id=any(v_requested) and business_date between p_period_start and p_period_end;

 insert into public.executive_sales_kpi_snapshots
 (tenant_id,actor_user_id,metric_key,formula_version,period_type,period_start,period_end,branch_ids,totals,daily,transactions,finance_reconciliation,source_sale_count)
 values(p_tenant_id,p_actor_user_id,'sales_net','sales-net-v1',p_period_type,p_period_start,p_period_end,v_requested,v_totals,v_daily,v_rows,v_finance,v_count)
 returning id into v_snapshot_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.sales.snapshot_created','executive_sales_kpi_snapshot',v_snapshot_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_ids',v_requested,'period_type',p_period_type,
   'period_start',p_period_start,'period_end',p_period_end,'source_sale_count',v_count,
   'formula_version','sales-net-v1','finance_reconciliation',v_finance));
 return jsonb_build_object('snapshot_id',v_snapshot_id,'tenant_id',p_tenant_id,'period_type',p_period_type,
  'period_start',p_period_start,'period_end',p_period_end,'branch_ids',v_requested,'totals',v_totals,
  'daily',v_daily,'transactions',v_rows,'finance_reconciliation',v_finance,
  'formula_version','sales-net-v1','source_sale_count',v_count,'generated_at',now());
end $$;
revoke all on function public.executive_sales_monitor_snapshot(uuid,uuid,uuid[],text,date,date) from public,anon,authenticated;
grant execute on function public.executive_sales_monitor_snapshot(uuid,uuid,uuid[],text,date,date) to service_role;

rollback;