-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Generated from the live staging schema inspection on 2026-11-28.
-- Do not apply until disposable replay, RLS/ACL review, and explicit staging approval.
-- Source-of-truth tables remain POS, refunds, settlements, Finance journals and domain entities.

begin;

-- A branch's local business date must be deterministic and configurable.
alter table public.branches
  add column if not exists business_day_cutoff time without time zone not null default time '00:00';

create table if not exists public.executive_sales_kpi_definitions (
  id uuid primary key default gen_random_uuid(),
  metric_key text not null,
  version text not null,
  display_name text not null,
  formula text not null,
  source_entities text[] not null,
  effective_from date not null,
  effective_to date,
  immutable boolean not null default true,
  created_at timestamptz not null default now(),
  unique(metric_key,version),
  check(effective_to is null or effective_to>=effective_from)
);
insert into public.executive_sales_kpi_definitions
(metric_key,version,display_name,formula,source_entities,effective_from)
values
('sales_net','sales-net-v1','Net sales','SUM(pos_sales.total_idr) - SUM(processed refund_records.amount_idr)',
 array['pos_sales','pos_sale_items','refund_records','payment_settlement_items','payment_settlements','finance_journal_entries'],
 date '2026-11-28')
on conflict(metric_key,version) do nothing;

create or replace function public.prevent_executive_sales_kpi_definition_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$ begin raise exception 'executive_sales_kpi_definition_is_immutable'; end $$;
drop trigger if exists executive_sales_kpi_definitions_immutable on public.executive_sales_kpi_definitions;
create trigger executive_sales_kpi_definitions_immutable
before update or delete on public.executive_sales_kpi_definitions
for each row execute function public.prevent_executive_sales_kpi_definition_mutation();

-- Read-only fact view: tenant comes from the trusted branch FK, not the browser.
-- Gross is the POS subtotal, discount is explicit, net is POS total less processed refunds.
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
  coalesce(j.journal_entry_ids,'[]'::jsonb) as finance_journal_entry_ids
from public.pos_sales s
join public.branches b on b.id=s.branch_id
left join lateral (
  select sum(rr.amount_idr)::bigint as refund_idr
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
  select count(*)::bigint as journal_entry_count,
         coalesce(jsonb_agg(jsonb_build_object('id',fje.id,'source_type',fje.source_type,'amount_idr',fje.amount_idr,'status',fje.status)
           order by fje.created_at),'[]'::jsonb) as journal_entry_ids
  from public.finance_journal_entries fje
  where fje.source_id=s.id
) j on true
where s.payment_status in ('paid','refunded');

create table if not exists public.executive_sales_kpi_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  metric_key text not null,
  formula_version text not null,
  period_type text not null check(period_type in ('day','week','month','custom')),
  period_start date not null,
  period_end date not null,
  branch_ids uuid[] not null,
  totals jsonb not null check(jsonb_typeof(totals)='object'),
  daily jsonb not null check(jsonb_typeof(daily)='array'),
  transactions jsonb not null check(jsonb_typeof(transactions)='array'),
  finance_reconciliation jsonb not null check(jsonb_typeof(finance_reconciliation)='object'),
  source_sale_count integer not null check(source_sale_count>=0),
  generated_at timestamptz not null default now(),
  unique(tenant_id,id),
  check(period_end>=period_start)
);
create index if not exists executive_sales_kpi_snapshots_lookup_idx
on public.executive_sales_kpi_snapshots(tenant_id,period_start,period_end,generated_at desc);

alter table public.executive_sales_kpi_definitions enable row level security;
alter table public.executive_sales_kpi_snapshots enable row level security;
alter table public.executive_sales_kpi_definitions force row level security;
alter table public.executive_sales_kpi_snapshots force row level security;
drop policy if exists service_role_only on public.executive_sales_kpi_definitions;
create policy service_role_only on public.executive_sales_kpi_definitions for all to service_role using(true) with check(true);
drop policy if exists service_role_only on public.executive_sales_kpi_snapshots;
create policy service_role_only on public.executive_sales_kpi_snapshots for all to service_role using(true) with check(true);
revoke all on public.executive_sales_kpi_definitions,public.executive_sales_kpi_snapshots from public,anon,authenticated;
grant select on public.executive_sales_kpi_definitions to service_role;
grant select,insert on public.executive_sales_kpi_snapshots to service_role;
revoke all on public.executive_pos_sales_fact from public,anon,authenticated;
grant select on public.executive_pos_sales_fact to service_role;

create or replace function public.executive_sales_monitor_snapshot(
 p_actor_user_id uuid,
 p_tenant_id uuid,
 p_branch_ids uuid[],
 p_period_type text,
 p_period_start date,
 p_period_end date
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
 v_role text;
 v_platform_owner boolean:=false;
 v_allowed uuid[];
 v_requested uuid[];
 v_rows jsonb;
 v_daily jsonb;
 v_totals jsonb;
 v_finance jsonb;
 v_snapshot_id uuid;
 v_count integer;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then
  raise exception using errcode='42501',message='EXECUTIVE_SERVICE_ROLE_REQUIRED';
 end if;
 if p_actor_user_id is null or p_tenant_id is null or p_period_start is null or p_period_end is null
   or p_period_end<p_period_start or p_period_type not in ('day','week','month','custom') then
  raise exception using errcode='22023',message='EXECUTIVE_SALES_INPUT_INVALID';
 end if;
 select role into v_role from public.tenant_memberships
 where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if not found then raise exception using errcode='42501',message='EXECUTIVE_TENANT_MEMBERSHIP_REQUIRED'; end if;
 select coalesce(jsonb_typeof(u.raw_app_meta_data->'platform_owner')='boolean'
   and (u.raw_app_meta_data->>'platform_owner')::boolean,false)
 into v_platform_owner from auth.users u where u.id=p_actor_user_id;
 if not exists(select 1 from public.admin_profiles ap where ap.user_id=p_actor_user_id and ap.is_active=true) then
  raise exception using errcode='42501',message='EXECUTIVE_ACTIVE_PROFILE_REQUIRED';
 end if;
 if v_role in ('tenant_owner','tenant_admin','group_hq','head_ops') or v_platform_owner then
  select coalesce(array_agg(b.id order by b.code),'{}'::uuid[]) into v_allowed
  from public.branches b where b.tenant_id=p_tenant_id;
 else
  select coalesce(array_agg(distinct b.id order by b.id),'{}'::uuid[]) into v_allowed
  from public.branches b join public.branch_assignments ba on ba.branch_id=b.id
  where b.tenant_id=p_tenant_id and ba.user_id=p_actor_user_id and ba.employment_status='active'
    and ba.starts_on<=current_date and (ba.ends_on is null or ba.ends_on>=current_date);
 end if;
 v_requested:=case when coalesce(cardinality(p_branch_ids),0)=0 then v_allowed else p_branch_ids end;
 if cardinality(v_requested)=0 or not (v_requested <@ v_allowed) then
  raise exception using errcode='42501',message='EXECUTIVE_BRANCH_SCOPE_DENIED';
 end if;
 if exists(select 1 from unnest(v_requested) x group by x having count(*)>1) then
  raise exception using errcode='22023',message='EXECUTIVE_BRANCH_DUPLICATE';
 end if;

 select coalesce(jsonb_agg(to_jsonb(f) order by f.business_date,f.created_at,f.sale_id),'[]'::jsonb),count(*)
 into v_rows,v_count
 from public.executive_pos_sales_fact f
 where f.tenant_id=p_tenant_id and f.branch_id=any(v_requested)
   and f.business_date between p_period_start and p_period_end;

 select coalesce(jsonb_agg(jsonb_build_object(
   'business_date',d.business_date,'gross_idr',d.gross_idr,'discount_idr',d.discount_idr,
   'refund_idr',d.refund_idr,'net_sales_idr',d.net_sales_idr,'matched_settlement_idr',d.matched_settlement_idr,
   'transaction_count',d.transaction_count) order by d.business_date),'[]'::jsonb)
 into v_daily
 from (
  select business_date,sum(gross_idr)::bigint gross_idr,sum(discount_idr)::bigint discount_idr,
   sum(processed_refund_idr)::bigint refund_idr,sum(net_sales_idr)::bigint net_sales_idr,
   sum(matched_settlement_idr)::bigint matched_settlement_idr,count(*)::integer transaction_count
  from public.executive_pos_sales_fact
  where tenant_id=p_tenant_id and branch_id=any(v_requested)
    and business_date between p_period_start and p_period_end
  group by business_date
 ) d;

 select jsonb_build_object(
   'gross_idr',coalesce(sum(gross_idr),0),
   'discount_idr',coalesce(sum(discount_idr),0),
   'refund_idr',coalesce(sum(processed_refund_idr),0),
   'net_sales_idr',coalesce(sum(net_sales_idr),0),
   'matched_settlement_idr',coalesce(sum(matched_settlement_idr),0),
   'transaction_count',count(*)
 ) into v_totals
 from public.executive_pos_sales_fact
 where tenant_id=p_tenant_id and branch_id=any(v_requested)
   and business_date between p_period_start and p_period_end;

 select jsonb_build_object(
   'sale_count',count(*),
   'sale_without_journal_count',count(*) filter(where finance_journal_entry_count=0),
   'linked_journal_entry_count',coalesce(sum(finance_journal_entry_count),0),
   'settlement_allocated_idr',coalesce(sum(matched_settlement_idr),0),
   'status',case when count(*)=0 then 'no_transactions'
      when count(*) filter(where finance_journal_entry_count=0)>0 then 'journal_gaps'
      else 'journal_links_present' end
 ) into v_finance
 from public.executive_pos_sales_fact
 where tenant_id=p_tenant_id and branch_id=any(v_requested)
   and business_date between p_period_start and p_period_end;

 insert into public.executive_sales_kpi_snapshots
 (tenant_id,actor_user_id,metric_key,formula_version,period_type,period_start,period_end,branch_ids,totals,daily,transactions,finance_reconciliation,source_sale_count)
 values(p_tenant_id,p_actor_user_id,'sales_net','sales-net-v1',p_period_type,p_period_start,p_period_end,v_requested,v_totals,v_daily,v_rows,v_finance,v_count)
 returning id into v_snapshot_id;

 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.sales.snapshot_created','executive_sales_kpi_snapshot',v_snapshot_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_ids',v_requested,'period_type',p_period_type,
   'period_start',p_period_start,'period_end',p_period_end,'source_sale_count',v_count,'formula_version','sales-net-v1'));

 return jsonb_build_object('snapshot_id',v_snapshot_id,'tenant_id',p_tenant_id,'period_type',p_period_type,
  'period_start',p_period_start,'period_end',p_period_end,'branch_ids',v_requested,'totals',v_totals,
  'daily',v_daily,'transactions',v_rows,'finance_reconciliation',v_finance,
  'formula_version','sales-net-v1','source_sale_count',v_count,'generated_at',now());
end $$;
revoke all on function public.executive_sales_monitor_snapshot(uuid,uuid,uuid[],text,date,date) from public,anon,authenticated;
grant execute on function public.executive_sales_monitor_snapshot(uuid,uuid,uuid[],text,date,date) to service_role;

-- Approval source inbox is a projection; it never replaces the state of the source entity.
create table if not exists public.executive_approval_policies (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 category text not null check(category in ('procurement','finance','hr','branch_ops')),
 required_role text not null,
 max_amount_idr bigint not null default 0 check(max_amount_idr>=0),
 self_approval_allowed boolean not null default false,
 expiry_minutes integer not null default 1440 check(expiry_minutes between 1 and 10080),
 status text not null default 'draft' check(status in ('draft','active','retired')),
 created_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 approved_at timestamptz,
 unique(tenant_id,id),
 check(approved_by is null or approved_by<>created_by),
 check(status<>'active' or (approved_by is not null and approved_at is not null))
);
create table if not exists public.executive_approval_delegations (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 delegator_user_id uuid not null references auth.users(id) on delete restrict,
 delegate_user_id uuid not null references auth.users(id) on delete restrict,
 category text not null check(category in ('procurement','finance','hr','branch_ops')),
 branch_id uuid,
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 status text not null default 'pending' check(status in ('pending','active','revoked','expired')),
 created_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,id),
 check(delegator_user_id<>delegate_user_id),
 check(ends_at>starts_at),
 check(approved_by is null or approved_by<>created_by),
 check(status<>'active' or approved_by is not null)
);
create table if not exists public.executive_approval_inbox (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 source_domain text not null check(source_domain in ('procurement','finance','hr','branch_ops')),
 source_entity text not null,
 source_entity_id uuid not null,
 branch_id uuid not null,
 category text not null check(category in ('procurement','finance','hr','branch_ops')),
 amount_idr bigint not null default 0 check(amount_idr>=0),
 created_by uuid not null references auth.users(id) on delete restrict,
 source_version bigint not null,
 status text not null default 'pending' check(status in ('pending','claimed','decided','expired','cancelled')),
 claimed_by uuid references auth.users(id) on delete restrict,
 claim_expires_at timestamptz,
 expires_at timestamptz not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,source_entity,source_entity_id),
 unique(tenant_id,id),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists executive_approval_queue_idx
 on public.executive_approval_inbox(tenant_id,status,expires_at,amount_idr desc);
create table if not exists public.executive_approval_decisions (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null,
 approval_id uuid not null,
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 decision text not null check(decision in ('approve','reject')),
 reason text not null check(length(btrim(reason))>=8),
 source_version_before bigint not null,
 source_version_after bigint not null,
 created_at timestamptz not null default now(),
 foreign key(tenant_id,approval_id) references public.executive_approval_inbox(tenant_id,id) on delete restrict,
 unique(tenant_id,approval_id)
);

do $$ declare t text; begin
 foreach t in array array['executive_approval_policies','executive_approval_delegations','executive_approval_inbox','executive_approval_decisions'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('alter table public.%I force row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update on public.%I to service_role',t);
 end loop;
end $$;

-- Pending sources are read live from the source entities; the inbox row is only a claim/decision envelope.
create or replace view public.executive_pending_approval_sources
with (security_invoker=true) as
select b.tenant_id,'procurement'::text source_domain,'purchase_requisition'::text source_entity,
 pr.id source_entity_id,pr.branch_id,'procurement'::text category,pr.estimated_total_idr amount_idr,
 pr.requested_by created_by,(extract(epoch from pr.updated_at)*1000)::bigint source_version,pr.updated_at source_updated_at
from public.purchase_requisitions pr join public.branches b on b.id=pr.branch_id
where pr.status='submitted'
union all
select b.tenant_id,'procurement','purchase_order',po.id,po.branch_id,'procurement',po.subtotal_idr,po.requested_by,
 (extract(epoch from po.updated_at)*1000)::bigint,po.updated_at
from public.purchase_orders po join public.branches b on b.id=po.branch_id
where po.status='submitted'
union all
select pr.tenant_id,'hr','hr_payroll_run',pr.id,pr.branch_id,'hr',pr.net_amount_idr,pr.created_by,
 (extract(epoch from pr.updated_at)*1000)::bigint,pr.updated_at
from public.hr_payroll_runs pr where pr.status='submitted';

revoke all on public.executive_pending_approval_sources from public,anon,authenticated;
grant select on public.executive_pending_approval_sources to service_role;

-- list_pending_approvals, claim_approval and decide_approval are implemented as service-only
-- RPCs after the source-domain adapters are finalized; do not expose direct writes to the projection.

rollback;
