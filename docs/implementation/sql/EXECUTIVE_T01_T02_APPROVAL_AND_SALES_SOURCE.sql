-- REVIEW-ONLY migration source for Executive T01/T02.
-- Target: staging project higoadrzxnhzbbwhdbmh, feature branch only.
-- Do not apply until disposable replay, ACL review, advisors, and explicit approval.
-- Existing paid POS rows are intentionally NOT backfilled: created_at is not proof of paid_at.

begin;

-- Purchase orders need an explicit rejected terminal state; cancellation remains separate.
alter table public.purchase_orders drop constraint if exists purchase_orders_status_check;
alter table public.purchase_orders add constraint purchase_orders_status_check
  check(status = any(array['draft','submitted','approved','rejected','ordered','partially_received','received','cancelled']::text[]));

-- T01: capture actual server-side paid transition and branch-local business date.
alter table public.pos_sales
  add column if not exists paid_at timestamptz,
  add column if not exists business_date date,
  add column if not exists business_timezone text;

create or replace function public.set_pos_sale_business_time()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_timezone text;
  v_newly_paid boolean;
begin
  select b.timezone into v_timezone
  from public.branches b
  where b.id = new.branch_id;
  if v_timezone is null or v_timezone not in ('Asia/Jakarta','Asia/Makassar','Asia/Jayapura') then
    raise exception using errcode='22023', message='POS_BRANCH_TIMEZONE_INVALID';
  end if;

  v_newly_paid := new.payment_status = 'paid' and
    (tg_op = 'INSERT' or old.payment_status is distinct from 'paid');

  if tg_op = 'UPDATE' and old.payment_status = 'paid' and
     (old.branch_id is distinct from new.branch_id) then
    raise exception using errcode='23514', message='PAID_POS_SALE_BRANCH_IMMUTABLE';
  end if;
  if tg_op = 'UPDATE' and old.payment_status = 'paid' and new.payment_status <> 'paid' then
    raise exception using errcode='23514', message='PAID_POS_SALE_STATUS_IMMUTABLE';
  end if;

  if v_newly_paid then
    new.paid_at := now();
    new.business_timezone := v_timezone;
    new.business_date := (new.paid_at at time zone v_timezone)::date;
  elsif tg_op = 'UPDATE' and old.payment_status = 'paid' then
    -- Preserve the original recognition instant and timezone for historical stability.
    new.paid_at := old.paid_at;
    new.business_timezone := old.business_timezone;
    new.business_date := old.business_date;
  elsif new.payment_status <> 'paid' then
    new.paid_at := null;
    new.business_date := null;
    new.business_timezone := null;
  end if;
  return new;
end;
$$;

drop trigger if exists pos_sales_set_business_time on public.pos_sales;
create trigger pos_sales_set_business_time
before insert or update of payment_status, branch_id on public.pos_sales
for each row execute function public.set_pos_sale_business_time();
revoke all on function public.set_pos_sale_business_time() from public, anon, authenticated;

create index if not exists pos_sales_branch_business_date_idx
  on public.pos_sales(branch_id,business_date,id) where payment_status='paid';
create index if not exists pos_sales_branch_paid_at_idx
  on public.pos_sales(branch_id,paid_at,id) where payment_status='paid';

create table if not exists public.executive_kpi_definitions (
  id uuid primary key default gen_random_uuid(),
  metric_key text not null,
  version text not null,
  definition jsonb not null check(jsonb_typeof(definition)='object'),
  effective_from timestamptz not null,
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete restrict,
  unique(metric_key,version),
  check(effective_to is null or effective_to>effective_from)
);
alter table public.executive_kpi_definitions enable row level security;
drop policy if exists service_role_only on public.executive_kpi_definitions;
create policy service_role_only on public.executive_kpi_definitions
  for all to service_role using(true) with check(true);
revoke all on public.executive_kpi_definitions from public,anon,authenticated;
grant select,insert,update on public.executive_kpi_definitions to service_role;

insert into public.executive_kpi_definitions(metric_key,version,definition,effective_from)
values('pos_sales','sales-monitor.v2',
 jsonb_build_object(
  'recognition','business_date then paid_at branch timezone; legacy created_at is uncertified',
  'gross','sum(pos_sales.subtotal_idr) for paid sales in branch business-date window',
  'discount','sum(pos_sales.discount_idr) for same sales',
  'sales_net_before_refunds','sum(pos_sales.total_idr)',
  'refunds','sum processed refund_records.amount_idr by processed_at in same branch-local window',
  'net_sales','sales_net_before_refunds minus processed refunds',
  'settlement','separate cash reconciliation; never substituted for sales revenue',
  'timezone','branches.timezone snapshot at payment recognition',
  'window','half-open local calendar period converted to UTC'
 ),now())
on conflict(metric_key,version) do nothing;

create or replace view public.executive_sales_source_v
with (security_invoker=true)
as
select s.id as sale_id,s.transaction_code,s.branch_id,b.tenant_id,b.timezone as current_branch_timezone,
       s.business_timezone,s.business_date,s.paid_at,s.created_at,s.payment_status,
       s.subtotal_idr,s.discount_idr,s.total_idr
from public.pos_sales s
join public.branches b on b.id=s.branch_id;

revoke all on public.executive_sales_source_v from public,anon,authenticated;
grant select on public.executive_sales_source_v to service_role;

-- Read-only per-sale reconciliation: settlement allocation and Finance journal remain
-- separate dimensions. A missing settlement/journal is visible as zero rows, not inferred as paid.
create or replace view public.executive_sales_reconciliation_v
with (security_invoker=true)
as
with settlement_tenant_totals as (
  select i.settlement_id,
         sum(i.amount_idr)::bigint as allocated_gross_idr,
         count(distinct b.tenant_id)::integer as tenant_count
  from public.payment_settlement_items i
  join public.pos_sales psale on psale.id=i.pos_sale_id
  join public.branches b on b.id=psale.branch_id
  group by i.settlement_id
),
settlement_allocation_base as (
  select i.id as settlement_item_id,i.pos_sale_id,i.settlement_id,
         ps.net_amount_idr,
         floor(i.amount_idr::numeric*ps.net_amount_idr/ps.gross_amount_idr)::bigint as base_net_idr,
         row_number() over(partition by i.settlement_id order by i.id) as allocation_order,
         sum(floor(i.amount_idr::numeric*ps.net_amount_idr/ps.gross_amount_idr))
           over(partition by i.settlement_id) as base_net_total_idr,
         st.allocated_gross_idr,st.tenant_count,ps.gross_amount_idr
  from public.payment_settlement_items i
  join public.payment_settlements ps on ps.id=i.settlement_id
  join settlement_tenant_totals st on st.settlement_id=i.settlement_id
  where ps.status='reconciled' and ps.net_amount_idr is not null
    and ps.gross_amount_idr>0 and st.tenant_count=1
    and st.allocated_gross_idr=ps.gross_amount_idr
),
settlement_allocations as (
  select settlement_item_id,pos_sale_id,
         (base_net_idr + case
           when allocation_order <= (net_amount_idr-base_net_total_idr) then 1 else 0
          end)::bigint as allocated_net_idr
  from settlement_allocation_base
),
settlement_by_sale as (
  select i.pos_sale_id,
         sum(i.amount_idr)::bigint as allocated_gross_idr,
         sum(sa.allocated_net_idr)::bigint as allocated_net_idr,
         count(*) filter(where ps.status='reconciled')::integer as reconciled_settlement_count
  from public.payment_settlement_items i
  join public.payment_settlements ps on ps.id=i.settlement_id
  left join settlement_allocations sa on sa.settlement_item_id=i.id
  group by i.pos_sale_id
)
select s.sale_id,s.transaction_code,s.tenant_id,s.branch_id,s.business_date,s.paid_at,
       s.subtotal_idr,s.discount_idr,s.total_idr,
       coalesce(r.refund_total_idr,0)::bigint as processed_refund_total_idr,
       coalesce(st.allocated_gross_idr,0)::bigint as settlement_allocated_gross_idr,
       st.allocated_net_idr as settlement_allocated_net_idr,
       coalesce(st.reconciled_settlement_count,0)::integer as reconciled_settlement_count,
       coalesce(j.posted_journal_total_idr,0)::bigint as posted_journal_total_idr,
       coalesce(j.posted_journal_count,0)::integer as posted_journal_count
from public.executive_sales_source_v s
left join lateral (
  select sum(rr.amount_idr)::bigint as refund_total_idr
  from public.refund_records rr
  where rr.pos_sale_id=s.sale_id and rr.branch_id=s.branch_id and rr.status='processed'
) r on true
left join settlement_by_sale st on st.pos_sale_id=s.sale_id
left join lateral (
  select sum(j.amount_idr)::bigint as posted_journal_total_idr,count(*)::integer as posted_journal_count
  from public.finance_journal_entries j
  where j.source_id=s.sale_id and j.branch_id=s.branch_id and j.status='posted'
) j on true
where s.payment_status='paid';

revoke all on public.executive_sales_reconciliation_v from public,anon,authenticated;
grant select on public.executive_sales_reconciliation_v to service_role;

-- Give legacy branch expenses an optimistic source timestamp so resubmission cannot
-- collide with an earlier approval attempt.
alter table public.branch_expenses
  add column if not exists updated_at timestamptz not null default now();
create or replace function public.touch_approval_source_updated_at()
returns trigger language plpgsql security invoker set search_path=''
as $$ begin new.updated_at:=now(); return new; end; $$;
drop trigger if exists branch_expenses_touch_updated_at on public.branch_expenses;
drop trigger if exists purchase_requisitions_touch_updated_at on public.purchase_requisitions;
drop trigger if exists purchase_orders_touch_updated_at on public.purchase_orders;
drop trigger if exists hr_timesheets_touch_updated_at on public.hr_timesheets;
create trigger branch_expenses_touch_updated_at before update on public.branch_expenses
for each row execute function public.touch_approval_source_updated_at();
create trigger purchase_requisitions_touch_updated_at before update on public.purchase_requisitions
for each row execute function public.touch_approval_source_updated_at();
create trigger purchase_orders_touch_updated_at before update on public.purchase_orders
for each row execute function public.touch_approval_source_updated_at();
create trigger hr_timesheets_touch_updated_at before update on public.hr_timesheets
for each row execute function public.touch_approval_source_updated_at();
revoke all on function public.touch_approval_source_updated_at() from public,anon,authenticated;

-- T02: approval policy and inbox are references to source entities, not replacement statuses.
create table if not exists public.approval_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  domain text not null check(domain in ('procurement','finance','hr','branch_ops')),
  source_entity_type text not null check(source_entity_type in ('purchase_requisition','purchase_order','branch_expense','hr_timesheet')),
  eligible_roles text[] not null check(cardinality(eligible_roles)>0),
  allowed_categories text[] not null default array['*']::text[] check(cardinality(allowed_categories)>0),
  max_amount_idr bigint not null default 1000000000 check(max_amount_idr>=0),
  separation_of_duties boolean not null default true,
  claim_ttl_minutes integer not null default 10 check(claim_ttl_minutes between 1 and 120),
  approval_ttl_hours integer not null default 72 check(approval_ttl_hours between 1 and 720),
  active boolean not null default true,
  policy_version integer not null default 1 check(policy_version>0),
  created_at timestamptz not null default now(),
  unique(tenant_id,source_entity_type,policy_version)
);

create table if not exists public.approval_inbox_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  domain text not null check(domain in ('procurement','finance','hr','branch_ops')),
  category text not null,
  source_entity_type text not null check(source_entity_type in ('purchase_requisition','purchase_order','branch_expense','hr_timesheet')),
  source_entity_id uuid not null,
  source_version timestamptz not null,
  policy_id uuid not null references public.approval_policies(id) on delete restrict,
  policy_version integer not null,
  amount_idr bigint not null default 0 check(amount_idr>=0),
  created_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'pending' check(status in ('pending','claimed','approved','rejected','expired','stale')),
  urgency text not null default 'normal' check(urgency in ('critical','high','normal','low')),
  evidence jsonb not null default '[]'::jsonb check(jsonb_typeof(evidence)='array'),
  version integer not null default 1 check(version>0),
  claimed_by uuid references auth.users(id) on delete restrict,
  delegated_from uuid references auth.users(id) on delete restrict,
  claim_expires_at timestamptz,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,source_entity_type,source_entity_id,source_version),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists approval_inbox_queue_idx
  on public.approval_inbox_items(tenant_id,branch_id,status,expires_at,created_at desc);
create index if not exists approval_inbox_source_idx
  on public.approval_inbox_items(tenant_id,source_entity_type,source_entity_id);

create table if not exists public.approval_delegations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  delegator_user_id uuid not null references auth.users(id) on delete restrict,
  delegate_user_id uuid not null references auth.users(id) on delete restrict,
  domain text not null check(domain in ('procurement','finance','hr','branch_ops')),
  branch_id uuid not null,
  category text,
  max_amount_idr bigint not null check(max_amount_idr>=0),
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check(delegator_user_id<>delegate_user_id),
  check(expires_at>starts_at)
);
create index if not exists approval_delegations_active_idx
  on public.approval_delegations(tenant_id,delegate_user_id,domain,branch_id,expires_at)
  where revoked_at is null;
create unique index if not exists approval_delegations_active_unique_idx
  on public.approval_delegations(tenant_id,delegator_user_id,delegate_user_id,domain,branch_id,(coalesce(category,'')))
  where revoked_at is null;

create table if not exists public.approval_claim_events (
  id uuid primary key default gen_random_uuid(),
  approval_id uuid not null references public.approval_inbox_items(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null check(event_type in ('claimed','released','expired')),
  version integer not null,
  created_at timestamptz not null default now()
);
create table if not exists public.approval_decisions (
  id uuid primary key default gen_random_uuid(),
  approval_id uuid not null references public.approval_inbox_items(id) on delete restrict,
  idempotency_key text not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  decision text not null check(decision in ('approved','rejected')),
  reason text not null check(length(btrim(reason))>=8),
  source_entity_type text not null,
  source_entity_id uuid not null,
  source_version timestamptz not null,
  policy_version integer not null,
  created_at timestamptz not null default now(),
  unique(approval_id,idempotency_key),
  unique(approval_id)
);

do $$
declare t text;
begin
  foreach t in array array['approval_policies','approval_inbox_items','approval_delegations','approval_claim_events','approval_decisions'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $;
-- Decision and claim event history is append-only, including for service-role RPC callers.
revoke update,delete on public.approval_claim_events,public.approval_decisions from service_role;
grant select,insert on public.approval_claim_events,public.approval_decisions to service_role;

-- Seed conservative tenant-owner-only policies; expand roles only through a reviewed policy change.
insert into public.approval_policies(tenant_id,domain,source_entity_type,eligible_roles,max_amount_idr)
select t.id,src.domain,src.entity_type,array['owner']::text[],1000000000
from public.tenants t
cross join (values
 ('procurement','purchase_requisition'),
 ('procurement','purchase_order'),
 ('finance','branch_expense'),
 ('hr','hr_timesheet')
) as src(domain,entity_type)
on conflict(tenant_id,source_entity_type,policy_version) do nothing;

create or replace function public.seed_approval_policies_for_tenant()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
 insert into public.approval_policies(tenant_id,domain,source_entity_type,eligible_roles,max_amount_idr)
 values
  (new.id,'procurement','purchase_requisition',array['owner']::text[],1000000000),
  (new.id,'procurement','purchase_order',array['owner']::text[],1000000000),
  (new.id,'finance','branch_expense',array['owner']::text[],1000000000),
  (new.id,'hr','hr_timesheet',array['owner']::text[],1000000000)
 on conflict(tenant_id,source_entity_type,policy_version) do nothing;
 return new;
end;
$$;
drop trigger if exists tenants_seed_approval_policies on public.tenants;
create trigger tenants_seed_approval_policies after insert on public.tenants
for each row execute function public.seed_approval_policies_for_tenant();
revoke all on function public.seed_approval_policies_for_tenant() from public,anon,authenticated;

-- The trigger only creates a pending inbox reference; source status remains authoritative.
create or replace function public.enqueue_approval_source()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_row jsonb := to_jsonb(new);
  v_branch uuid;
  v_tenant uuid;
  v_source_id uuid;
  v_creator uuid;
  v_amount bigint := 0;
  v_status text;
  v_version timestamptz;
  v_domain text;
  v_entity text := tg_table_name;
  v_category text;
  v_policy public.approval_policies%rowtype;
begin
  v_source_id := (v_row->>'id')::uuid;
  v_branch := (v_row->>'branch_id')::uuid;
  v_status := v_row->>'status';
  v_creator := coalesce((v_row->>'created_by')::uuid,(v_row->>'requested_by')::uuid);
  v_version := coalesce((v_row->>'updated_at')::timestamptz,(v_row->>'created_at')::timestamptz,now());
  if v_entity='purchase_requisitions' then
    v_entity:='purchase_requisition'; v_domain:='procurement';
    v_amount:=coalesce((v_row->>'estimated_total_idr')::bigint,0);
    v_category:=coalesce(v_row->>'purpose','purchase');
    if v_status<>'submitted' then return new; end if;
  elsif v_entity='purchase_orders' then
    v_entity:='purchase_order'; v_domain:='procurement';
    v_amount:=coalesce((v_row->>'subtotal_idr')::bigint,0);
    v_category:='purchase_order';
    if v_status<>'submitted' then return new; end if;
  elsif v_entity='branch_expenses' then
    v_entity:='branch_expense'; v_domain:='finance';
    v_amount:=coalesce((v_row->>'amount_idr')::bigint,0);
    v_category:=coalesce(v_row->>'category','expense');
    if v_status<>'pending_approval' then return new; end if;
  elsif v_entity='hr_timesheets' then
    v_entity:='hr_timesheet'; v_domain:='hr';
    v_amount:=0; v_category:='timesheet';
    if v_status<>'submitted' then return new; end if;
  else
    return new;
  end if;
  select b.tenant_id into v_tenant from public.branches b where b.id=v_branch;
  if v_tenant is null or v_creator is null then
    raise exception using errcode='23503',message='APPROVAL_SOURCE_SCOPE_INVALID';
  end if;
  select * into v_policy from public.approval_policies p
   where p.tenant_id=v_tenant and p.source_entity_type=v_entity and p.active
   order by p.policy_version desc limit 1;
  if not found then
    raise exception using errcode='23514',message='APPROVAL_POLICY_MISSING';
  end if;
  update public.approval_inbox_items
    set status='stale',version=version+1,updated_at=now()
    where tenant_id=v_tenant and source_entity_type=v_entity and source_entity_id=v_source_id
      and source_version<>v_version and status in ('pending','claimed');
  insert into public.approval_inbox_items(
    tenant_id,branch_id,domain,category,source_entity_type,source_entity_id,source_version,
    policy_id,policy_version,amount_idr,created_by,expires_at,evidence
  ) values(
    v_tenant,v_branch,v_domain,v_category,v_entity,v_source_id,v_version,
    v_policy.id,v_policy.policy_version,v_amount,v_creator,
    now()+make_interval(hours=>v_policy.approval_ttl_hours),
    jsonb_build_array(jsonb_build_object('source_table',tg_table_name,'source_id',v_source_id))
  ) on conflict(tenant_id,source_entity_type,source_entity_id,source_version) do nothing;
  return new;
end;
$$;
revoke all on function public.enqueue_approval_source() from public,anon,authenticated;

drop trigger if exists approval_enqueue_purchase_requisitions on public.purchase_requisitions;
create trigger approval_enqueue_purchase_requisitions after insert or update on public.purchase_requisitions
for each row execute function public.enqueue_approval_source();
drop trigger if exists approval_enqueue_purchase_orders on public.purchase_orders;
create trigger approval_enqueue_purchase_orders after insert or update on public.purchase_orders
for each row execute function public.enqueue_approval_source();
drop trigger if exists approval_enqueue_branch_expenses on public.branch_expenses;
create trigger approval_enqueue_branch_expenses after insert or update on public.branch_expenses
for each row execute function public.enqueue_approval_source();
drop trigger if exists approval_enqueue_hr_timesheets on public.hr_timesheets;
create trigger approval_enqueue_hr_timesheets after insert or update on public.hr_timesheets
for each row execute function public.enqueue_approval_source();

-- Backfill currently pending source entities into the read model without changing source status.
insert into public.approval_inbox_items(
 tenant_id,branch_id,domain,category,source_entity_type,source_entity_id,source_version,
 policy_id,policy_version,amount_idr,created_by,expires_at,evidence
)
select src.tenant_id,src.branch_id,src.domain,src.category,src.entity_type,src.entity_id,src.source_version,
 p.id,p.policy_version,src.amount_idr,src.created_by,now()+make_interval(hours=>p.approval_ttl_hours),
 jsonb_build_array(jsonb_build_object('source_table',src.source_table,'source_id',src.entity_id))
from (
 select b.tenant_id,r.branch_id,'procurement'::text as domain,coalesce(r.purpose,'purchase') as category,
  'purchase_requisition'::text as entity_type,r.id as entity_id,r.updated_at as source_version,
  r.estimated_total_idr as amount_idr,r.requested_by as created_by,'purchase_requisitions'::text as source_table
 from public.purchase_requisitions r join public.branches b on b.id=r.branch_id where r.status='submitted'
 union all
 select b.tenant_id,o.branch_id,'procurement','purchase_order','purchase_order',o.id,o.updated_at,
  o.subtotal_idr,o.requested_by,'purchase_orders'
 from public.purchase_orders o join public.branches b on b.id=o.branch_id where o.status='submitted'
 union all
 select b.tenant_id,e.branch_id,'finance',coalesce(e.category,'expense'),'branch_expense',e.id,e.updated_at,
  e.amount_idr,e.created_by,'branch_expenses'
 from public.branch_expenses e join public.branches b on b.id=e.branch_id where e.status='pending_approval'
 union all
 select t.tenant_id,t.branch_id,'hr','timesheet','hr_timesheet',t.id,t.updated_at,0::bigint,t.created_by,'hr_timesheets'
 from public.hr_timesheets t where t.status='submitted'
) src
join public.approval_policies p on p.tenant_id=src.tenant_id and p.source_entity_type=src.entity_type and p.active
on conflict(tenant_id,source_entity_type,source_entity_id,source_version) do nothing;

-- RPCs are service-role-only and called by the authenticated Edge Function, which
-- derives actor identity and branch scope from the verified JWT. No client scope is trusted.
create or replace function public.approval_source_is_current(p_approval_id uuid)
returns boolean
language plpgsql security invoker set search_path=''
as $$
declare a public.approval_inbox_items%rowtype;
begin
 select * into a from public.approval_inbox_items where id=p_approval_id;
 if not found then return false; end if;
 if a.source_entity_type='purchase_requisition' then
  return exists(select 1 from public.purchase_requisitions r where r.id=a.source_entity_id and r.branch_id=a.branch_id and r.status='submitted' and r.updated_at=a.source_version);
 elsif a.source_entity_type='purchase_order' then
  return exists(select 1 from public.purchase_orders o where o.id=a.source_entity_id and o.branch_id=a.branch_id and o.status='submitted' and o.updated_at=a.source_version);
 elsif a.source_entity_type='branch_expense' then
  return exists(select 1 from public.branch_expenses e where e.id=a.source_entity_id and e.branch_id=a.branch_id and e.status='pending_approval' and e.updated_at=a.source_version);
 elsif a.source_entity_type='hr_timesheet' then
  return exists(select 1 from public.hr_timesheets t where t.id=a.source_entity_id and t.branch_id=a.branch_id and t.status='submitted' and t.updated_at=a.source_version);
 end if;
 return false;
end;
$$;
revoke all on function public.approval_source_is_current(uuid) from public,anon,authenticated;
grant execute on function public.approval_source_is_current(uuid) to service_role;

create or replace function public.list_pending_approvals(
 p_actor_user_id uuid,p_allowed_branch_ids uuid[],p_branch_id uuid default null,
 p_domain text default null,p_category text default null
) returns setof jsonb
language plpgsql security invoker set search_path=''
as $$
declare v_role text; v_active boolean;
begin
 select role,is_active into v_role,v_active from public.admin_profiles where user_id=p_actor_user_id;
 if not found or not v_active then raise exception using errcode='42501',message='APPROVAL_ACTOR_INACTIVE'; end if;
 return query
 select jsonb_build_object(
  'id',a.id,'tenant_id',a.tenant_id,'branch_id',a.branch_id,'domain',a.domain,'category',a.category,
  'source_entity_type',a.source_entity_type,'source_entity_id',a.source_entity_id,
  'source_version',a.source_version,'amount_idr',a.amount_idr,'created_by',a.created_by,
  'status',a.status,'urgency',case when a.expires_at<=now()+interval '6 hours' then 'critical' when a.amount_idr>=100000000 then 'high' else a.urgency end,'evidence',a.evidence,'version',a.version,
  'claimed_by',a.claimed_by,'claim_expires_at',a.claim_expires_at,'expires_at',a.expires_at,
  'created_at',a.created_at,'policy_version',a.policy_version,
  'source_detail',case a.source_entity_type
    when 'purchase_requisition' then (select jsonb_build_object('number',r.requisition_number,'purpose',r.purpose,'notes',r.notes,'needed_by',r.needed_by) from public.purchase_requisitions r where r.id=a.source_entity_id and r.branch_id=a.branch_id)
    when 'purchase_order' then (select jsonb_build_object('number',o.po_number,'supplier_id',o.supplier_id,'notes',o.notes) from public.purchase_orders o where o.id=a.source_entity_id and o.branch_id=a.branch_id)
    when 'branch_expense' then (select jsonb_build_object('code',e.expense_code,'description',e.description,'payment_method',e.payment_method,'receipt_reference',e.receipt_reference) from public.branch_expenses e where e.id=a.source_entity_id and e.branch_id=a.branch_id)
    when 'hr_timesheet' then (select jsonb_build_object('period_start',t.period_start,'period_end',t.period_end,'total_minutes',t.total_minutes,'employee_user_id',t.employee_user_id) from public.hr_timesheets t where t.id=a.source_entity_id and t.branch_id=a.branch_id)
    else null end
 )
 from public.approval_inbox_items a
 join public.approval_policies p on p.id=a.policy_id and p.tenant_id=a.tenant_id and p.active
 where a.status in ('pending','claimed') and a.expires_at>now()
   and a.branch_id=any(coalesce(p_allowed_branch_ids,array[]::uuid[]))
   and (p_branch_id is null or a.branch_id=p_branch_id)
   and (p_domain is null or a.domain=p_domain)
   and (p_category is null or a.category=p_category)
   and (p.allowed_categories @> array['*']::text[] or p.allowed_categories @> array[a.category]::text[])
   and public.approval_source_is_current(a.id)
   and a.amount_idr<=p.max_amount_idr
   and (p.eligible_roles @> array[v_role] or exists(
     select 1 from public.approval_delegations d
     join public.admin_profiles delegator on delegator.user_id=d.delegator_user_id and delegator.is_active
     where d.tenant_id=a.tenant_id and d.delegate_user_id=p_actor_user_id
       and d.delegator_user_id<>a.created_by and d.domain=a.domain and d.branch_id=a.branch_id
       and (d.category is null or d.category=a.category) and d.max_amount_idr>=a.amount_idr
       and d.revoked_at is null and d.starts_at<=now() and d.expires_at>now()
       and p.eligible_roles @> array[delegator.role]
   ))
   and (not p.separation_of_duties or a.created_by<>p_actor_user_id)
   and not (a.source_entity_type='hr_timesheet' and exists(
     select 1 from public.hr_timesheets t where t.id=a.source_entity_id and t.employee_user_id=p_actor_user_id
   ))
 order by case a.urgency when 'critical' then 0 when 'high' then 1 when 'normal' then 2 else 3 end,
          a.amount_idr desc,a.expires_at,a.created_at;
end;
$$;

create or replace function public.claim_approval(
 p_approval_id uuid,p_actor_user_id uuid,p_allowed_branch_ids uuid[],p_expected_version integer
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare a public.approval_inbox_items%rowtype; p public.approval_policies%rowtype;
 v_role text; v_active boolean; v_delegator uuid;
begin
 select * into a from public.approval_inbox_items where id=p_approval_id for update;
 if not found then raise exception using errcode='P0002',message='APPROVAL_NOT_FOUND'; end if;
 if a.version<>p_expected_version then raise exception using errcode='40001',message='APPROVAL_STALE_VERSION'; end if;
 if a.status not in ('pending','claimed') or a.expires_at<=now() then raise exception using errcode='23514',message='APPROVAL_NOT_CLAIMABLE'; end if;
 if not public.approval_source_is_current(a.id) then raise exception using errcode='40001',message='APPROVAL_SOURCE_STALE'; end if;
 if not (a.branch_id=any(coalesce(p_allowed_branch_ids,array[]::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_BRANCH_FORBIDDEN'; end if;
 select role,is_active into v_role,v_active from public.admin_profiles where user_id=p_actor_user_id;
 if not found or not v_active then raise exception using errcode='42501',message='APPROVAL_ACTOR_INACTIVE'; end if;
 select * into p from public.approval_policies where id=a.policy_id and tenant_id=a.tenant_id and active;
 if not found then raise exception using errcode='23514',message='APPROVAL_POLICY_INACTIVE'; end if;
 if p.separation_of_duties and a.created_by=p_actor_user_id then raise exception using errcode='42501',message='APPROVAL_SELF_APPROVAL_FORBIDDEN'; end if;
 if a.source_entity_type='hr_timesheet' and exists(
   select 1 from public.hr_timesheets t where t.id=a.source_entity_id and t.employee_user_id=p_actor_user_id
 ) then raise exception using errcode='42501',message='APPROVAL_EMPLOYEE_SELF_APPROVAL_FORBIDDEN'; end if;
 if not (p.allowed_categories @> array['*']::text[] or p.allowed_categories @> array[a.category]::text[]) then raise exception using errcode='42501',message='APPROVAL_CATEGORY_FORBIDDEN'; end if;
 if a.amount_idr>p.max_amount_idr then raise exception using errcode='42501',message='APPROVAL_AMOUNT_LIMIT_EXCEEDED'; end if;
 if not (p.eligible_roles @> array[v_role]) then
   select d.delegator_user_id into v_delegator from public.approval_delegations d
   join public.admin_profiles dp on dp.user_id=d.delegator_user_id and dp.is_active
   where d.tenant_id=a.tenant_id and d.delegate_user_id=p_actor_user_id and d.domain=a.domain
     and d.branch_id=a.branch_id and (d.category is null or d.category=a.category)
     and d.max_amount_idr>=a.amount_idr and d.delegator_user_id<>a.created_by and d.revoked_at is null and d.starts_at<=now()
     and d.expires_at>now() and p.eligible_roles @> array[dp.role]
   limit 1;
   if v_delegator is null then raise exception using errcode='42501',message='APPROVAL_ROLE_OR_DELEGATION_FORBIDDEN'; end if;
 end if;
 if a.status='claimed' and a.claim_expires_at>now() and a.claimed_by<>p_actor_user_id then
   raise exception using errcode='55P03',message='APPROVAL_ALREADY_CLAIMED';
 end if;
 if a.status='claimed' and a.claim_expires_at>now() and a.claimed_by=p_actor_user_id then
   return jsonb_build_object('approval_id',a.id,'status',a.status,'version',a.version,
     'claimed_by',a.claimed_by,'claim_expires_at',a.claim_expires_at,'delegated_from',a.delegated_from,'duplicate',true);
 end if;
 update public.approval_inbox_items set status='claimed',claimed_by=p_actor_user_id,
   delegated_from=v_delegator,claim_expires_at=now()+make_interval(mins=>p.claim_ttl_minutes),
   version=version+1,updated_at=now() where id=a.id returning * into a;
 insert into public.approval_claim_events(approval_id,actor_user_id,event_type,version)
 values(a.id,p_actor_user_id,'claimed',a.version);
 return jsonb_build_object('approval_id',a.id,'status',a.status,'version',a.version,
   'claimed_by',a.claimed_by,'claim_expires_at',a.claim_expires_at,'delegated_from',a.delegated_from);
end;
$$;

create or replace function public.decide_approval(
 p_approval_id uuid,p_actor_user_id uuid,p_allowed_branch_ids uuid[],p_expected_version integer,
 p_decision text,p_reason text,p_idempotency_key text
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare a public.approval_inbox_items%rowtype; p public.approval_policies%rowtype;
 v_existing_decision public.approval_decisions%rowtype;
 v_role text; v_active boolean; v_updated integer;
begin
 if p_decision not in ('approved','rejected') or length(btrim(coalesce(p_reason,'')))<8
    or length(btrim(coalesce(p_idempotency_key,'')))<16 then
   raise exception using errcode='22023',message='APPROVAL_DECISION_INVALID';
 end if;
 select * into a from public.approval_inbox_items where id=p_approval_id for update;
 if not found then raise exception using errcode='P0002',message='APPROVAL_NOT_FOUND'; end if;
 if not (a.branch_id=any(coalesce(p_allowed_branch_ids,array[]::uuid[]))) then
   raise exception using errcode='42501',message='APPROVAL_BRANCH_FORBIDDEN';
 end if;
 select role,is_active into v_role,v_active from public.admin_profiles where user_id=p_actor_user_id;
 if not found or not v_active then raise exception using errcode='42501',message='APPROVAL_ACTOR_INACTIVE'; end if;
 select * into v_existing_decision from public.approval_decisions
   where approval_id=a.id and idempotency_key=p_idempotency_key;
 if found then
   if v_existing_decision.actor_user_id<>p_actor_user_id then
     raise exception using errcode='42501',message='APPROVAL_IDEMPOTENCY_ACTOR_MISMATCH';
   end if;
   return jsonb_build_object('approval_id',v_existing_decision.approval_id,
     'decision',v_existing_decision.decision,'duplicate',true);
 end if;
 if a.version<>p_expected_version then raise exception using errcode='40001',message='APPROVAL_STALE_VERSION'; end if;
 if a.status<>'claimed' or a.claimed_by<>p_actor_user_id or a.claim_expires_at<=now() or a.expires_at<=now() then
   raise exception using errcode='42501',message='APPROVAL_ACTIVE_CLAIM_REQUIRED';
 end if;
 if not (a.branch_id=any(coalesce(p_allowed_branch_ids,array[]::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_BRANCH_FORBIDDEN'; end if;
 select role,is_active into v_role,v_active from public.admin_profiles where user_id=p_actor_user_id;
 if not found or not v_active then raise exception using errcode='42501',message='APPROVAL_ACTOR_INACTIVE'; end if;
 select * into p from public.approval_policies where id=a.policy_id and tenant_id=a.tenant_id and active;
 if not found or (p.separation_of_duties and a.created_by=p_actor_user_id) or a.amount_idr>p.max_amount_idr or not (p.allowed_categories @> array['*']::text[] or p.allowed_categories @> array[a.category]::text[]) then
   raise exception using errcode='42501',message='APPROVAL_POLICY_OR_SEPARATION_OF_DUTIES_FAILED';
 end if;
 if a.source_entity_type='hr_timesheet' and exists(
   select 1 from public.hr_timesheets t where t.id=a.source_entity_id and t.employee_user_id=p_actor_user_id
 ) then raise exception using errcode='42501',message='APPROVAL_EMPLOYEE_SELF_APPROVAL_FORBIDDEN'; end if;
 if not (p.eligible_roles @> array[v_role]) and a.delegated_from is distinct from (
   select d.delegator_user_id from public.approval_delegations d
   join public.admin_profiles dp on dp.user_id=d.delegator_user_id and dp.is_active
   where d.tenant_id=a.tenant_id and d.delegate_user_id=p_actor_user_id and d.domain=a.domain
    and d.branch_id=a.branch_id and (d.category is null or d.category=a.category)
    and d.max_amount_idr>=a.amount_idr and d.revoked_at is null and d.starts_at<=now()
    and d.expires_at>now() and p.eligible_roles @> array[dp.role] limit 1
 ) then raise exception using errcode='42501',message='APPROVAL_ROLE_OR_DELEGATION_FORBIDDEN'; end if;

 -- Lock and transition only the whitelisted source table, guarded by source_version/status.
 if a.source_entity_type='purchase_requisition' then
   update public.purchase_requisitions set status=p_decision,approved_by=case when p_decision='approved' then p_actor_user_id else approved_by end,
     rejected_by=case when p_decision='rejected' then p_actor_user_id else rejected_by end,
     approved_at=case when p_decision='approved' then now() else approved_at end,
     rejected_at=case when p_decision='rejected' then now() else rejected_at end,updated_at=now()
   where id=a.source_entity_id and branch_id=a.branch_id and status='submitted' and updated_at=a.source_version;
   get diagnostics v_updated=row_count;
 elsif a.source_entity_type='purchase_order' then
   update public.purchase_orders set status=p_decision,
     approved_by=case when p_decision='approved' then p_actor_user_id else approved_by end,updated_at=now()
   where id=a.source_entity_id and branch_id=a.branch_id and status='submitted' and updated_at=a.source_version;
   get diagnostics v_updated=row_count;
 elsif a.source_entity_type='branch_expense' then
   update public.branch_expenses set status=p_decision,reviewed_by=p_actor_user_id,reviewed_at=now()
   where id=a.source_entity_id and branch_id=a.branch_id and status='pending_approval' and updated_at=a.source_version;
   get diagnostics v_updated=row_count;
 elsif a.source_entity_type='hr_timesheet' then
   update public.hr_timesheets set status=p_decision,approved_by=case when p_decision='approved' then p_actor_user_id else null end,
     approved_at=case when p_decision='approved' then now() else null end,updated_at=now()
   where id=a.source_entity_id and branch_id=a.branch_id and status='submitted' and updated_at=a.source_version;
   get diagnostics v_updated=row_count;
 else
   raise exception using errcode='22023',message='APPROVAL_SOURCE_TYPE_UNSUPPORTED';
 end if;
 if v_updated<>1 then raise exception using errcode='40001',message='APPROVAL_SOURCE_STALE_OR_ALREADY_TRANSITIONED'; end if;

 insert into public.approval_decisions(approval_id,idempotency_key,actor_user_id,decision,reason,
  source_entity_type,source_entity_id,source_version,policy_version)
 values(a.id,p_idempotency_key,p_actor_user_id,p_decision,left(btrim(p_reason),1000),
  a.source_entity_type,a.source_entity_id,a.source_version,a.policy_version);
 update public.approval_inbox_items set status=p_decision,version=version+1,updated_at=now()
 where id=a.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.'||p_decision,'approval_inbox_item',a.id::text,
  jsonb_build_object('tenant_id',a.tenant_id,'branch_id',a.branch_id,'source_entity_type',a.source_entity_type,
   'source_entity_id',a.source_entity_id,'source_version',a.source_version,'policy_version',a.policy_version,
   'idempotency_key',p_idempotency_key));
 return jsonb_build_object('approval_id',a.id,'decision',p_decision,'source_entity_type',a.source_entity_type,
  'source_entity_id',a.source_entity_id,'source_version',a.source_version,'version',a.version+1,'duplicate',false);
end;
$$;

create or replace function public.create_approval_delegation(
 p_actor_user_id uuid,p_allowed_branch_ids uuid[],p_delegate_user_id uuid,
 p_domain text,p_branch_id uuid,p_category text,p_max_amount_idr bigint,
 p_starts_at timestamptz,p_expires_at timestamptz
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare v_role text;v_active boolean;v_tenant_id uuid;v_policy public.approval_policies%rowtype;v_delegation public.approval_delegations%rowtype;
begin
 if p_delegate_user_id is null or p_delegate_user_id=p_actor_user_id
    or p_domain not in ('procurement','finance','hr','branch_ops')
    or p_max_amount_idr is null or p_max_amount_idr<0
    or p_starts_at is null or p_expires_at is null
    or p_starts_at<now() or p_expires_at<=p_starts_at
    or p_expires_at>p_starts_at+interval '90 days' then
   raise exception using errcode='22023',message='APPROVAL_DELEGATION_INVALID';
 end if;
 if not (p_branch_id=any(coalesce(p_allowed_branch_ids,array[]::uuid[]))) then
   raise exception using errcode='42501',message='APPROVAL_BRANCH_FORBIDDEN';
 end if;
 select role,is_active into v_role,v_active from public.admin_profiles where user_id=p_actor_user_id;
 if not found or not v_active then raise exception using errcode='42501',message='APPROVAL_ACTOR_INACTIVE'; end if;
 select tenant_id into v_tenant_id from public.branches where id=p_branch_id;
 if v_tenant_id is null then raise exception using errcode='P0002',message='APPROVAL_BRANCH_NOT_FOUND'; end if;
 select * into v_policy from public.approval_policies p
   where p.tenant_id=v_tenant_id and p.domain=p_domain and p.active
     and p.eligible_roles @> array[v_role]
   order by p.policy_version desc limit 1;
 if not found then raise exception using errcode='42501',message='APPROVAL_DELEGATOR_ROLE_FORBIDDEN'; end if;
 if p_max_amount_idr>v_policy.max_amount_idr
    or (p_category is not null and not (v_policy.allowed_categories @> array['*']::text[] or v_policy.allowed_categories @> array[p_category]::text[])) then
   raise exception using errcode='42501',message='APPROVAL_DELEGATION_POLICY_LIMIT_EXCEEDED';
 end if;
 if not exists(select 1 from public.admin_profiles a where a.user_id=p_delegate_user_id and a.is_active)
    or not (
      exists(select 1 from public.tenant_memberships m where m.tenant_id=v_tenant_id
        and m.user_id=p_delegate_user_id and m.status='active')
      or exists(select 1 from public.branch_assignments ba where ba.branch_id=p_branch_id
        and ba.user_id=p_delegate_user_id and ba.employment_status='active'
        and ba.starts_on<=current_date and (ba.ends_on is null or ba.ends_on>=current_date))
    ) then
   raise exception using errcode='42501',message='APPROVAL_DELEGATE_NOT_ACTIVE_IN_SCOPE';
 end if;
 insert into public.approval_delegations(tenant_id,delegator_user_id,delegate_user_id,domain,branch_id,
   category,max_amount_idr,starts_at,expires_at)
 values(v_tenant_id,p_actor_user_id,p_delegate_user_id,p_domain,p_branch_id,
   nullif(btrim(coalesce(p_category,'')),''),p_max_amount_idr,p_starts_at,p_expires_at)
 returning * into v_delegation;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.created','approval_delegation',v_delegation.id::text,
  jsonb_build_object('tenant_id',v_tenant_id,'branch_id',p_branch_id,'delegate_user_id',p_delegate_user_id,
   'domain',p_domain,'category',p_category,'max_amount_idr',p_max_amount_idr,
   'starts_at',p_starts_at,'expires_at',p_expires_at));
 return jsonb_build_object('id',v_delegation.id,'tenant_id',v_tenant_id,'branch_id',p_branch_id,
   'delegate_user_id',p_delegate_user_id,'domain',p_domain,'expires_at',p_expires_at);
end;
$$;

create or replace function public.revoke_approval_delegation(
 p_delegation_id uuid,p_actor_user_id uuid,p_allowed_branch_ids uuid[]
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare d public.approval_delegations%rowtype;
begin
 select * into d from public.approval_delegations where id=p_delegation_id for update;
 if not found then raise exception using errcode='P0002',message='APPROVAL_DELEGATION_NOT_FOUND'; end if;
 if d.delegator_user_id<>p_actor_user_id
    or not (d.branch_id=any(coalesce(p_allowed_branch_ids,array[]::uuid[]))) then
   raise exception using errcode='42501',message='APPROVAL_DELEGATION_FORBIDDEN';
 end if;
 if d.revoked_at is null then
   update public.approval_delegations set revoked_at=now() where id=d.id;
   insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
   values(p_actor_user_id,'executive.approval.delegation.revoked','approval_delegation',d.id::text,
     jsonb_build_object('tenant_id',d.tenant_id,'branch_id',d.branch_id,'delegate_user_id',d.delegate_user_id));
 end if;
 return jsonb_build_object('id',d.id,'revoked',true);
end;
$$;

revoke all on function public.list_pending_approvals(uuid,uuid[],uuid,text,text) from public,anon,authenticated;
revoke all on function public.claim_approval(uuid,uuid,uuid[],integer) from public,anon,authenticated;
revoke all on function public.decide_approval(uuid,uuid,uuid[],integer,text,text,text) from public,anon,authenticated;
grant execute on function public.list_pending_approvals(uuid,uuid[],uuid,text,text) to service_role;
grant execute on function public.claim_approval(uuid,uuid,uuid[],integer) to service_role;
grant execute on function public.decide_approval(uuid,uuid,uuid[],integer,text,text,text) to service_role;
revoke all on function public.create_approval_delegation(uuid,uuid[],uuid,text,uuid,text,bigint,timestamptz,timestamptz) from public,anon,authenticated;
revoke all on function public.revoke_approval_delegation(uuid,uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.create_approval_delegation(uuid,uuid[],uuid,text,uuid,text,bigint,timestamptz,timestamptz) to service_role;
grant execute on function public.revoke_approval_delegation(uuid,uuid,uuid[]) to service_role;

commit;
