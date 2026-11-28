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
  and s.payment_status in ('paid','refunded')
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

  if tg_op = 'INSERT' and new.payment_status = 'refunded' then
    raise exception using errcode='23514', message='POS_SALE_REFUND_REQUIRES_PAID_SOURCE';
  elsif tg_op = 'UPDATE' and new.payment_status = 'refunded' and old.payment_status <> 'paid' and old.payment_status <> 'refunded' then
    raise exception using errcode='23514', message='POS_SALE_REFUND_REQUIRES_PAID_SOURCE';
  elsif tg_op = 'INSERT' and new.payment_status = 'paid' then
    -- Payment recognition is server-timestamped; clients cannot backdate a new sale.
    new.paid_at := now();
    new.paid_at_source := 'payment_transition';
    new.business_date := (new.paid_at at time zone v_timezone)::date;
  elsif tg_op = 'UPDATE' and old.payment_status in ('paid','refunded') then
    if new.branch_id is distinct from old.branch_id then
      raise exception using errcode='42501', message='POS_SALE_PAID_BRANCH_IMMUTABLE';
    end if;
    if new.paid_at is distinct from old.paid_at or new.paid_at_source is distinct from old.paid_at_source then
      raise exception using errcode='42501', message='POS_SALE_PAYMENT_RECOGNITION_IMMUTABLE';
    end if;
    if old.payment_status='refunded' and new.payment_status='paid' then
      raise exception using errcode='23514', message='POS_SALE_REFUND_CANNOT_REOPEN_PAYMENT';
    end if;
    if new.payment_status in ('paid','refunded') then
      -- Refund is a separate contra-revenue event; preserve original paid recognition.
      new.paid_at := old.paid_at;
      new.paid_at_source := old.paid_at_source;
      new.business_date := case when old.paid_at is null then null else (old.paid_at at time zone v_timezone)::date end;
    else
      raise exception using errcode='23514', message='POS_SALE_PAID_STATUS_TERMINAL';
    end if;
  elsif new.payment_status = 'paid' then
    -- Pending -> paid is the payment recognition transition.
    new.paid_at := now();
    new.paid_at_source := 'payment_transition';
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
before insert or update of payment_status, branch_id, paid_at, business_date, paid_at_source
on public.pos_sales
for each row execute function public.set_pos_sale_payment_recognition();
-- Trigger execution is managed by PostgreSQL; never expose the trigger function as an RPC.
revoke all on function public.set_pos_sale_payment_recognition() from public,anon,authenticated,service_role;

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
create unique index if not exists executive_approval_one_active_source_idx
  on public.executive_approval_items(tenant_id,source_domain,source_entity,source_entity_id)
  where status in ('pending','claimed');

create table if not exists public.executive_approval_delegations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  delegator_user_id uuid not null references auth.users(id) on delete restrict,
  delegate_user_id uuid not null references auth.users(id) on delete restrict,
  source_domains text[] not null check(cardinality(source_domains)>0 and source_domains <@ array['pos','orders','inventory','procurement','finance','hr','franchise']::text[]),
  idempotency_key text not null check(length(btrim(idempotency_key)) between 8 and 160),
  valid_from timestamptz not null,
  valid_until timestamptz not null,
  revoked_at timestamptz null,
  revoked_by uuid null references auth.users(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,idempotency_key),
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
  delegation_id uuid null references public.executive_approval_delegations(id) on delete restrict,
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
declare v public.executive_command_center_snapshots%rowtype; v_inserted integer;
  v_active_count integer; v_fact_count integer; v_distinct_fact_count integer;
begin
  if not exists(
    select 1 from public.tenant_memberships m
    where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active'
      and (m.role in ('tenant_owner','tenant_admin') or m.permissions ? 'executive.command_center.read')
  ) and coalesce((select u.raw_app_meta_data->'platform_owner' = 'true'::jsonb from auth.users u where u.id=p_actor_user_id),false) is not true then
    raise exception using errcode='42501',message='EXECUTIVE_COMMAND_CENTER_PERMISSION_REQUIRED';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end<p_period_start or p_as_of is null
     or p_formula_version is null or p_formula_version<1
     or p_expected_branch_count is null or p_expected_branch_count not between 1 and 150
     or p_active_branch_count is null or p_active_branch_count not between 0 and 150
     or p_reconciled_branch_count is null or p_reconciled_branch_count not between 0 and p_active_branch_count
     or p_status is null or p_status not in ('partial','complete')
     or p_totals is null or jsonb_typeof(p_totals)<>'object'
     or p_branch_facts is null or jsonb_typeof(p_branch_facts)<>'array'
     or p_source_gaps is null or jsonb_typeof(p_source_gaps)<>'array'
     or length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 160 then
    raise exception using errcode='22023',message='EXECUTIVE_SNAPSHOT_INPUT_INVALID';
  end if;
  select count(*) into v_active_count from public.branches
    where tenant_id=p_tenant_id and status='active';
  if v_active_count<>p_active_branch_count then
    raise exception using errcode='23514',message='EXECUTIVE_SNAPSHOT_ACTIVE_BRANCH_COUNT_MISMATCH';
  end if;
  select count(*),count(distinct fact->>'branchId')
    into v_fact_count,v_distinct_fact_count
    from jsonb_array_elements(p_branch_facts) fact;
  if v_fact_count<>p_reconciled_branch_count or v_distinct_fact_count<>v_fact_count then
    raise exception using errcode='23514',message='EXECUTIVE_SNAPSHOT_BRANCH_FACT_COUNT_MISMATCH';
  end if;
  if exists(
    select 1 from jsonb_array_elements(p_branch_facts) fact
    where case
      when coalesce(fact->>'branchId','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then not exists(
        select 1 from public.branches b
        where b.id=(fact->>'branchId')::uuid and b.tenant_id=p_tenant_id and b.status='active'
      )
      else true
    end
  ) then
    raise exception using errcode='42501',message='EXECUTIVE_SNAPSHOT_BRANCH_SCOPE_MISMATCH';
  end if;
  insert into public.executive_command_center_snapshots(
    tenant_id,period_start,period_end,as_of,formula_version,expected_branch_count,
    active_branch_count,reconciled_branch_count,status,totals,branch_facts,source_gaps,idempotency_key,created_by
  ) values(
    p_tenant_id,p_period_start,p_period_end,p_as_of,p_formula_version,p_expected_branch_count,
    p_active_branch_count,p_reconciled_branch_count,p_status,p_totals,p_branch_facts,p_source_gaps,p_idempotency_key,p_actor_user_id
  ) on conflict(tenant_id,idempotency_key) do nothing;
  get diagnostics v_inserted = row_count;
  select * into v from public.executive_command_center_snapshots
    where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
  if v_inserted=0 and (
    v.period_start is distinct from p_period_start or v.period_end is distinct from p_period_end
    or v.formula_version is distinct from p_formula_version or v.totals is distinct from p_totals
    or v.branch_facts is distinct from p_branch_facts or v.source_gaps is distinct from p_source_gaps
  ) then
    raise exception using errcode='23505',message='EXECUTIVE_SNAPSHOT_IDEMPOTENCY_KEY_REUSED';
  end if;
  if v_inserted=1 then
    insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
    values(p_actor_user_id,'executive.command_center.snapshot_built','executive_command_center_snapshots',v.id::text,
      jsonb_build_object('tenant_id',p_tenant_id,'period_start',p_period_start,'period_end',p_period_end,
        'status',v.status,'formula_version',v.formula_version,'reconciled_branch_count',v.reconciled_branch_count));
  end if;
  return jsonb_build_object('id',v.id,'status',v.status,'duplicate',v_inserted=0);
end $$;
revoke all on function public.executive_persist_command_center_snapshot(uuid,uuid,date,date,timestamptz,integer,integer,integer,integer,text,jsonb,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.executive_persist_command_center_snapshot(uuid,uuid,date,date,timestamptz,integer,integer,integer,integer,text,jsonb,jsonb,jsonb,text) to service_role;

-- T02: explicit, time-bounded approval delegation lifecycle.
create or replace function public.executive_create_approval_delegation(
 p_tenant_id uuid,p_actor_user_id uuid,p_delegator_user_id uuid,p_delegate_user_id uuid,
 p_source_domains text[],p_valid_from timestamptz,p_valid_until timestamptz,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path='' as $delegation$
declare v public.executive_approval_delegations%rowtype; v_admin boolean; v_platform_owner boolean; v_inserted integer;
begin
 if p_tenant_id is null or p_actor_user_id is null or p_delegator_user_id is null or p_delegate_user_id is null
  or p_delegator_user_id=p_delegate_user_id or p_valid_from is null or p_valid_until is null
  or p_valid_until<=p_valid_from or p_valid_from<now()-interval '5 minutes'
  or p_valid_until>now()+interval '90 days'
  or p_source_domains is null or cardinality(p_source_domains)<1
  or not (p_source_domains <@ array['pos','orders','inventory','procurement','finance','hr','franchise']::text[])
  or length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 160 then
  raise exception using errcode='22023',message='EXECUTIVE_DELEGATION_INPUT_INVALID';
 end if;
 select coalesce((select u.raw_app_meta_data->'platform_owner'='true'::jsonb from auth.users u where u.id=p_actor_user_id),false) into v_platform_owner;
 select exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active'
  and m.role in ('tenant_owner','tenant_admin')) into v_admin;
 if not v_admin and not v_platform_owner and p_actor_user_id<>p_delegator_user_id then
  raise exception using errcode='42501',message='EXECUTIVE_DELEGATION_ACTOR_MISMATCH';
 end if;
 if not v_platform_owner and not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active'
   and (m.role in ('tenant_owner','tenant_admin') or m.permissions ? 'executive.approvals.delegate')) then
  raise exception using errcode='42501',message='EXECUTIVE_DELEGATION_PERMISSION_REQUIRED';
 end if;
 if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_delegator_user_id and m.status='active')
  or not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_delegate_user_id and m.status='active') then
  raise exception using errcode='42501',message='EXECUTIVE_DELEGATION_MEMBERSHIP_REQUIRED';
 end if;
 insert into public.executive_approval_delegations(tenant_id,delegator_user_id,delegate_user_id,source_domains,
  idempotency_key,valid_from,valid_until,created_by)
 values(p_tenant_id,p_delegator_user_id,p_delegate_user_id,array(select distinct x from unnest(p_source_domains) x order by x),
  p_idempotency_key,p_valid_from,p_valid_until,p_actor_user_id)
 on conflict(tenant_id,idempotency_key) do nothing;
 get diagnostics v_inserted=row_count;
 select * into v from public.executive_approval_delegations where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if v.delegator_user_id is distinct from p_delegator_user_id or v.delegate_user_id is distinct from p_delegate_user_id
  or v.source_domains is distinct from array(select distinct x from unnest(p_source_domains) x order by x)
  or v.valid_from is distinct from p_valid_from or v.valid_until is distinct from p_valid_until then
  raise exception using errcode='23505',message='EXECUTIVE_DELEGATION_IDEMPOTENCY_KEY_REUSED';
 end if;
 if v_inserted=1 then
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'executive.approval.delegation.created','executive_approval_delegation',v.id::text,
   jsonb_build_object('tenant_id',p_tenant_id,'delegator_user_id',p_delegator_user_id,'delegate_user_id',p_delegate_user_id,
    'source_domains',v.source_domains,'valid_from',p_valid_from,'valid_until',p_valid_until));
 end if;
 return jsonb_build_object('id',v.id,'duplicate',v_inserted=0,'valid_from',v.valid_from,'valid_until',v.valid_until);
end $delegation$;
revoke all on function public.executive_create_approval_delegation(uuid,uuid,uuid,uuid,text[],timestamptz,timestamptz,text) from public,anon,authenticated;
grant execute on function public.executive_create_approval_delegation(uuid,uuid,uuid,uuid,text[],timestamptz,timestamptz,text) to service_role;

create or replace function public.executive_revoke_approval_delegation(
 p_tenant_id uuid,p_actor_user_id uuid,p_delegation_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $delegation$
declare v public.executive_approval_delegations%rowtype; v_admin boolean; v_platform_owner boolean;
begin
 if p_tenant_id is null or p_actor_user_id is null or p_delegation_id is null then
  raise exception using errcode='22023',message='EXECUTIVE_DELEGATION_INPUT_INVALID';
 end if;
 select coalesce((select u.raw_app_meta_data->'platform_owner'='true'::jsonb from auth.users u where u.id=p_actor_user_id),false) into v_platform_owner;
 select exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id
  and m.status='active' and m.role in ('tenant_owner','tenant_admin')) into v_admin;
 select * into v from public.executive_approval_delegations where tenant_id=p_tenant_id and id=p_delegation_id for update;
 if not found then raise exception using errcode='P0002',message='EXECUTIVE_DELEGATION_NOT_FOUND'; end if;
 if not v_admin and not v_platform_owner and v.delegator_user_id<>p_actor_user_id then
  raise exception using errcode='42501',message='EXECUTIVE_DELEGATION_REVOKE_FORBIDDEN';
 end if;
 if v.revoked_at is not null then return jsonb_build_object('id',v.id,'revoked',true,'duplicate',true); end if;
 update public.executive_approval_delegations set revoked_at=now(),revoked_by=p_actor_user_id
  where tenant_id=p_tenant_id and id=p_delegation_id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.revoked','executive_approval_delegation',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'delegator_user_id',v.delegator_user_id,'delegate_user_id',v.delegate_user_id));
 return jsonb_build_object('id',v.id,'revoked',true,'duplicate',false);
end $delegation$;
revoke all on function public.executive_revoke_approval_delegation(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.executive_revoke_approval_delegation(uuid,uuid,uuid) to service_role;

-- Atomic claim: row lock + optimistic version + idempotency + immutable event.
create or replace function public.executive_claim_approval(
  p_tenant_id uuid,p_approval_id uuid,p_actor_user_id uuid,p_expected_version bigint,
  p_idempotency_key text,p_claim_ttl_seconds integer default 300
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v public.executive_approval_items%rowtype; v_prior public.executive_approval_claim_events%rowtype;
begin
  if p_tenant_id is null or p_approval_id is null or p_actor_user_id is null
     or p_expected_version is null or p_expected_version<0
     or p_claim_ttl_seconds is null or p_claim_ttl_seconds not between 30 and 3600
     or length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 160 then
    raise exception using errcode='22023',message='EXECUTIVE_CLAIM_INPUT_INVALID';
  end if;
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
  if found then
    if v_prior.approval_id is distinct from p_approval_id or v_prior.actor_user_id is distinct from p_actor_user_id then
      raise exception using errcode='23505',message='EXECUTIVE_APPROVAL_IDEMPOTENCY_KEY_REUSED';
    end if;
    return jsonb_build_object('duplicate',true,'approval_id',v_prior.approval_id,'version',v_prior.version);
  end if;
  select * into v from public.executive_approval_items
   where tenant_id=p_tenant_id and id=p_approval_id for update;
  if not found then raise exception using errcode='P0002',message='EXECUTIVE_APPROVAL_NOT_FOUND'; end if;
  -- Recheck after acquiring the row lock so concurrent retries with the same
  -- idempotency key return the original claim rather than a stale-version error.
  select * into v_prior from public.executive_approval_claim_events
   where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
  if found then
    if v_prior.approval_id is distinct from p_approval_id or v_prior.actor_user_id is distinct from p_actor_user_id then
      raise exception using errcode='23505',message='EXECUTIVE_APPROVAL_IDEMPOTENCY_KEY_REUSED';
    end if;
    return jsonb_build_object('duplicate',true,'approval_id',v_prior.approval_id,'version',v_prior.version);
  end if;
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


-- T02: enqueue approval requests only for source entities with verified adapters.
create or replace function public.executive_enqueue_approval(
 p_tenant_id uuid,p_actor_user_id uuid,p_branch_id uuid,p_source_domain text,
 p_source_entity text,p_source_entity_id text,p_requested_action text,
 p_request_payload jsonb,p_idempotency_key text,p_expires_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path='' as $enqueue$
declare v_source_branch uuid; v_source_tenant uuid; v_source_status text; v_source_version bigint;
 v_item public.executive_approval_items%rowtype; v_inserted integer; v_platform_owner boolean;
begin
 if p_tenant_id is null or p_actor_user_id is null or p_branch_id is null
  or p_source_domain is null or p_source_entity is null or p_requested_action is null
  or p_source_domain not in ('procurement','hr')
  or p_source_entity not in ('purchase_requisitions','hr_leave_requests')
  or p_source_entity_id is null or p_source_entity_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}
create or replace function public.executive_get_sales_monitor(
 p_tenant_id uuid,p_actor_user_id uuid,p_branch_ids uuid[],p_from_date date,p_through_date date
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_allowed boolean; v_count integer; v_result jsonb;
begin
 select exists(
  select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active'
   and (m.role in ('tenant_owner','tenant_admin') or m.permissions ? 'executive.command_center.read')
 ) or coalesce((select u.raw_app_meta_data->'platform_owner'='true'::jsonb from auth.users u where u.id=p_actor_user_id),false)
 into v_allowed;
 if not v_allowed then raise exception using errcode='42501',message='EXECUTIVE_COMMAND_CENTER_PERMISSION_REQUIRED'; end if;
 if p_branch_ids is null or cardinality(p_branch_ids)<1 or cardinality(p_branch_ids)>150
    or p_from_date is null or p_through_date is null or p_through_date<p_from_date
    or p_through_date-p_from_date>92 then
  raise exception using errcode='22023',message='EXECUTIVE_SALES_MONITOR_INPUT_INVALID';
 end if;
 if exists(select 1 from public.branches b where b.id=any(p_branch_ids) and b.tenant_id<>p_tenant_id) then
  raise exception using errcode='42501',message='EXECUTIVE_SALES_MONITOR_TENANT_SCOPE_DENIED';
 end if;
 if not (coalesce((select u.raw_app_meta_data->'platform_owner'='true'::jsonb from auth.users u where u.id=p_actor_user_id),false)
   or exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('tenant_owner','tenant_admin'))) then
  if exists(select 1 from unnest(p_branch_ids) bid where not exists(
    select 1 from public.branch_assignments ba where ba.branch_id=bid and ba.user_id=p_actor_user_id
      and ba.employment_status='active' and ba.starts_on<=current_date and (ba.ends_on is null or ba.ends_on>=current_date)
  )) then raise exception using errcode='42501',message='EXECUTIVE_SALES_MONITOR_BRANCH_SCOPE_DENIED'; end if;
 end if;
 select count(*) into v_count from public.branches b where b.id=any(p_branch_ids) and b.tenant_id=p_tenant_id;
 if v_count<>cardinality(p_branch_ids) then raise exception using errcode='42501',message='EXECUTIVE_SALES_MONITOR_BRANCH_SCOPE_DENIED'; end if;
 if exists(select 1 from public.pos_sales s where s.branch_id=any(p_branch_ids)
   and s.payment_status in ('paid','refunded') and s.paid_at is not null
   and s.subtotal_idr-s.discount_idr<>s.total_idr) then
  raise exception using errcode='23514',message='EXECUTIVE_SALES_SOURCE_TOTAL_MISMATCH';
 end if;
 if exists(
  select s.id from public.pos_sales s join public.refund_records r on r.pos_sale_id=s.id and r.status='processed'
  join public.branches b on b.id=s.branch_id and b.tenant_id=p_tenant_id
  where s.branch_id=any(p_branch_ids) and s.paid_at is not null
   and (r.processed_at at time zone b.timezone)::date between p_from_date and p_through_date
  group by s.id,s.total_idr having sum(r.amount_idr)>s.total_idr
 ) then raise exception using errcode='23514',message='EXECUTIVE_PROCESSED_REFUND_EXCEEDS_SALE'; end if;
 with branch_sales as (
  select b.id branch_id,b.code,b.name,b.timezone,
   coalesce(sum(s.subtotal_idr) filter(where s.payment_status in ('paid','refunded')),0)::bigint gross_sales_idr,
   coalesce(sum(s.discount_idr) filter(where s.payment_status in ('paid','refunded')),0)::bigint discount_idr,
   coalesce(sum(s.total_idr) filter(where s.payment_status in ('paid','refunded')),0)::bigint net_before_refund_idr,
   count(s.id) filter(where s.payment_status in ('paid','refunded'))::integer paid_transactions,
   count(s.id) filter(where s.payment_status in ('paid','refunded') and s.paid_at_source='legacy_created_at_backfill')::integer legacy_paid_at_count
  from public.branches b left join public.pos_sales s on s.branch_id=b.id
   and s.paid_at is not null and s.business_date between p_from_date and p_through_date
  where b.id=any(p_branch_ids) and b.tenant_id=p_tenant_id group by b.id,b.code,b.name,b.timezone
 ), branch_refunds as (
  select r.branch_id,coalesce(sum(r.amount_idr),0)::bigint refund_idr
  from public.refund_records r join public.branches b on b.id=r.branch_id and b.tenant_id=p_tenant_id
  where r.branch_id=any(p_branch_ids) and r.pos_sale_id is not null and r.status='processed'
    and (r.processed_at at time zone b.timezone)::date between p_from_date and p_through_date
  group by r.branch_id
 ), branch_settlements as (
  -- Allocate only the source item amount to a branch. Provider-level fee/net/
  -- received totals are calculated once per distinct settlement below.
  select s.branch_id,coalesce(sum(psi.amount_idr),0)::bigint settlement_gross_idr,
   count(distinct ps.id)::integer matched_settlements
  from public.payment_settlement_items psi
  join public.pos_sales s on s.id=psi.pos_sale_id
  join public.branches b on b.id=s.branch_id and b.tenant_id=p_tenant_id
  join public.payment_settlements ps on ps.id=psi.settlement_id
  where s.branch_id=any(p_branch_ids) and ps.status='matched'
    and ps.settlement_date between p_from_date and p_through_date
  group by s.branch_id
 ), settlement_totals as (
  select coalesce(sum(ps.gross_amount_idr),0)::bigint gross_idr,
   coalesce(sum(ps.fee_amount_idr),0)::bigint fee_idr,
   coalesce(sum(ps.net_amount_idr),0)::bigint net_idr,
   coalesce(sum(ps.received_amount_idr),0)::bigint received_idr,
   count(*)::integer settlement_count
  from public.payment_settlements ps
  where ps.status='matched' and ps.settlement_date between p_from_date and p_through_date
   and exists(select 1 from public.payment_settlement_items psi
    join public.pos_sales s on s.id=psi.pos_sale_id
    join public.branches b on b.id=s.branch_id
    where psi.settlement_id=ps.id and b.tenant_id=p_tenant_id and s.branch_id=any(p_branch_ids))
   and not exists(select 1 from public.payment_settlement_items psi
    join public.pos_sales s on s.id=psi.pos_sale_id
    join public.branches b on b.id=s.branch_id
    where psi.settlement_id=ps.id and (b.tenant_id<>p_tenant_id or not (s.branch_id=any(p_branch_ids))))
 )
 select jsonb_build_object(
  'tenant_id',p_tenant_id,'from_date',p_from_date,'through_date',p_through_date,
  'branch_count',count(*),
  'gross_sales_idr',coalesce(sum(bs.gross_sales_idr),0),
  'discount_idr',coalesce(sum(bs.discount_idr),0),
  'refund_idr',coalesce(sum(coalesce(br.refund_idr,0)),0),
  'net_sales_idr',coalesce(sum(bs.net_before_refund_idr-coalesce(br.refund_idr,0)),0),
  'paid_transactions',coalesce(sum(bs.paid_transactions),0),
  'legacy_paid_at_count',coalesce(sum(bs.legacy_paid_at_count),0),
  'settlement_item_gross_idr',coalesce(sum(coalesce(bt.settlement_gross_idr,0)),0),
  'settlement_fee_idr',(select fee_idr from settlement_totals),
  'settlement_net_idr',(select net_idr from settlement_totals),
  'settlement_received_idr',(select received_idr from settlement_totals),
  'settlement_gross_idr',(select gross_idr from settlement_totals),
  'matched_settlements',(select settlement_count from settlement_totals),
  'branches',coalesce(jsonb_agg(jsonb_build_object(
    'branch_id',bs.branch_id,'code',bs.code,'name',bs.name,'timezone',bs.timezone,
    'gross_sales_idr',bs.gross_sales_idr,'discount_idr',bs.discount_idr,
    'refund_idr',coalesce(br.refund_idr,0),'net_sales_idr',bs.net_before_refund_idr-coalesce(br.refund_idr,0),
    'paid_transactions',bs.paid_transactions,'legacy_paid_at_count',bs.legacy_paid_at_count,'settlement_item_gross_idr',coalesce(bt.settlement_gross_idr,0),
    'matched_settlements',coalesce(bt.matched_settlements,0)
  ) order by bs.code),'[]'::jsonb)
 ) into v_result
 from branch_sales bs left join branch_refunds br on br.branch_id=bs.branch_id
 left join branch_settlements bt on bt.branch_id=bs.branch_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.sales_monitor.read','executive_sales_monitor',p_tenant_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'from_date',p_from_date,'through_date',p_through_date,
   'branch_ids',p_branch_ids,'paid_transactions',v_result->'paid_transactions',
   'legacy_paid_at_count',v_result->'legacy_paid_at_count'));
 return v_result;
end $$;
revoke all on function public.executive_get_sales_monitor(uuid,uuid,uuid[],date,date) from public,anon,authenticated;
grant execute on function public.executive_get_sales_monitor(uuid,uuid,uuid[],date,date) to service_role;

  or p_requested_action<>'approve_or_reject'
  or p_request_payload is null or jsonb_typeof(p_request_payload)<>'object'
  or length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 160
  or (p_expires_at is not null and (p_expires_at<=now() or p_expires_at>now()+interval '90 days')) then
  raise exception using errcode='22023',message='EXECUTIVE_APPROVAL_ENQUEUE_INPUT_INVALID';
 end if;
 select coalesce((select u.raw_app_meta_data->'platform_owner'='true'::jsonb from auth.users u where u.id=p_actor_user_id),false) into v_platform_owner;
 if not v_platform_owner and not exists(
  select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active'
   and (m.role in ('tenant_owner','tenant_admin') or m.permissions ? p_source_domain)
 ) then raise exception using errcode='42501',message='EXECUTIVE_APPROVAL_ENQUEUE_PERMISSION_REQUIRED'; end if;
 if p_source_entity='purchase_requisitions' and p_source_domain='procurement' then
  select b.id,b.tenant_id,r.status,floor(extract(epoch from r.updated_at)*1000000)::bigint
   into v_source_branch,v_source_tenant,v_source_status,v_source_version
   from public.purchase_requisitions r join public.branches b on b.id=r.branch_id
   where r.id=p_source_entity_id::uuid for update of r;
 elsif p_source_entity='hr_leave_requests' and p_source_domain='hr' then
  select l.branch_id,l.tenant_id,l.status,floor(extract(epoch from l.updated_at)*1000000)::bigint
   into v_source_branch,v_source_tenant,v_source_status,v_source_version
   from public.hr_leave_requests l where l.id=p_source_entity_id::uuid for update;
 else
  raise exception using errcode='22023',message='EXECUTIVE_APPROVAL_SOURCE_ADAPTER_UNSUPPORTED';
 end if;
 if v_source_branch is null or v_source_tenant is distinct from p_tenant_id or v_source_branch is distinct from p_branch_id then
  raise exception using errcode='42501',message='EXECUTIVE_APPROVAL_SOURCE_SCOPE_DENIED';
 end if;
 if v_source_status<>'submitted' then raise exception using errcode='23514',message='EXECUTIVE_APPROVAL_SOURCE_NOT_SUBMITTED'; end if;
 if not v_platform_owner
  and not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('tenant_owner','tenant_admin'))
  and not exists(select 1 from public.branch_assignments ba where ba.branch_id=p_branch_id and ba.user_id=p_actor_user_id
    and ba.employment_status='active' and ba.starts_on<=current_date and (ba.ends_on is null or ba.ends_on>=current_date)) then
  raise exception using errcode='42501',message='EXECUTIVE_APPROVAL_ENQUEUE_BRANCH_SCOPE_DENIED';
 end if;
 insert into public.executive_approval_items(tenant_id,branch_id,source_domain,source_entity,source_entity_id,
  source_version,requested_action,request_payload,created_by,expires_at,idempotency_key)
 values(p_tenant_id,p_branch_id,p_source_domain,p_source_entity,p_source_entity_id,v_source_version,
  p_requested_action,p_request_payload,p_actor_user_id,p_expires_at,p_idempotency_key)
 on conflict(tenant_id,idempotency_key) do nothing;
 get diagnostics v_inserted=row_count;
 select * into v_item from public.executive_approval_items where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if v_item.source_entity_id is distinct from p_source_entity_id or v_item.source_entity is distinct from p_source_entity
  or v_item.source_domain is distinct from p_source_domain or v_item.requested_action is distinct from p_requested_action
  or v_item.request_payload is distinct from p_request_payload
  or v_item.source_version is distinct from v_source_version or v_item.branch_id is distinct from p_branch_id
  or v_item.created_by is distinct from p_actor_user_id then
  raise exception using errcode='23505',message='EXECUTIVE_APPROVAL_ENQUEUE_IDEMPOTENCY_KEY_REUSED';
 end if;
 if v_inserted=1 then
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'executive.approval.enqueued','executive_approval_item',v_item.id::text,
   jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'source_domain',p_source_domain,
    'source_entity',p_source_entity,'source_entity_id',p_source_entity_id,'source_version',v_source_version));
 end if;
 return jsonb_build_object('id',v_item.id,'status',v_item.status,'version',v_item.version,'duplicate',v_inserted=0);
end $enqueue$;
revoke all on function public.executive_enqueue_approval(uuid,uuid,uuid,text,text,text,text,jsonb,text,timestamptz) from public,anon,authenticated;
grant execute on function public.executive_enqueue_approval(uuid,uuid,uuid,text,text,text,text,jsonb,text,timestamptz) to service_role;

-- T02: approve/reject and source mutation are committed in one PostgreSQL transaction.
create or replace function public.executive_decide_approval(
 p_tenant_id uuid,p_actor_user_id uuid,p_approval_id uuid,p_expected_version bigint,
 p_idempotency_key text,p_decision text,p_reason text
) returns jsonb language plpgsql security definer set search_path='' as $decision$
declare v public.executive_approval_items%rowtype; v_prior public.executive_approval_decisions%rowtype;
 v_platform_owner boolean; v_tenant_admin boolean; v_delegation_id uuid; v_source_version bigint; v_mutation jsonb;
begin
 if p_tenant_id is null or p_actor_user_id is null or p_approval_id is null
  or p_expected_version is null or p_expected_version<0 or p_decision is null
  or p_decision not in ('approved','rejected')
  or length(btrim(coalesce(p_reason,''))) not between 8 and 2000
  or length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 160 then
  raise exception using errcode='22023',message='EXECUTIVE_APPROVAL_DECISION_INPUT_INVALID';
 end if;
 select * into v_prior from public.executive_approval_decisions where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then
  if v_prior.approval_id is distinct from p_approval_id or v_prior.actor_user_id is distinct from p_actor_user_id
   or v_prior.decision is distinct from p_decision or v_prior.reason is distinct from btrim(p_reason) then
   raise exception using errcode='23505',message='EXECUTIVE_APPROVAL_DECISION_IDEMPOTENCY_KEY_REUSED';
  end if;
  return jsonb_build_object('approval_id',v_prior.approval_id,'decision',v_prior.decision,'duplicate',true,
   'source_mutation_id',v_prior.source_mutation_id);
 end if;
 select * into v from public.executive_approval_items where tenant_id=p_tenant_id and id=p_approval_id for update;
 if not found then raise exception using errcode='P0002',message='EXECUTIVE_APPROVAL_NOT_FOUND'; end if;
 -- Recheck after the item lock to make concurrent decision retries idempotent.
 select * into v_prior from public.executive_approval_decisions where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then
  if v_prior.approval_id is distinct from p_approval_id or v_prior.actor_user_id is distinct from p_actor_user_id
   or v_prior.decision is distinct from p_decision or v_prior.reason is distinct from btrim(p_reason) then
   raise exception using errcode='23505',message='EXECUTIVE_APPROVAL_DECISION_IDEMPOTENCY_KEY_REUSED';
  end if;
  return jsonb_build_object('approval_id',v_prior.approval_id,'decision',v_prior.decision,'duplicate',true,
   'source_mutation_id',v_prior.source_mutation_id);
 end if;
 if v.version<>p_expected_version then raise exception using errcode='40001',message='EXECUTIVE_APPROVAL_STALE_VERSION'; end if;
 if v.status<>'claimed' or v.claimed_by<>p_actor_user_id or v.claim_expires_at<=now()
  or (v.expires_at is not null and v.expires_at<=now()) then
  raise exception using errcode='23514',message='EXECUTIVE_APPROVAL_ACTIVE_CLAIM_REQUIRED';
 end if;
 select coalesce((select u.raw_app_meta_data->'platform_owner'='true'::jsonb from auth.users u where u.id=p_actor_user_id),false) into v_platform_owner;
 select exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id
  and m.status='active' and m.role in ('tenant_owner','tenant_admin')) into v_tenant_admin;
 if not v_platform_owner and not v_tenant_admin then
  if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active') then
   raise exception using errcode='42501',message='EXECUTIVE_APPROVAL_DECISION_MEMBERSHIP_REQUIRED';
  end if;
  if not exists(select 1 from public.branch_assignments ba where ba.branch_id=v.branch_id and ba.user_id=p_actor_user_id
    and ba.employment_status='active' and ba.starts_on<=current_date and (ba.ends_on is null or ba.ends_on>=current_date)) then
   raise exception using errcode='42501',message='EXECUTIVE_APPROVAL_DECISION_BRANCH_SCOPE_DENIED';
  end if;
  select d.id into v_delegation_id from public.executive_approval_delegations d
   where d.tenant_id=p_tenant_id and d.delegate_user_id=p_actor_user_id and d.revoked_at is null
    and d.valid_from<=now() and d.valid_until>now() and d.source_domains @> array[v.source_domain]
   order by d.valid_from desc limit 1;
  if v_delegation_id is null then raise exception using errcode='42501',message='EXECUTIVE_APPROVAL_DELEGATION_REQUIRED'; end if;
 end if;
 if v.created_by=p_actor_user_id then raise exception using errcode='42501',message='EXECUTIVE_APPROVAL_SELF_APPROVAL_DENIED'; end if;
 if v.source_entity_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}
create or replace function public.executive_get_sales_monitor(
 p_tenant_id uuid,p_actor_user_id uuid,p_branch_ids uuid[],p_from_date date,p_through_date date
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_allowed boolean; v_count integer; v_result jsonb;
begin
 select exists(
  select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active'
   and (m.role in ('tenant_owner','tenant_admin') or m.permissions ? 'executive.command_center.read')
 ) or coalesce((select u.raw_app_meta_data->'platform_owner'='true'::jsonb from auth.users u where u.id=p_actor_user_id),false)
 into v_allowed;
 if not v_allowed then raise exception using errcode='42501',message='EXECUTIVE_COMMAND_CENTER_PERMISSION_REQUIRED'; end if;
 if p_branch_ids is null or cardinality(p_branch_ids)<1 or cardinality(p_branch_ids)>150
    or p_from_date is null or p_through_date is null or p_through_date<p_from_date
    or p_through_date-p_from_date>92 then
  raise exception using errcode='22023',message='EXECUTIVE_SALES_MONITOR_INPUT_INVALID';
 end if;
 if exists(select 1 from public.branches b where b.id=any(p_branch_ids) and b.tenant_id<>p_tenant_id) then
  raise exception using errcode='42501',message='EXECUTIVE_SALES_MONITOR_TENANT_SCOPE_DENIED';
 end if;
 if not (coalesce((select u.raw_app_meta_data->'platform_owner'='true'::jsonb from auth.users u where u.id=p_actor_user_id),false)
   or exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('tenant_owner','tenant_admin'))) then
  if exists(select 1 from unnest(p_branch_ids) bid where not exists(
    select 1 from public.branch_assignments ba where ba.branch_id=bid and ba.user_id=p_actor_user_id
      and ba.employment_status='active' and ba.starts_on<=current_date and (ba.ends_on is null or ba.ends_on>=current_date)
  )) then raise exception using errcode='42501',message='EXECUTIVE_SALES_MONITOR_BRANCH_SCOPE_DENIED'; end if;
 end if;
 select count(*) into v_count from public.branches b where b.id=any(p_branch_ids) and b.tenant_id=p_tenant_id;
 if v_count<>cardinality(p_branch_ids) then raise exception using errcode='42501',message='EXECUTIVE_SALES_MONITOR_BRANCH_SCOPE_DENIED'; end if;
 if exists(select 1 from public.pos_sales s where s.branch_id=any(p_branch_ids)
   and s.payment_status in ('paid','refunded') and s.paid_at is not null
   and s.subtotal_idr-s.discount_idr<>s.total_idr) then
  raise exception using errcode='23514',message='EXECUTIVE_SALES_SOURCE_TOTAL_MISMATCH';
 end if;
 if exists(
  select s.id from public.pos_sales s join public.refund_records r on r.pos_sale_id=s.id and r.status='processed'
  join public.branches b on b.id=s.branch_id and b.tenant_id=p_tenant_id
  where s.branch_id=any(p_branch_ids) and s.paid_at is not null
   and (r.processed_at at time zone b.timezone)::date between p_from_date and p_through_date
  group by s.id,s.total_idr having sum(r.amount_idr)>s.total_idr
 ) then raise exception using errcode='23514',message='EXECUTIVE_PROCESSED_REFUND_EXCEEDS_SALE'; end if;
 with branch_sales as (
  select b.id branch_id,b.code,b.name,b.timezone,
   coalesce(sum(s.subtotal_idr) filter(where s.payment_status in ('paid','refunded')),0)::bigint gross_sales_idr,
   coalesce(sum(s.discount_idr) filter(where s.payment_status in ('paid','refunded')),0)::bigint discount_idr,
   coalesce(sum(s.total_idr) filter(where s.payment_status in ('paid','refunded')),0)::bigint net_before_refund_idr,
   count(s.id) filter(where s.payment_status in ('paid','refunded'))::integer paid_transactions,
   count(s.id) filter(where s.payment_status in ('paid','refunded') and s.paid_at_source='legacy_created_at_backfill')::integer legacy_paid_at_count
  from public.branches b left join public.pos_sales s on s.branch_id=b.id
   and s.paid_at is not null and s.business_date between p_from_date and p_through_date
  where b.id=any(p_branch_ids) and b.tenant_id=p_tenant_id group by b.id,b.code,b.name,b.timezone
 ), branch_refunds as (
  select r.branch_id,coalesce(sum(r.amount_idr),0)::bigint refund_idr
  from public.refund_records r join public.branches b on b.id=r.branch_id and b.tenant_id=p_tenant_id
  where r.branch_id=any(p_branch_ids) and r.pos_sale_id is not null and r.status='processed'
    and (r.processed_at at time zone b.timezone)::date between p_from_date and p_through_date
  group by r.branch_id
 ), branch_settlements as (
  -- Allocate only the source item amount to a branch. Provider-level fee/net/
  -- received totals are calculated once per distinct settlement below.
  select s.branch_id,coalesce(sum(psi.amount_idr),0)::bigint settlement_gross_idr,
   count(distinct ps.id)::integer matched_settlements
  from public.payment_settlement_items psi
  join public.pos_sales s on s.id=psi.pos_sale_id
  join public.branches b on b.id=s.branch_id and b.tenant_id=p_tenant_id
  join public.payment_settlements ps on ps.id=psi.settlement_id
  where s.branch_id=any(p_branch_ids) and ps.status='matched'
    and ps.settlement_date between p_from_date and p_through_date
  group by s.branch_id
 ), settlement_totals as (
  select coalesce(sum(ps.gross_amount_idr),0)::bigint gross_idr,
   coalesce(sum(ps.fee_amount_idr),0)::bigint fee_idr,
   coalesce(sum(ps.net_amount_idr),0)::bigint net_idr,
   coalesce(sum(ps.received_amount_idr),0)::bigint received_idr,
   count(*)::integer settlement_count
  from public.payment_settlements ps
  where ps.status='matched' and ps.settlement_date between p_from_date and p_through_date
   and exists(select 1 from public.payment_settlement_items psi
    join public.pos_sales s on s.id=psi.pos_sale_id
    join public.branches b on b.id=s.branch_id
    where psi.settlement_id=ps.id and b.tenant_id=p_tenant_id and s.branch_id=any(p_branch_ids))
   and not exists(select 1 from public.payment_settlement_items psi
    join public.pos_sales s on s.id=psi.pos_sale_id
    join public.branches b on b.id=s.branch_id
    where psi.settlement_id=ps.id and (b.tenant_id<>p_tenant_id or not (s.branch_id=any(p_branch_ids))))
 )
 select jsonb_build_object(
  'tenant_id',p_tenant_id,'from_date',p_from_date,'through_date',p_through_date,
  'branch_count',count(*),
  'gross_sales_idr',coalesce(sum(bs.gross_sales_idr),0),
  'discount_idr',coalesce(sum(bs.discount_idr),0),
  'refund_idr',coalesce(sum(coalesce(br.refund_idr,0)),0),
  'net_sales_idr',coalesce(sum(bs.net_before_refund_idr-coalesce(br.refund_idr,0)),0),
  'paid_transactions',coalesce(sum(bs.paid_transactions),0),
  'legacy_paid_at_count',coalesce(sum(bs.legacy_paid_at_count),0),
  'settlement_item_gross_idr',coalesce(sum(coalesce(bt.settlement_gross_idr,0)),0),
  'settlement_fee_idr',(select fee_idr from settlement_totals),
  'settlement_net_idr',(select net_idr from settlement_totals),
  'settlement_received_idr',(select received_idr from settlement_totals),
  'settlement_gross_idr',(select gross_idr from settlement_totals),
  'matched_settlements',(select settlement_count from settlement_totals),
  'branches',coalesce(jsonb_agg(jsonb_build_object(
    'branch_id',bs.branch_id,'code',bs.code,'name',bs.name,'timezone',bs.timezone,
    'gross_sales_idr',bs.gross_sales_idr,'discount_idr',bs.discount_idr,
    'refund_idr',coalesce(br.refund_idr,0),'net_sales_idr',bs.net_before_refund_idr-coalesce(br.refund_idr,0),
    'paid_transactions',bs.paid_transactions,'legacy_paid_at_count',bs.legacy_paid_at_count,'settlement_item_gross_idr',coalesce(bt.settlement_gross_idr,0),
    'matched_settlements',coalesce(bt.matched_settlements,0)
  ) order by bs.code),'[]'::jsonb)
 ) into v_result
 from branch_sales bs left join branch_refunds br on br.branch_id=bs.branch_id
 left join branch_settlements bt on bt.branch_id=bs.branch_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.sales_monitor.read','executive_sales_monitor',p_tenant_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'from_date',p_from_date,'through_date',p_through_date,
   'branch_ids',p_branch_ids,'paid_transactions',v_result->'paid_transactions',
   'legacy_paid_at_count',v_result->'legacy_paid_at_count'));
 return v_result;
end $$;
revoke all on function public.executive_get_sales_monitor(uuid,uuid,uuid[],date,date) from public,anon,authenticated;
grant execute on function public.executive_get_sales_monitor(uuid,uuid,uuid[],date,date) to service_role;
 then
  raise exception using errcode='22023',message='EXECUTIVE_APPROVAL_SOURCE_ID_INVALID';
 end if;
 if v.source_domain='procurement' and v.source_entity='purchase_requisitions' then
  perform 1 from public.purchase_requisitions r join public.branches b on b.id=r.branch_id
   where r.id=v.source_entity_id::uuid and b.tenant_id=p_tenant_id and r.branch_id=v.branch_id
    and r.status='submitted' and floor(extract(epoch from r.updated_at)*1000000)::bigint=v.source_version for update of r;
  if not found then raise exception using errcode='40001',message='EXECUTIVE_APPROVAL_SOURCE_VERSION_MISMATCH'; end if;
  v_source_version:=v.source_version;
  v_mutation:=public.erp_transition_purchase_requisition(v.source_entity_id::uuid,p_decision,p_actor_user_id,null);
 elsif v.source_domain='hr' and v.source_entity='hr_leave_requests' then
  perform 1 from public.hr_leave_requests l where l.id=v.source_entity_id::uuid and l.tenant_id=p_tenant_id
   and l.branch_id=v.branch_id and l.status='submitted'
   and floor(extract(epoch from l.updated_at)*1000000)::bigint=v.source_version for update of l;
  if not found then raise exception using errcode='40001',message='EXECUTIVE_APPROVAL_SOURCE_VERSION_MISMATCH'; end if;
  v_source_version:=v.source_version;
  v_mutation:=public.hr_review_leave_request(v.source_entity_id::uuid,p_actor_user_id,p_decision='approved',btrim(p_reason));
 else
  raise exception using errcode='0A000',message='EXECUTIVE_APPROVAL_SOURCE_ADAPTER_UNSUPPORTED';
 end if;
 insert into public.executive_approval_decisions(tenant_id,approval_id,actor_user_id,decision,reason,source_version,source_mutation_id,delegation_id,idempotency_key)
 values(p_tenant_id,p_approval_id,p_actor_user_id,p_decision,btrim(p_reason),v_source_version,v.source_entity_id,v_delegation_id,p_idempotency_key);
 update public.executive_approval_items set status=p_decision,claimed_by=null,claimed_at=null,claim_expires_at=null,
  version=version+1,updated_at=now() where tenant_id=p_tenant_id and id=p_approval_id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.'||p_decision,'executive_approval_item',p_approval_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',v.branch_id,'source_domain',v.source_domain,
   'source_entity',v.source_entity,'source_entity_id',v.source_entity_id,'source_version',v_source_version,
   'source_mutation',v_mutation,'delegation_id',v_delegation_id,'reason',btrim(p_reason)));
 return jsonb_build_object('approval_id',v.id,'decision',p_decision,'version',v.version,
  'source_mutation_id',v.source_entity_id,'duplicate',false);
end $decision$;
revoke all on function public.executive_decide_approval(uuid,uuid,uuid,bigint,text,text,text) from public,anon,authenticated;
grant execute on function public.executive_decide_approval(uuid,uuid,uuid,bigint,text,text,text) to service_role;

-- T01: authoritative paid-sales, processed-refund and settlement facts by branch-local date.
create or replace function public.executive_get_sales_monitor(
 p_tenant_id uuid,p_actor_user_id uuid,p_branch_ids uuid[],p_from_date date,p_through_date date
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_allowed boolean; v_count integer; v_result jsonb;
begin
 select exists(
  select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active'
   and (m.role in ('tenant_owner','tenant_admin') or m.permissions ? 'executive.command_center.read')
 ) or coalesce((select u.raw_app_meta_data->'platform_owner'='true'::jsonb from auth.users u where u.id=p_actor_user_id),false)
 into v_allowed;
 if not v_allowed then raise exception using errcode='42501',message='EXECUTIVE_COMMAND_CENTER_PERMISSION_REQUIRED'; end if;
 if p_branch_ids is null or cardinality(p_branch_ids)<1 or cardinality(p_branch_ids)>150
    or p_from_date is null or p_through_date is null or p_through_date<p_from_date
    or p_through_date-p_from_date>92 then
  raise exception using errcode='22023',message='EXECUTIVE_SALES_MONITOR_INPUT_INVALID';
 end if;
 if exists(select 1 from public.branches b where b.id=any(p_branch_ids) and b.tenant_id<>p_tenant_id) then
  raise exception using errcode='42501',message='EXECUTIVE_SALES_MONITOR_TENANT_SCOPE_DENIED';
 end if;
 if not (coalesce((select u.raw_app_meta_data->'platform_owner'='true'::jsonb from auth.users u where u.id=p_actor_user_id),false)
   or exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('tenant_owner','tenant_admin'))) then
  if exists(select 1 from unnest(p_branch_ids) bid where not exists(
    select 1 from public.branch_assignments ba where ba.branch_id=bid and ba.user_id=p_actor_user_id
      and ba.employment_status='active' and ba.starts_on<=current_date and (ba.ends_on is null or ba.ends_on>=current_date)
  )) then raise exception using errcode='42501',message='EXECUTIVE_SALES_MONITOR_BRANCH_SCOPE_DENIED'; end if;
 end if;
 select count(*) into v_count from public.branches b where b.id=any(p_branch_ids) and b.tenant_id=p_tenant_id;
 if v_count<>cardinality(p_branch_ids) then raise exception using errcode='42501',message='EXECUTIVE_SALES_MONITOR_BRANCH_SCOPE_DENIED'; end if;
 if exists(select 1 from public.pos_sales s where s.branch_id=any(p_branch_ids)
   and s.payment_status in ('paid','refunded') and s.paid_at is not null
   and s.subtotal_idr-s.discount_idr<>s.total_idr) then
  raise exception using errcode='23514',message='EXECUTIVE_SALES_SOURCE_TOTAL_MISMATCH';
 end if;
 if exists(
  select s.id from public.pos_sales s join public.refund_records r on r.pos_sale_id=s.id and r.status='processed'
  join public.branches b on b.id=s.branch_id and b.tenant_id=p_tenant_id
  where s.branch_id=any(p_branch_ids) and s.paid_at is not null
   and (r.processed_at at time zone b.timezone)::date between p_from_date and p_through_date
  group by s.id,s.total_idr having sum(r.amount_idr)>s.total_idr
 ) then raise exception using errcode='23514',message='EXECUTIVE_PROCESSED_REFUND_EXCEEDS_SALE'; end if;
 with branch_sales as (
  select b.id branch_id,b.code,b.name,b.timezone,
   coalesce(sum(s.subtotal_idr) filter(where s.payment_status in ('paid','refunded')),0)::bigint gross_sales_idr,
   coalesce(sum(s.discount_idr) filter(where s.payment_status in ('paid','refunded')),0)::bigint discount_idr,
   coalesce(sum(s.total_idr) filter(where s.payment_status in ('paid','refunded')),0)::bigint net_before_refund_idr,
   count(s.id) filter(where s.payment_status in ('paid','refunded'))::integer paid_transactions,
   count(s.id) filter(where s.payment_status in ('paid','refunded') and s.paid_at_source='legacy_created_at_backfill')::integer legacy_paid_at_count
  from public.branches b left join public.pos_sales s on s.branch_id=b.id
   and s.paid_at is not null and s.business_date between p_from_date and p_through_date
  where b.id=any(p_branch_ids) and b.tenant_id=p_tenant_id group by b.id,b.code,b.name,b.timezone
 ), branch_refunds as (
  select r.branch_id,coalesce(sum(r.amount_idr),0)::bigint refund_idr
  from public.refund_records r join public.branches b on b.id=r.branch_id and b.tenant_id=p_tenant_id
  where r.branch_id=any(p_branch_ids) and r.pos_sale_id is not null and r.status='processed'
    and (r.processed_at at time zone b.timezone)::date between p_from_date and p_through_date
  group by r.branch_id
 ), branch_settlements as (
  -- Allocate only the source item amount to a branch. Provider-level fee/net/
  -- received totals are calculated once per distinct settlement below.
  select s.branch_id,coalesce(sum(psi.amount_idr),0)::bigint settlement_gross_idr,
   count(distinct ps.id)::integer matched_settlements
  from public.payment_settlement_items psi
  join public.pos_sales s on s.id=psi.pos_sale_id
  join public.branches b on b.id=s.branch_id and b.tenant_id=p_tenant_id
  join public.payment_settlements ps on ps.id=psi.settlement_id
  where s.branch_id=any(p_branch_ids) and ps.status='matched'
    and ps.settlement_date between p_from_date and p_through_date
  group by s.branch_id
 ), settlement_totals as (
  select coalesce(sum(ps.gross_amount_idr),0)::bigint gross_idr,
   coalesce(sum(ps.fee_amount_idr),0)::bigint fee_idr,
   coalesce(sum(ps.net_amount_idr),0)::bigint net_idr,
   coalesce(sum(ps.received_amount_idr),0)::bigint received_idr,
   count(*)::integer settlement_count
  from public.payment_settlements ps
  where ps.status='matched' and ps.settlement_date between p_from_date and p_through_date
   and exists(select 1 from public.payment_settlement_items psi
    join public.pos_sales s on s.id=psi.pos_sale_id
    join public.branches b on b.id=s.branch_id
    where psi.settlement_id=ps.id and b.tenant_id=p_tenant_id and s.branch_id=any(p_branch_ids))
   and not exists(select 1 from public.payment_settlement_items psi
    join public.pos_sales s on s.id=psi.pos_sale_id
    join public.branches b on b.id=s.branch_id
    where psi.settlement_id=ps.id and (b.tenant_id<>p_tenant_id or not (s.branch_id=any(p_branch_ids))))
 )
 select jsonb_build_object(
  'tenant_id',p_tenant_id,'from_date',p_from_date,'through_date',p_through_date,
  'branch_count',count(*),
  'gross_sales_idr',coalesce(sum(bs.gross_sales_idr),0),
  'discount_idr',coalesce(sum(bs.discount_idr),0),
  'refund_idr',coalesce(sum(coalesce(br.refund_idr,0)),0),
  'net_sales_idr',coalesce(sum(bs.net_before_refund_idr-coalesce(br.refund_idr,0)),0),
  'paid_transactions',coalesce(sum(bs.paid_transactions),0),
  'legacy_paid_at_count',coalesce(sum(bs.legacy_paid_at_count),0),
  'settlement_item_gross_idr',coalesce(sum(coalesce(bt.settlement_gross_idr,0)),0),
  'settlement_fee_idr',(select fee_idr from settlement_totals),
  'settlement_net_idr',(select net_idr from settlement_totals),
  'settlement_received_idr',(select received_idr from settlement_totals),
  'settlement_gross_idr',(select gross_idr from settlement_totals),
  'matched_settlements',(select settlement_count from settlement_totals),
  'branches',coalesce(jsonb_agg(jsonb_build_object(
    'branch_id',bs.branch_id,'code',bs.code,'name',bs.name,'timezone',bs.timezone,
    'gross_sales_idr',bs.gross_sales_idr,'discount_idr',bs.discount_idr,
    'refund_idr',coalesce(br.refund_idr,0),'net_sales_idr',bs.net_before_refund_idr-coalesce(br.refund_idr,0),
    'paid_transactions',bs.paid_transactions,'legacy_paid_at_count',bs.legacy_paid_at_count,'settlement_item_gross_idr',coalesce(bt.settlement_gross_idr,0),
    'matched_settlements',coalesce(bt.matched_settlements,0)
  ) order by bs.code),'[]'::jsonb)
 ) into v_result
 from branch_sales bs left join branch_refunds br on br.branch_id=bs.branch_id
 left join branch_settlements bt on bt.branch_id=bs.branch_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.sales_monitor.read','executive_sales_monitor',p_tenant_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'from_date',p_from_date,'through_date',p_through_date,
   'branch_ids',p_branch_ids,'paid_transactions',v_result->'paid_transactions',
   'legacy_paid_at_count',v_result->'legacy_paid_at_count'));
 return v_result;
end $$;
revoke all on function public.executive_get_sales_monitor(uuid,uuid,uuid[],date,date) from public,anon,authenticated;
grant execute on function public.executive_get_sales_monitor(uuid,uuid,uuid[],date,date) to service_role;
