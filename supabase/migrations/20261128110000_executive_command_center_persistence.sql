-- T01/T02 persistence foundation. Source-only migration; do not apply to shared staging
-- until disposable replay, auth/RLS review, and final acceptance are approved.

-- T01: payment recognition timestamp and branch-local business date.
alter table public.pos_sales
  add column if not exists paid_at timestamptz,
  add column if not exists business_date date,
  add column if not exists paid_at_source text;

update public.pos_sales s
set paid_at = s.created_at,
    business_date = (s.created_at at time zone b.timezone)::date,
    paid_at_source = 'legacy_created_at_backfill'
from public.branches b
where b.id = s.branch_id
  and s.payment_status = 'paid'
  and s.paid_at is null;

alter table public.pos_sales
  add constraint pos_sales_paid_at_source_check
  check (paid_at_source is null or paid_at_source in ('payment_transition','legacy_created_at_backfill'));

create or replace function public.set_pos_sale_payment_recognition()
returns trigger
language plpgsql
set search_path = ''
as $$
declare v_timezone text;
begin
  select b.timezone into v_timezone
  from public.branches b where b.id = new.branch_id;
  if v_timezone is null then
    raise exception using errcode='23503', message='POS_SALE_BRANCH_TIMEZONE_REQUIRED';
  end if;

  if new.payment_status = 'paid' then
    if tg_op = 'INSERT' and new.paid_at is null then
      new.paid_at := now();
      new.paid_at_source := 'payment_transition';
    elsif tg_op = 'UPDATE' and old.payment_status is distinct from 'paid' then
      new.paid_at := now();
      new.paid_at_source := 'payment_transition';
    elsif new.paid_at is null then
      new.paid_at := now();
      new.paid_at_source := 'payment_transition';
    end if;
    new.business_date := (new.paid_at at time zone v_timezone)::date;
  else
    new.paid_at := null;
    new.business_date := null;
    new.paid_at_source := null;
  end if;
  return new;
end $$;

drop trigger if exists pos_sales_payment_recognition on public.pos_sales;
create trigger pos_sales_payment_recognition
before insert or update of payment_status, branch_id, paid_at
on public.pos_sales
for each row execute function public.set_pos_sale_payment_recognition();

create index if not exists pos_sales_branch_business_date_paid_idx
  on public.pos_sales(branch_id,business_date,paid_at)
  where payment_status='paid';

-- T01: immutable, versioned snapshots persisted only after source reconciliation.
create table if not exists public.executive_command_center_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  period_start date not null,
  period_end date not null,
  as_of timestamptz not null,
  formula_version integer not null check(formula_version > 0),
  expected_branch_count integer not null check(expected_branch_count between 1 and 150),
  active_branch_count integer not null check(active_branch_count between 0 and 150),
  reconciled_branch_count integer not null check(reconciled_branch_count between 0 and 150),
  status text not null check(status in ('partial','complete')),
  totals jsonb not null check(jsonb_typeof(totals)='object'),
  branch_facts jsonb not null check(jsonb_typeof(branch_facts)='array'),
  source_gaps jsonb not null default '[]'::jsonb check(jsonb_typeof(source_gaps)='array'),
  idempotency_key text not null check(length(btrim(idempotency_key)) between 8 and 160),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,idempotency_key),
  check(period_end >= period_start),
  check(reconciled_branch_count <= active_branch_count),
  check(status <> 'complete' or (active_branch_count=expected_branch_count and reconciled_branch_count=active_branch_count and jsonb_array_length(source_gaps)=0))
);
create index if not exists executive_cc_snapshot_period_idx
  on public.executive_command_center_snapshots(tenant_id,period_start,period_end,as_of desc);

-- T02: persisted approval coordination. Source entity state remains owned by its domain.
create table if not exists public.executive_approval_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  source_domain text not null check(source_domain in ('pos','orders','inventory','procurement','finance','hr','franchise')),
  source_entity text not null,
  source_entity_id text not null,
  source_version bigint not null check(source_version >= 0),
  requested_action text not null,
  request_payload jsonb not null default '{}'::jsonb check(jsonb_typeof(request_payload)='object'),
  created_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'pending' check(status in ('pending','claimed','approved','rejected','cancelled','expired')),
  claimed_by uuid null references auth.users(id) on delete restrict,
  claimed_at timestamptz null,
  claim_expires_at timestamptz null,
  expires_at timestamptz null,
  version bigint not null default 0 check(version >= 0),
  idempotency_key text not null check(length(btrim(idempotency_key)) between 8 and 160),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,idempotency_key),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check((status='claimed') = (claimed_by is not null and claimed_at is not null and claim_expires_at is not null))
);
create index if not exists executive_approval_queue_idx
  on public.executive_approval_items(tenant_id,branch_id,status,created_at desc);

create table if not exists public.executive_approval_delegations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  delegator_user_id uuid not null references auth.users(id) on delete restrict,
  delegate_user_id uuid not null references auth.users(id) on delete restrict,
  source_domains text[] not null check(cardinality(source_domains)>0),
  valid_from timestamptz not null,
  valid_until timestamptz not null,
  revoked_at timestamptz null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  check(delegator_user_id<>delegate_user_id),
  check(valid_until>valid_from)
);
create index if not exists executive_approval_delegation_active_idx
  on public.executive_approval_delegations(tenant_id,delegate_user_id,valid_from,valid_until)
  where revoked_at is null;

create table if not exists public.executive_approval_claim_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  approval_id uuid not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null check(event_type in ('claimed','released','expired')),
  version bigint not null,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  foreign key(tenant_id,approval_id) references public.executive_approval_items(tenant_id,id) on delete restrict,
  unique(tenant_id,idempotency_key)
);

create table if not exists public.executive_approval_decisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  approval_id uuid not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  decision text not null check(decision in ('approved','rejected')),
  reason text not null check(length(btrim(reason)) between 8 and 2000),
  source_version bigint not null,
  source_mutation_id text null,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  foreign key(tenant_id,approval_id) references public.executive_approval_items(tenant_id,id) on delete restrict,
  unique(tenant_id,idempotency_key),
  unique(tenant_id,approval_id)
);

do $$
declare t text;
begin
  foreach t in array array[
    'executive_command_center_snapshots','executive_approval_items',
    'executive_approval_delegations','executive_approval_claim_events',
    'executive_approval_decisions'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
    execute format('revoke all on public.%I from anon,authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;

-- Caller identity is supplied by a trusted server adapter; the RPC independently
-- verifies an active tenant membership before persisting a snapshot.
create or replace function public.executive_persist_command_center_snapshot(
  p_tenant_id uuid,p_actor_user_id uuid,p_period_start date,p_period_end date,
  p_as_of timestamptz,p_formula_version integer,p_expected_branch_count integer,
  p_active_branch_count integer,p_reconciled_branch_count integer,p_status text,
  p_totals jsonb,p_branch_facts jsonb,p_source_gaps jsonb,p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v public.executive_command_center_snapshots%rowtype;
begin
  if not exists(
    select 1 from public.tenant_memberships m
    where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active'
      and (m.role in ('tenant_owner','tenant_admin') or m.permissions ? 'executive.command_center.read')
  ) and coalesce((select u.raw_app_meta_data->'platform_owner' = 'true'::jsonb from auth.users u where u.id=p_actor_user_id),false) is not true then
    raise exception using errcode='42501',message='EXECUTIVE_COMMAND_CENTER_PERMISSION_REQUIRED';
  end if;
  if p_period_start is null or p_period_end<p_period_start or p_as_of is null
     or p_formula_version<1 or p_expected_branch_count not between 1 and 150
     or p_active_branch_count not between 0 and 150
     or p_reconciled_branch_count not between 0 and p_active_branch_count
     or p_status not in ('partial','complete')
     or jsonb_typeof(p_totals)<>'object' or jsonb_typeof(p_branch_facts)<>'array'
     or jsonb_typeof(p_source_gaps)<>'array'
     or length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 160 then
    raise exception using errcode='22023',message='EXECUTIVE_SNAPSHOT_INPUT_INVALID';
  end if;
  insert into public.executive_command_center_snapshots(
    tenant_id,period_start,period_end,as_of,formula_version,expected_branch_count,
    active_branch_count,reconciled_branch_count,status,totals,branch_facts,source_gaps,idempotency_key,created_by
  ) values(
    p_tenant_id,p_period_start,p_period_end,p_as_of,p_formula_version,p_expected_branch_count,
    p_active_branch_count,p_reconciled_branch_count,p_status,p_totals,p_branch_facts,p_source_gaps,p_idempotency_key,p_actor_user_id
  ) on conflict(tenant_id,idempotency_key) do nothing;
  select * into v from public.executive_command_center_snapshots
    where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
  return jsonb_build_object('id',v.id,'status',v.status,'duplicate',v.created_at<>transaction_timestamp());
end $$;
revoke all on function public.executive_persist_command_center_snapshot(uuid,uuid,date,date,timestamptz,integer,integer,integer,integer,text,jsonb,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.executive_persist_command_center_snapshot(uuid,uuid,date,date,timestamptz,integer,integer,integer,integer,text,jsonb,jsonb,jsonb,text) to service_role;

-- Atomic claim: row lock + optimistic version + idempotency + immutable event.
create or replace function public.executive_claim_approval(
  p_tenant_id uuid,p_approval_id uuid,p_actor_user_id uuid,p_expected_version bigint,
  p_idempotency_key text,p_claim_ttl_seconds integer default 300
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v public.executive_approval_items%rowtype; v_prior public.executive_approval_claim_events%rowtype;
begin
  if not exists(
    select 1 from public.tenant_memberships m
    where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active'
      and (m.role in ('tenant_owner','tenant_admin') or m.permissions ? 'executive.approvals.claim')
  ) and coalesce((select u.raw_app_meta_data->'platform_owner' = 'true'::jsonb from auth.users u where u.id=p_actor_user_id),false) is not true then
    raise exception using errcode='42501',message='EXECUTIVE_APPROVAL_CLAIM_PERMISSION_REQUIRED';
  end if;
  if length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 160 or p_claim_ttl_seconds not between 30 and 3600 then
    raise exception using errcode='22023',message='EXECUTIVE_CLAIM_INPUT_INVALID';
  end if;
  select * into v_prior from public.executive_approval_claim_events
   where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
  if found then return jsonb_build_object('duplicate',true,'approval_id',v_prior.approval_id,'version',v_prior.version); end if;
  select * into v from public.executive_approval_items
   where tenant_id=p_tenant_id and id=p_approval_id for update;
  if not found then raise exception using errcode='P0002',message='EXECUTIVE_APPROVAL_NOT_FOUND'; end if;
  if v.version<>p_expected_version then raise exception using errcode='40001',message='EXECUTIVE_APPROVAL_STALE_VERSION'; end if;
  if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('tenant_owner','tenant_admin'))
     and coalesce((select u.raw_app_meta_data->'platform_owner' = 'true'::jsonb from auth.users u where u.id=p_actor_user_id),false) is not true
     and not exists(select 1 from public.branch_assignments ba where ba.branch_id=v.branch_id and ba.user_id=p_actor_user_id and ba.employment_status='active' and ba.starts_on<=current_date and (ba.ends_on is null or ba.ends_on>=current_date)) then
    raise exception using errcode='42501',message='EXECUTIVE_APPROVAL_BRANCH_SCOPE_DENIED';
  end if;
  if v.status not in ('pending','claimed') or (v.expires_at is not null and v.expires_at<=now()) then
    raise exception using errcode='23514',message='EXECUTIVE_APPROVAL_NOT_CLAIMABLE';
  end if;
  if v.status='claimed' and v.claim_expires_at>now() and v.claimed_by<>p_actor_user_id then
    raise exception using errcode='55P03',message='EXECUTIVE_APPROVAL_ALREADY_CLAIMED';
  end if;
  update public.executive_approval_items set status='claimed',claimed_by=p_actor_user_id,
    claimed_at=now(),claim_expires_at=now()+make_interval(secs=>p_claim_ttl_seconds),
    version=version+1,updated_at=now()
   where tenant_id=p_tenant_id and id=p_approval_id returning * into v;
  insert into public.executive_approval_claim_events(tenant_id,approval_id,actor_user_id,event_type,version,idempotency_key)
  values(p_tenant_id,p_approval_id,p_actor_user_id,'claimed',v.version,p_idempotency_key);
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'executive.approval.claimed','executive_approval_item',p_approval_id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'branch_id',v.branch_id,'version',v.version));
  return jsonb_build_object('approval_id',v.id,'status',v.status,'claimed_by',v.claimed_by,'version',v.version,'claim_expires_at',v.claim_expires_at,'duplicate',false);
end $$;
revoke all on function public.executive_claim_approval(uuid,uuid,uuid,bigint,text,integer) from public,anon,authenticated;
grant execute on function public.executive_claim_approval(uuid,uuid,uuid,bigint,text,integer) to service_role;

comment on table public.executive_approval_decisions is
  'Decision persistence only. A decision is not accepted as complete until a source-domain adapter applies exactly one source mutation in the same transaction.';
