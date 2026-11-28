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

-- Payment recognition is immutable and server-timestamped. Existing paid rows are
-- explicitly marked as estimates because the original payment timestamp is absent.
alter table public.pos_sales
 add column if not exists paid_at timestamptz,
 add column if not exists business_date date,
 add column if not exists paid_at_source text,
 add column if not exists business_day_cutoff time without time zone,
 add column if not exists business_day_policy_version integer;

update public.pos_sales s
set paid_at=s.created_at,
 business_day_cutoff=coalesce(p.cutoff_time,time '00:00'),
 business_day_policy_version=coalesce(p.policy_version,0),
 business_date=(s.created_at at time zone b.timezone-coalesce(p.cutoff_time,time '00:00'))::date,
 paid_at_source='legacy_created_at_backfill'
from public.branches b
left join public.branch_business_day_policies p on p.tenant_id=b.tenant_id and p.branch_id=b.id
where b.id=s.branch_id and s.payment_status in ('paid','refunded') and s.paid_at is null;

do $ begin
 if not exists(select 1 from pg_constraint where conname='pos_sales_paid_at_source_check') then
  alter table public.pos_sales add constraint pos_sales_paid_at_source_check
   check(paid_at_source is null or paid_at_source in ('payment_transition','legacy_created_at_backfill'));
 end if;
end $;

create or replace function public.set_pos_sale_payment_recognition()
returns trigger language plpgsql security invoker set search_path=''
as $
declare v_timezone text;v_cutoff time;v_policy_version integer;
begin
 select b.timezone,coalesce(p.cutoff_time,time '00:00'),coalesce(p.policy_version,0)
 into v_timezone,v_cutoff,v_policy_version
 from public.branches b left join public.branch_business_day_policies p
  on p.tenant_id=b.tenant_id and p.branch_id=b.id
 where b.id=new.branch_id;
 if v_timezone is null then raise exception using errcode='23503',message='POS_SALE_BRANCH_TIMEZONE_REQUIRED';end if;
 if tg_op='INSERT' and new.payment_status='refunded' then
  raise exception using errcode='23514',message='POS_SALE_REFUND_REQUIRES_PAID_SOURCE';
 elsif tg_op='UPDATE' and old.payment_status in ('paid','refunded') then
  if new.branch_id is distinct from old.branch_id then raise exception using errcode='42501',message='POS_SALE_PAID_BRANCH_IMMUTABLE';end if;
  if new.paid_at is distinct from old.paid_at or new.paid_at_source is distinct from old.paid_at_source
    or new.business_date is distinct from old.business_date
    or new.business_day_cutoff is distinct from old.business_day_cutoff
    or new.business_day_policy_version is distinct from old.business_day_policy_version then
   raise exception using errcode='42501',message='POS_SALE_PAYMENT_RECOGNITION_IMMUTABLE';
  end if;
  if old.payment_status='refunded' and new.payment_status='paid' then
   raise exception using errcode='23514',message='POS_SALE_REFUND_CANNOT_REOPEN_PAYMENT';
  elsif new.payment_status not in ('paid','refunded') then
   raise exception using errcode='23514',message='POS_SALE_PAID_STATUS_TERMINAL';
  end if;
  new.paid_at:=old.paid_at;new.paid_at_source:=old.paid_at_source;new.business_date:=old.business_date;
  new.business_day_cutoff:=old.business_day_cutoff;new.business_day_policy_version:=old.business_day_policy_version;
 elsif new.payment_status='paid' then
  new.paid_at:=now();new.paid_at_source:='payment_transition';
  new.business_day_cutoff:=v_cutoff;new.business_day_policy_version:=v_policy_version;
  new.business_date:=(new.paid_at at time zone v_timezone-v_cutoff)::date;
 else
  new.paid_at:=null;new.paid_at_source:=null;new.business_date:=null;
  new.business_day_cutoff:=null;new.business_day_policy_version:=null;
 end if;
 return new;
end $;
drop trigger if exists pos_sales_payment_recognition on public.pos_sales;
create trigger pos_sales_payment_recognition
before insert or update of payment_status,branch_id,paid_at,paid_at_source,business_date,business_day_cutoff,business_day_policy_version
on public.pos_sales for each row execute function public.set_pos_sale_payment_recognition();
revoke all on function public.set_pos_sale_payment_recognition() from public,anon,authenticated,service_role;
create index if not exists pos_sales_branch_business_date_paid_idx
 on public.pos_sales(branch_id,business_date,paid_at) where payment_status in ('paid','refunded');

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
 '{"gross":"sum(pos_sales.subtotal_idr)","discount":"sum(pos_sales.discount_idr)","refund":"sum(processed refund_records linked to paid sale cohort)","net":"sum(pos_sales.total_idr)-processed_refunds","eligibility":"pos_sales.payment_status in (paid,refunded) and paid_at is not null","business_date":"immutable pos_sales.business_date captured at paid_at using branch timezone and cutoff policy version","settlement":"sum matched payment_settlement_items.amount_idr linked to sale cohort","finance":"posted finance_journal_entries linked to sale and refund source ids; expose missing and amount totals"}'::jsonb,true)
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
 finance_linked_journal_entry_count integer not null,finance_sale_journal_amount_idr bigint not null,
 finance_refund_journal_amount_idr bigint not null,finance_refunds_without_journal_count integer not null,
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
 transaction_code text not null,paid_at timestamptz not null,paid_at_source text not null,business_date date not null,
 timezone text not null,cutoff_time time without time zone not null,business_day_policy_version integer not null,
 gross_idr bigint not null,discount_idr bigint not null,sale_total_idr bigint not null,processed_refund_idr bigint not null,net_sales_idr bigint not null,
 tender_allocated_idr bigint not null,matched_settlement_idr bigint not null,finance_journal_entry_count integer not null,
 finance_journal_amount_idr bigint not null,finance_refund_journal_entry_count integer not null,finance_refund_journal_amount_idr bigint not null,
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
   s.total_idr,s.payment_method,s.paid_at,s.paid_at_source,s.business_day_policy_version,b.timezone,
   coalesce(s.business_day_cutoff,time '00:00') cutoff_time,s.business_date
  from public.pos_sales s join public.branches b on b.id=s.branch_id and b.tenant_id=p_tenant_id
  where b.id=any(p_branch_ids) and s.payment_status in ('paid','refunded')
   and s.paid_at is not null and s.business_date is not null
 ), refunds as (
  select r.pos_sale_id,sum(r.amount_idr)::bigint amount_idr from public.refund_records r
  where r.status='processed' and r.pos_sale_id is not null group by r.pos_sale_id
 ), tenders as (
  select t.sale_id,sum(t.amount_idr)::bigint amount_idr from public.pos_sale_tenders t group by t.sale_id
 ), settlements as (
  select i.pos_sale_id,sum(i.amount_idr)::bigint amount_idr
  from public.payment_settlement_items i join public.payment_settlements s on s.id=i.settlement_id
  where s.status='matched' and i.pos_sale_id is not null group by i.pos_sale_id
 ), journals as (
  select j.source_id,count(*)::integer entry_count,coalesce(sum(j.amount_idr),0)::bigint amount_idr
  from public.finance_journal_entries j where j.status='posted' and j.source_id is not null group by j.source_id
 ), refund_journals as (
  select r.pos_sale_id,count(j.id)::integer entry_count,coalesce(sum(j.amount_idr),0)::bigint amount_idr
  from public.refund_records r left join public.finance_journal_entries j on j.source_id=r.id and j.status='posted'
  where r.status='processed' and r.pos_sale_id is not null group by r.pos_sale_id
 )
 select s.sale_id,s.transaction_code,s.branch_id,s.shift_id,s.branch_code,s.paid_at,s.paid_at_source,
  s.business_date,s.timezone,s.cutoff_time,s.business_day_policy_version,
  s.gross_idr,s.discount_idr,s.total_idr sale_total_idr,coalesce(r.amount_idr,0)::bigint processed_refund_idr,
  (s.total_idr-coalesce(r.amount_idr,0))::bigint net_sales_idr,
  case when t.amount_idr is not null then t.amount_idr when s.payment_method='split' then 0 else s.total_idr end::bigint tender_allocated_idr,
  coalesce(st.amount_idr,0)::bigint matched_settlement_idr,
  coalesce(j.entry_count,0)::integer finance_journal_entry_count,coalesce(j.amount_idr,0)::bigint finance_journal_amount_idr,
  coalesce(rj.entry_count,0)::integer finance_refund_journal_entry_count,
  coalesce(rj.amount_idr,0)::bigint finance_refund_journal_amount_idr
 from sales s left join refunds r on r.pos_sale_id=s.sale_id left join tenders t on t.sale_id=s.sale_id
 left join settlements st on st.pos_sale_id=s.sale_id left join journals j on j.source_id=s.sale_id
 left join refund_journals rj on rj.pos_sale_id=s.sale_id
 where s.business_date between p_period_start and p_period_end;

 select count(*) filter(where net_sales_idr<0)::integer into v_refund_overrun from _exec_sales_rows;
 if v_refund_overrun>0 then raise exception using errcode='23514',message='EXECUTIVE_REFUND_EXCEEDS_SALE_TOTAL';end if;
 select count(*) filter(where tender_allocated_idr<>sale_total_idr)::integer into v_tender_mismatch from _exec_sales_rows;
 if exists(select 1 from _exec_sales_rows where gross_idr-discount_idr<>sale_total_idr) then
  raise exception using errcode='23514',message='EXECUTIVE_POS_SALE_TOTAL_MISMATCH';
 end if;
 select coalesce(sum(gross_idr),0),coalesce(sum(discount_idr),0),coalesce(sum(processed_refund_idr),0),
  coalesce(sum(net_sales_idr),0),coalesce(sum(matched_settlement_idr),0),count(*)::integer,
  count(*) filter(where finance_journal_entry_count>0)::integer,
  count(*) filter(where finance_journal_entry_count=0)::integer,
  coalesce(sum(finance_journal_entry_count),0)::integer
 into v_gross,v_discount,v_refund,v_net,v_settlement,v_count,v_finance_count,v_missing_journal,v_journal_count
 from _exec_sales_rows;

 insert into public.executive_sales_monitor_snapshots(tenant_id,actor_user_id,period_type,period_start,period_end,
  formula_key,formula_version,branch_ids,gross_idr,discount_idr,refund_idr,net_sales_idr,matched_settlement_idr,
  transaction_count,finance_sale_count,finance_sale_without_journal_count,finance_linked_journal_entry_count,
  finance_sale_journal_amount_idr,finance_refund_journal_amount_idr,finance_refunds_without_journal_count)
 values(p_tenant_id,p_actor_user_id,p_period_type,p_period_start,p_period_end,'sales_net','sales-net-v1',p_branch_ids,
  v_gross,v_discount,v_refund,v_net,v_settlement,v_count,v_finance_count,v_missing_journal,v_journal_count,
  (select coalesce(sum(finance_journal_amount_idr),0) from _exec_sales_rows),
  (select coalesce(sum(finance_refund_journal_amount_idr),0) from _exec_sales_rows),
  (select count(*) from _exec_sales_rows where processed_refund_idr>0 and finance_refund_journal_entry_count=0))
 returning * into v_snapshot;

 insert into public.executive_sales_monitor_snapshot_rows(snapshot_id,tenant_id,sale_id,branch_id,shift_id,branch_code,transaction_code,
  paid_at,paid_at_source,business_date,timezone,cutoff_time,business_day_policy_version,gross_idr,discount_idr,sale_total_idr,
  processed_refund_idr,net_sales_idr,tender_allocated_idr,matched_settlement_idr,finance_journal_entry_count,
  finance_journal_amount_idr,finance_refund_journal_entry_count,finance_refund_journal_amount_idr)
 select v_snapshot.id,p_tenant_id,sale_id,branch_id,shift_id,branch_code,transaction_code,paid_at,paid_at_source,business_date,timezone,
  cutoff_time,business_day_policy_version,gross_idr,discount_idr,sale_total_idr,processed_refund_idr,net_sales_idr,
  tender_allocated_idr,matched_settlement_idr,finance_journal_entry_count,finance_journal_amount_idr,
  finance_refund_journal_entry_count,finance_refund_journal_amount_idr
 from _exec_sales_rows;

 select coalesce(jsonb_agg(jsonb_build_object('business_date',d.business_date,'gross_idr',d.gross_idr,
  'discount_idr',d.discount_idr,'refund_idr',d.refund_idr,'net_sales_idr',d.net_sales_idr,'matched_settlement_idr',d.matched_settlement_idr,'transaction_count',d.transaction_count)
  order by d.business_date),'[]'::jsonb) into v_daily
 from (select business_date,sum(gross_idr)::bigint gross_idr,sum(discount_idr)::bigint discount_idr,
  sum(processed_refund_idr)::bigint refund_idr,sum(net_sales_idr)::bigint net_sales_idr,sum(matched_settlement_idr)::bigint matched_settlement_idr,count(*)::integer transaction_count
  from _exec_sales_rows group by business_date) d;
 select coalesce(jsonb_agg(jsonb_build_object('sale_id',sale_id,'transaction_code',transaction_code,'branch_id',branch_id,'branch_code',branch_code,'shift_id',shift_id,
  'paid_at',paid_at,'paid_at_source',paid_at_source,'business_date',business_date,'timezone',timezone,'cutoff_time',cutoff_time,
  'business_day_policy_version',business_day_policy_version,'gross_idr',gross_idr,'discount_idr',discount_idr,'sale_total_idr',sale_total_idr,
  'processed_refund_idr',processed_refund_idr,'net_sales_idr',net_sales_idr,'tender_allocated_idr',tender_allocated_idr,
  'matched_settlement_idr',matched_settlement_idr,'finance_journal_entry_count',finance_journal_entry_count,
  'finance_journal_amount_idr',finance_journal_amount_idr,'finance_refund_journal_entry_count',finance_refund_journal_entry_count,
  'finance_refund_journal_amount_idr',finance_refund_journal_amount_idr)
  order by business_date,transaction_code),'[]'::jsonb) into v_rows from _exec_sales_rows;
 v_payment:=jsonb_build_object('sale_count',v_count,'tender_mismatch_count',v_tender_mismatch,
  'tender_allocations_balanced',v_tender_mismatch=0,
  'legacy_paid_at_count',(select count(*) from _exec_sales_rows where paid_at_source='legacy_created_at_backfill'));
 v_finance:=jsonb_build_object('sale_count',v_count,'sale_without_journal_count',v_missing_journal,
  'linked_journal_entry_count',v_journal_count,
  'sale_journal_amount_idr',(select coalesce(sum(finance_journal_amount_idr),0) from _exec_sales_rows),
  'refund_journal_amount_idr',(select coalesce(sum(finance_refund_journal_amount_idr),0) from _exec_sales_rows),
  'refunds_without_journal_count',(select count(*) from _exec_sales_rows where processed_refund_idr>0 and finance_refund_journal_entry_count=0),
  'status',case when v_missing_journal=0 and not exists(select 1 from _exec_sales_rows where processed_refund_idr>0 and finance_refund_journal_entry_count=0)
    then 'journal_links_present' else 'journal_links_incomplete' end);
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
as $$ declare v_role text;v_branch public.branches%rowtype;v_cutoff time;v_version integer;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='EXECUTIVE_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null then raise exception using errcode='42501',message='EXECUTIVE_TENANT_MEMBERSHIP_REQUIRED';end if;
 select * into v_branch from public.branches where tenant_id=p_tenant_id and id=p_branch_id;
 if not found then raise exception using errcode='42501',message='EXECUTIVE_BRANCH_SCOPE_DENIED';end if;
 if v_role<>'tenant_owner' and (v_role<>'branch_manager' or not p_branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then
  raise exception using errcode='42501',message='EXECUTIVE_CUTOFF_READ_DENIED';end if;
 select cutoff_time,policy_version into v_cutoff,v_version from public.branch_business_day_policies where tenant_id=p_tenant_id and branch_id=p_branch_id;
 return jsonb_build_object('branch_id',p_branch_id,'timezone',v_branch.timezone,'cutoff_time',coalesce(v_cutoff,time '00:00'),'policy_version',coalesce(v_version,0));
end $$;

create or replace function public.set_branch_business_day_cutoff(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_id uuid,p_branch_ids uuid[],p_cutoff_time time without time zone,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path=''
as $$ declare v_role text;v_version integer;begin
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
end $$;

revoke all on function public.executive_sales_monitor_snapshot(uuid,uuid,uuid[],text,date,date) from public,anon,authenticated;
grant execute on function public.executive_sales_monitor_snapshot(uuid,uuid,uuid[],text,date,date) to service_role;
revoke all on function public.set_branch_business_day_cutoff(uuid,uuid,uuid,uuid[],time,integer) from public,anon,authenticated;
grant execute on function public.set_branch_business_day_cutoff(uuid,uuid,uuid,uuid[],time,integer) to service_role;
revoke all on function public.get_branch_business_day_cutoff(uuid,uuid,uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.get_branch_business_day_cutoff(uuid,uuid,uuid,uuid[]) to service_role;
commit;
