-- T01 / D01-F02: authoritative, branch-local sales snapshot.
-- Source migration. Apply only to the disposable/staging project after review.
begin;

create table if not exists public.branch_business_day_policies (
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 cutoff_time time without time zone not null default time '00:00',
 policy_version integer not null default 1 check(policy_version>0),
 updated_by uuid references auth.users(id) on delete restrict,
 updated_at timestamptz not null default now(),
 primary key(tenant_id,branch_id),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);

create table if not exists public.executive_kpi_formula_versions (
 formula_key text not null,
 formula_version text not null,
 definition jsonb not null check(jsonb_typeof(definition)='object'),
 is_active boolean not null default false,
 created_at timestamptz not null default now(),
 primary key(formula_key,formula_version)
);
insert into public.executive_kpi_formula_versions(formula_key,formula_version,definition,is_active)
values('sales_net','sales-net-v1',
 '{"gross":"sum(pos_sales.subtotal_idr)","discount":"sum(pos_sales.discount_idr)","refund":"sum(refund_records.amount_idr where status=processed)","net":"sum(pos_sales.total_idr)-processed_refunds","eligibility":"pos_sales.payment_status=paid","business_date":"(created_at at branch.timezone - branch_business_day_policies.cutoff_time)::date","settlement":"sum(reconciled payment_settlement_items.amount_idr)","finance":"posted finance_journal_entries linked by source_id to sale"}'::jsonb,true)
on conflict(formula_key,formula_version) do nothing;

create table if not exists public.executive_sales_monitor_snapshots (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 period_type text not null check(period_type in ('day','week','month')),
 period_start date not null,period_end date not null,
 formula_key text not null default 'sales_net',formula_version text not null,
 branch_ids uuid[] not null,
 gross_idr bigint not null,discount_idr bigint not null,refund_idr bigint not null,net_sales_idr bigint not null,
 matched_settlement_idr bigint not null,transaction_count integer not null,
 finance_sale_count integer not null,finance_sale_without_journal_count integer not null,
 finance_linked_journal_entry_count integer not null,
 created_at timestamptz not null default now(),
 foreign key(formula_key,formula_version) references public.executive_kpi_formula_versions(formula_key,formula_version),
 check(period_end>=period_start),check(gross_idr>=0 and discount_idr>=0 and refund_idr>=0 and net_sales_idr>=0 and matched_settlement_idr>=0)
);
create index if not exists executive_sales_snapshots_tenant_period_idx on public.executive_sales_monitor_snapshots(tenant_id,period_start,period_end,created_at desc);

create table if not exists public.executive_sales_monitor_snapshot_rows (
 snapshot_id uuid not null references public.executive_sales_monitor_snapshots(id) on delete cascade,
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 sale_id uuid not null references public.pos_sales(id) on delete restrict,
 branch_id uuid not null,shift_id uuid not null,branch_code text not null,
 transaction_code text not null,business_date date not null,timezone text not null,cutoff_time time without time zone not null,
 gross_idr bigint not null,discount_idr bigint not null,sale_total_idr bigint not null,processed_refund_idr bigint not null,net_sales_idr bigint not null,
 tender_allocated_idr bigint not null,matched_settlement_idr bigint not null,finance_journal_entry_count integer not null,
 primary key(snapshot_id,sale_id),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists executive_sales_snapshot_rows_sale_idx on public.executive_sales_monitor_snapshot_rows(tenant_id,sale_id);

alter table public.branch_business_day_policies enable row level security;
alter table public.branch_business_day_policies force row level security;
alter table public.executive_kpi_formula_versions enable row level security;
alter table public.executive_kpi_formula_versions force row level security;
alter table public.executive_sales_monitor_snapshots enable row level security;
alter table public.executive_sales_monitor_snapshots force row level security;
alter table public.executive_sales_monitor_snapshot_rows enable row level security;
alter table public.executive_sales_monitor_snapshot_rows force row level security;
do $$ declare t text; begin
 foreach t in array array['branch_business_day_policies','executive_kpi_formula_versions','executive_sales_monitor_snapshots','executive_sales_monitor_snapshot_rows'] loop
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;

create or replace function public.executive_sales_monitor_snapshot(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_period_type text,p_period_start date,p_period_end date
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_snapshot public.executive_sales_monitor_snapshots%rowtype;
 v_rows jsonb;v_daily jsonb;v_finance jsonb;v_payment jsonb;v_branch_count integer;v_tender_mismatch integer;v_refund_overrun integer;
 v_gross bigint;v_discount bigint;v_refund bigint;v_net bigint;v_settlement bigint;v_count integer;
 v_finance_count integer;v_missing_journal integer;v_journal_count integer;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then
  raise exception using errcode='42501',message='EXECUTIVE_SERVICE_ROLE_REQUIRED';
 end if;
 if p_actor_user_id is null or p_tenant_id is null or p_period_type not in ('day','week','month')
  or p_period_start is null or p_period_end is null or p_period_end<p_period_start
  or p_period_end-p_period_start>366 then
  raise exception using errcode='22023',message='EXECUTIVE_SALES_INPUT_INVALID';
 end if;
 if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active') then
  raise exception using errcode='42501',message='EXECUTIVE_TENANT_MEMBERSHIP_REQUIRED';
 end if;
 if coalesce(cardinality(p_branch_ids),0)=0 then raise exception using errcode='22023',message='EXECUTIVE_BRANCH_SCOPE_EMPTY';end if;
 select count(*) into v_branch_count from public.branches b
 where b.tenant_id=p_tenant_id and b.id=any(p_branch_ids);
 if v_branch_count<>cardinality(p_branch_ids) then raise exception using errcode='42501',message='EXECUTIVE_BRANCH_SCOPE_DENIED';end if;

 create temporary table _exec_sales_rows on commit drop as
 with sales as (
  select s.id sale_id,s.transaction_code,s.branch_id,s.shift_id,b.code branch_code,s.subtotal_idr gross_idr,s.discount_idr,
   s.total_idr,s.created_at,b.timezone,coalesce(p.cutoff_time,time '00:00') cutoff_time,
   (s.created_at at time zone b.timezone - coalesce(p.cutoff_time,time '00:00'))::date business_date
  from public.pos_sales s join public.branches b on b.id=s.branch_id and b.tenant_id=p_tenant_id
  left join public.branch_business_day_policies p on p.tenant_id=b.tenant_id and p.branch_id=b.id
  where b.id=any(p_branch_ids) and s.payment_status='paid'
 ), refunds as (
  select r.pos_sale_id,sum(r.amount_idr)::bigint amount_idr from public.refund_records r
  where r.status='processed' and r.pos_sale_id is not null group by r.pos_sale_id
 ), tenders as (
  select t.sale_id,sum(t.amount_idr)::bigint amount_idr from public.pos_sale_tenders t group by t.sale_id
 ), settlements as (
  select i.pos_sale_id,sum(i.amount_idr)::bigint amount_idr
  from public.payment_settlement_items i join public.payment_settlements s on s.id=i.settlement_id
  where s.status='reconciled' and i.pos_sale_id is not null group by i.pos_sale_id
 ), journals as (
  select j.source_id,count(*)::integer entry_count from public.finance_journal_entries j
  where j.status='posted' and j.source_id is not null group by j.source_id
 )
 select s.sale_id,s.transaction_code,s.branch_id,s.shift_id,s.branch_code,s.business_date,s.timezone,s.cutoff_time,
  s.gross_idr,s.discount_idr,s.total_idr sale_total_idr,coalesce(r.amount_idr,0)::bigint processed_refund_idr,
  (s.total_idr-coalesce(r.amount_idr,0))::bigint net_sales_idr,
  coalesce(t.amount_idr,0)::bigint tender_allocated_idr,coalesce(st.amount_idr,0)::bigint matched_settlement_idr,
  coalesce(j.entry_count,0)::integer finance_journal_entry_count
 from sales s left join refunds r on r.pos_sale_id=s.sale_id left join tenders t on t.sale_id=s.sale_id
 left join settlements st on st.pos_sale_id=s.sale_id left join journals j on j.source_id=s.sale_id
 where s.business_date between p_period_start and p_period_end;

 select count(*) filter(where net_sales_idr<0)::integer into v_refund_overrun from _exec_sales_rows;
 if v_refund_overrun>0 then raise exception using errcode='23514',message='EXECUTIVE_REFUND_EXCEEDS_SALE_TOTAL';end if;
 select count(*) filter(where tender_allocated_idr<>sale_total_idr)::integer into v_tender_mismatch from _exec_sales_rows;
 select coalesce(sum(gross_idr),0),coalesce(sum(discount_idr),0),coalesce(sum(processed_refund_idr),0),
  coalesce(sum(net_sales_idr),0),coalesce(sum(matched_settlement_idr),0),count(*)::integer,
  count(*) filter(where finance_journal_entry_count>0)::integer,
  count(*) filter(where finance_journal_entry_count=0)::integer,
  coalesce(sum(finance_journal_entry_count),0)::integer
 into v_gross,v_discount,v_refund,v_net,v_settlement,v_count,v_finance_count,v_missing_journal,v_journal_count
 from _exec_sales_rows;

 insert into public.executive_sales_monitor_snapshots(tenant_id,actor_user_id,period_type,period_start,period_end,
  formula_key,formula_version,branch_ids,gross_idr,discount_idr,refund_idr,net_sales_idr,matched_settlement_idr,
  transaction_count,finance_sale_count,finance_sale_without_journal_count,finance_linked_journal_entry_count)
 values(p_tenant_id,p_actor_user_id,p_period_type,p_period_start,p_period_end,'sales_net','sales-net-v1',p_branch_ids,
  v_gross,v_discount,v_refund,v_net,v_settlement,v_count,v_finance_count,v_missing_journal,v_journal_count)
 returning * into v_snapshot;

 insert into public.executive_sales_monitor_snapshot_rows(snapshot_id,tenant_id,sale_id,branch_id,shift_id,branch_code,transaction_code,
  business_date,timezone,cutoff_time,gross_idr,discount_idr,sale_total_idr,processed_refund_idr,net_sales_idr,tender_allocated_idr,
  matched_settlement_idr,finance_journal_entry_count)
 select v_snapshot.id,p_tenant_id,sale_id,branch_id,shift_id,branch_code,transaction_code,business_date,timezone,cutoff_time,gross_idr,
  discount_idr,sale_total_idr,processed_refund_idr,net_sales_idr,tender_allocated_idr,matched_settlement_idr,finance_journal_entry_count
 from _exec_sales_rows;

 select coalesce(jsonb_agg(jsonb_build_object('business_date',d.business_date,'gross_idr',d.gross_idr,
  'discount_idr',d.discount_idr,'refund_idr',d.refund_idr,'net_sales_idr',d.net_sales_idr,'matched_settlement_idr',d.matched_settlement_idr,'transaction_count',d.transaction_count)
  order by d.business_date),'[]'::jsonb) into v_daily
 from (select business_date,sum(gross_idr)::bigint gross_idr,sum(discount_idr)::bigint discount_idr,
  sum(processed_refund_idr)::bigint refund_idr,sum(net_sales_idr)::bigint net_sales_idr,sum(matched_settlement_idr)::bigint matched_settlement_idr,count(*)::integer transaction_count
  from _exec_sales_rows group by business_date) d;
 select coalesce(jsonb_agg(jsonb_build_object('sale_id',sale_id,'transaction_code',transaction_code,'branch_id',branch_id,'branch_code',branch_code,'shift_id',shift_id,
  'business_date',business_date,'timezone',timezone,'cutoff_time',cutoff_time,'gross_idr',gross_idr,'discount_idr',discount_idr,'sale_total_idr',sale_total_idr,
  'processed_refund_idr',processed_refund_idr,'net_sales_idr',net_sales_idr,'tender_allocated_idr',tender_allocated_idr,
  'matched_settlement_idr',matched_settlement_idr,'finance_journal_entry_count',finance_journal_entry_count)
  order by business_date,transaction_code),'[]'::jsonb) into v_rows from _exec_sales_rows;
 v_payment:=jsonb_build_object('sale_count',v_count,'tender_mismatch_count',v_tender_mismatch,'tender_allocations_balanced',v_tender_mismatch=0);
 v_finance:=jsonb_build_object('sale_count',v_count,'sale_without_journal_count',v_missing_journal,
  'linked_journal_entry_count',v_journal_count,'status',case when v_missing_journal=0 then 'journal_links_present' else 'journal_links_incomplete' end);
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.sales_monitor.snapshot','executive_sales_monitor_snapshots',v_snapshot.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'period_type',p_period_type,'period_start',p_period_start,'period_end',p_period_end,
   'formula_version','sales-net-v1','branch_ids',p_branch_ids,'transaction_count',v_count));
 return jsonb_build_object('snapshot_id',v_snapshot.id,'tenant_id',p_tenant_id,'period_type',p_period_type,
  'formula_version','sales-net-v1','totals',jsonb_build_object('gross_idr',v_gross,'discount_idr',v_discount,
   'refund_idr',v_refund,'net_sales_idr',v_net,'matched_settlement_idr',v_settlement,'transaction_count',v_count),
  'daily',v_daily,'transactions',v_rows,'payment_reconciliation',v_payment,'finance_reconciliation',v_finance);
end $$;
create or replace function public.get_branch_business_day_cutoff(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_id uuid,p_branch_ids uuid[]
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_branch public.branches%rowtype;v_cutoff time;v_version integer;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='EXECUTIVE_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null then raise exception using errcode='42501',message='EXECUTIVE_TENANT_MEMBERSHIP_REQUIRED';end if;
 select * into v_branch from public.branches where tenant_id=p_tenant_id and id=p_branch_id;
 if not found then raise exception using errcode='42501',message='EXECUTIVE_BRANCH_SCOPE_DENIED';end if;
 if v_role<>'tenant_owner' and (v_role<>'branch_manager' or not p_branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then
  raise exception using errcode='42501',message='EXECUTIVE_CUTOFF_READ_DENIED';end if;
 select cutoff_time,policy_version into v_cutoff,v_version from public.branch_business_day_policies where tenant_id=p_tenant_id and branch_id=p_branch_id;
 return jsonb_build_object('branch_id',p_branch_id,'timezone',v_branch.timezone,'cutoff_time',coalesce(v_cutoff,time '00:00'),'policy_version',coalesce(v_version,0));
end $;

create or replace function public.set_branch_business_day_cutoff(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_id uuid,p_branch_ids uuid[],p_cutoff_time time without time zone,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_version integer;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='EXECUTIVE_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null then raise exception using errcode='42501',message='EXECUTIVE_TENANT_MEMBERSHIP_REQUIRED';end if;
 if not exists(select 1 from public.branches where tenant_id=p_tenant_id and id=p_branch_id) then raise exception using errcode='42501',message='EXECUTIVE_BRANCH_SCOPE_DENIED';end if;
 if v_role<>'tenant_owner' and (v_role<>'branch_manager' or not p_branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then
  raise exception using errcode='42501',message='EXECUTIVE_CUTOFF_UPDATE_DENIED';end if;
 select policy_version into v_version from public.branch_business_day_policies where tenant_id=p_tenant_id and branch_id=p_branch_id for update;
 if not found then v_version:=0;end if;
 if v_version<>p_expected_version then raise exception using errcode='40001',message='EXECUTIVE_CUTOFF_STALE_VERSION';end if;
 insert into public.branch_business_day_policies(tenant_id,branch_id,cutoff_time,policy_version,updated_by)
 values(p_tenant_id,p_branch_id,p_cutoff_time,v_version+1,p_actor_user_id)
 on conflict(tenant_id,branch_id) do update set cutoff_time=excluded.cutoff_time,policy_version=excluded.policy_version,
  updated_by=excluded.updated_by,updated_at=now();
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.branch_business_day_cutoff.updated','branches',p_branch_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'cutoff_time',p_cutoff_time,'policy_version',v_version+1));
 return jsonb_build_object('branch_id',p_branch_id,'cutoff_time',p_cutoff_time,'policy_version',v_version+1);
end $;

revoke all on function public.executive_sales_monitor_snapshot(uuid,uuid,uuid[],text,date,date) from public,anon,authenticated;
grant execute on function public.executive_sales_monitor_snapshot(uuid,uuid,uuid[],text,date,date) to service_role;
revoke all on function public.set_branch_business_day_cutoff(uuid,uuid,uuid,uuid[],time,integer) from public,anon,authenticated;
grant execute on function public.set_branch_business_day_cutoff(uuid,uuid,uuid,uuid[],time,integer) to service_role;
revoke all on function public.get_branch_business_day_cutoff(uuid,uuid,uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.get_branch_business_day_cutoff(uuid,uuid,uuid,uuid[]) to service_role;
commit;
