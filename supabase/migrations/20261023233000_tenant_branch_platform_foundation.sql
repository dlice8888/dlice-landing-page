-- Tenant, warehouse, branch configuration, handover, waste and integration foundations.
-- This is a staged foundation; application-wide tenant scoping and restore drills remain acceptance gates.

create table if not exists public.tenants (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,60}$'),
  legal_name text not null check (length(trim(legal_name)) between 2 and 180),
  status text not null default 'trial' check (status in ('trial','active','suspended','closed')),
  plan_code text not null default 'starter',
  settings jsonb not null default '{}'::jsonb check (jsonb_typeof(settings)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.tenants(id,slug,legal_name,status,plan_code)
values('00000000-0000-4000-8000-000000000001','dlice-default','D’Lice FnB','active','internal')
on conflict (slug) do nothing;

create table if not exists public.tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  role text not null check (role in ('tenant_owner','tenant_admin','branch_manager','cashier','inventory','production','finance','viewer','tenant_member')),
  permissions jsonb not null default '[]'::jsonb check (jsonb_typeof(permissions)='array'),
  status text not null default 'active' check (status in ('invited','active','suspended','revoked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,user_id)
);
create index if not exists tenant_memberships_user_status_idx on public.tenant_memberships(user_id,status,tenant_id);

alter table public.branches add column if not exists tenant_id uuid;
update public.branches set tenant_id='00000000-0000-4000-8000-000000000001' where tenant_id is null;
alter table public.branches alter column tenant_id set default '00000000-0000-4000-8000-000000000001';
alter table public.branches alter column tenant_id set not null;
do $$ begin
  if not exists(select 1 from pg_constraint where conname='branches_tenant_id_fkey') then
    alter table public.branches add constraint branches_tenant_id_fkey foreign key(tenant_id) references public.tenants(id) on delete restrict;
  end if;
end $$;
create index if not exists branches_tenant_status_idx on public.branches(tenant_id,status);

insert into public.tenant_memberships(tenant_id,user_id,role,permissions,status)
select '00000000-0000-4000-8000-000000000001',p.user_id,
  case when p.role='owner' then 'tenant_owner' else 'tenant_member' end,
  case when p.role='owner' then '["*"]'::jsonb else coalesce(p.permissions,'[]'::jsonb) end,
  case when p.is_active then 'active' else 'suspended' end
from public.admin_profiles p
on conflict(tenant_id,user_id) do nothing;

create table if not exists public.tenant_invites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  email text not null check (length(email) between 3 and 254),
  role text not null check (role in ('tenant_admin','branch_manager','cashier','inventory','production','finance','viewer','tenant_member')),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  status text not null default 'pending' check (status in ('pending','accepted','expired','revoked')),
  invited_by uuid not null references auth.users(id) on delete restrict,
  expires_at timestamptz not null,
  accepted_by uuid references auth.users(id) on delete restrict,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists tenant_invites_tenant_status_idx on public.tenant_invites(tenant_id,status,expires_at);

create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  code text not null check (code ~ '^[A-Z0-9_-]{2,40}$'),
  name text not null check (length(trim(name)) between 2 and 120),
  warehouse_type text not null default 'branch' check (warehouse_type in ('central','branch','cold_storage','transit')),
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(tenant_id,code)
);
create unique index if not exists warehouses_one_default_per_branch_idx on public.warehouses(branch_id) where is_default;
insert into public.warehouses(tenant_id,branch_id,code,name,warehouse_type,is_default)
select b.tenant_id,b.id,'MAIN-'||replace(b.code,'-','_'),left(b.name||' - Gudang Utama',120),'branch',true
from public.branches b
on conflict(tenant_id,code) do nothing;
alter table public.branch_inventory add column if not exists warehouse_id uuid references public.warehouses(id) on delete restrict;
update public.branch_inventory bi set warehouse_id=w.id
from public.warehouses w where w.branch_id=bi.branch_id and w.is_default and bi.warehouse_id is null;
create index if not exists branch_inventory_warehouse_idx on public.branch_inventory(warehouse_id,inventory_item_id);

create table if not exists public.branch_settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  category text not null check (category in ('tax','pricing','menu','policy','timezone','fulfillment')),
  setting_key text not null check (length(trim(setting_key)) between 2 and 100),
  setting_value jsonb not null,
  effective_from date not null default current_date,
  effective_to date,
  version integer not null default 1 check (version>0),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (effective_to is null or effective_to>=effective_from),
  unique(branch_id,category,setting_key,version)
);
create index if not exists branch_settings_lookup_idx on public.branch_settings(tenant_id,branch_id,category,setting_key,effective_from desc);

create or replace function public.dlice_version_branch_setting()
returns trigger language plpgsql security invoker set search_path=public as $
begin
  update public.branch_settings
  set effective_to=case when effective_from<new.effective_from then new.effective_from-1 else effective_from end
  where branch_id=new.branch_id and category=new.category and setting_key=new.setting_key
    and effective_to is null and version<new.version;
  return new;
end;
$;
drop trigger if exists dlice_branch_setting_versioning on public.branch_settings;
create trigger dlice_branch_setting_versioning
before insert on public.branch_settings
for each row execute function public.dlice_version_branch_setting();

create table if not exists public.shift_handover_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  shift_id uuid not null references public.pos_shifts(id) on delete restrict,
  outgoing_user_id uuid not null references auth.users(id) on delete restrict,
  incoming_user_id uuid references auth.users(id) on delete restrict,
  cash_counted_idr bigint not null default 0 check (cash_counted_idr>=0),
  pending_orders jsonb not null default '[]'::jsonb check (jsonb_typeof(pending_orders)='array'),
  waste_summary jsonb not null default '[]'::jsonb check (jsonb_typeof(waste_summary)='array'),
  open_issues text,
  notes text,
  status text not null default 'submitted' check (status in ('submitted','acknowledged','exception')),
  acknowledged_at timestamptz,
  created_at timestamptz not null default now(),
  unique(shift_id)
);
create index if not exists shift_handover_branch_created_idx on public.shift_handover_records(branch_id,created_at desc);

create table if not exists public.inventory_waste_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  quantity numeric(14,3) not null check (quantity>0),
  reason_code text not null check (reason_code in ('expired','damaged','quality_reject','overproduction','spill','count_variance','other')),
  reason text not null check (length(trim(reason)) between 3 and 500),
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  payload_fingerprint text not null check (payload_fingerprint ~ '^[0-9a-f]{64} check (status in ('posted','pending_review','reversed')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(branch_id,idempotency_key)
);
create index if not exists inventory_waste_branch_created_idx on public.inventory_waste_events(branch_id,created_at desc);

create table if not exists public.integration_connections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  provider text not null check (provider ~ '^[a-z0-9][a-z0-9_-]{1,60}$'),
  display_name text not null,
  status text not null default 'disabled' check (status in ('disabled','pending','active','degraded','revoked')),
  secret_reference text,
  config jsonb not null default '{}'::jsonb check (jsonb_typeof(config)='object'),
  last_success_at timestamptz,
  last_error_at timestamptz,
  last_error_code text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,provider,display_name)
);

create table if not exists public.integration_outbox (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete restrict,
  connection_id uuid references public.integration_connections(id) on delete set null,
  event_type text not null,
  aggregate_id uuid,
  idempotency_key text not null,
  payload jsonb not null check (jsonb_typeof(payload)='object'),
  status text not null default 'pending' check (status in ('pending','processing','delivered','retry','dead_letter','cancelled')),
  attempt_count integer not null default 0 check (attempt_count>=0),
  next_attempt_at timestamptz not null default now(),
  last_error_code text,
  last_error text,
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  unique(tenant_id,idempotency_key)
);
create index if not exists integration_outbox_retry_idx on public.integration_outbox(status,next_attempt_at) where status in ('pending','retry');

create table if not exists public.backup_restore_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete restrict,
  run_type text not null check (run_type in ('backup','restore','restore_drill')),
  status text not null default 'queued' check (status in ('queued','running','succeeded','failed','verified')),
  artifact_reference text,
  started_by uuid references auth.users(id) on delete set null,
  started_at timestamptz,
  completed_at timestamptz,
  verified_at timestamptz,
  restored_at timestamptz,
  checksum_sha256 text check (checksum_sha256 is null or checksum_sha256 ~ '^[0-9a-f]{64}$'),
  error_code text,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists backup_restore_runs_type_created_idx on public.backup_restore_runs(run_type,created_at desc);

create or replace function public.erp_record_inventory_waste(
  p_branch_id uuid,p_inventory_item_id uuid,p_quantity numeric,p_reason_code text,
  p_reason text,p_actor_user_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security invoker set search_path=public as $$
declare prior public.inventory_waste_events%rowtype; event_id uuid; tenant uuid; current_qty numeric(14,3); fingerprint text;
begin
  if p_quantity is null or p_quantity<=0 or p_quantity>1000000 then raise exception 'invalid_waste_quantity'; end if;
  if p_reason_code not in ('expired','damaged','quality_reject','overproduction','spill','count_variance','other') then raise exception 'invalid_waste_reason'; end if;
  if p_reason is null or length(trim(p_reason))<3 or length(p_reason)>500 then raise exception 'waste_reason_required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>120 then raise exception 'invalid_idempotency_key'; end if;
  fingerprint:=encode(digest(jsonb_build_object('branch_id',p_branch_id,'inventory_item_id',p_inventory_item_id,'quantity',p_quantity,'reason_code',p_reason_code,'reason',trim(p_reason))::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_branch_id::text||':'||p_idempotency_key,0));
  select tenant_id into tenant from public.branches where id=p_branch_id and status='active';
  if not found then raise exception 'branch_not_active'; end if;
  select * into prior from public.inventory_waste_events where branch_id=p_branch_id and idempotency_key=p_idempotency_key for update;
  if found then
    if prior.payload_fingerprint<>fingerprint then raise exception 'idempotency_key_payload_mismatch'; end if;
    return jsonb_build_object('ok',true,'waste_id',prior.id,'replayed',true,'quantity',prior.quantity);
  end if;
  insert into public.branch_inventory(branch_id,inventory_item_id,on_hand)
  values(p_branch_id,p_inventory_item_id,0) on conflict(branch_id,inventory_item_id) do nothing;
  select on_hand into current_qty from public.branch_inventory where branch_id=p_branch_id and inventory_item_id=p_inventory_item_id for update;
  if current_qty<p_quantity then raise exception 'insufficient_stock'; end if;
  insert into public.inventory_waste_events(tenant_id,branch_id,inventory_item_id,quantity,reason_code,reason,idempotency_key,payload_fingerprint,created_by)
  values(tenant,p_branch_id,p_inventory_item_id,p_quantity,p_reason_code,left(trim(p_reason),500),p_idempotency_key,fingerprint,p_actor_user_id)
  returning id into event_id;
  update public.branch_inventory set on_hand=on_hand-p_quantity,updated_at=now()
  where branch_id=p_branch_id and inventory_item_id=p_inventory_item_id;
  insert into public.stock_movements(branch_id,inventory_item_id,movement_type,quantity,reference_type,reference_id,notes,created_by)
  values(p_branch_id,p_inventory_item_id,'waste',p_quantity,'inventory_waste',event_id,left(trim(p_reason),500),p_actor_user_id);
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'inventory_waste_posted','inventory_waste_event',event_id::text,jsonb_build_object('branch_id',p_branch_id,'inventory_item_id',p_inventory_item_id,'quantity',p_quantity,'reason_code',p_reason_code));
  return jsonb_build_object('ok',true,'waste_id',event_id,'replayed',false,'quantity',p_quantity,'on_hand',current_qty-p_quantity);
end $$;

do $$ declare t text; begin
  foreach t in array array['tenants','tenant_memberships','tenant_invites','warehouses','branch_settings','shift_handover_records','inventory_waste_events','integration_connections','integration_outbox','backup_restore_runs'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from anon,authenticated',t);
  end loop;
end $$;
revoke all on function public.dlice_version_branch_setting() from public,anon,authenticated;
revoke all on function public.erp_record_inventory_waste(uuid,uuid,numeric,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.erp_record_inventory_waste(uuid,uuid,numeric,text,text,uuid,text) to service_role;
),
  status text not null default 'posted' check (status in ('posted','pending_review','reversed')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(branch_id,idempotency_key)
);
create index if not exists inventory_waste_branch_created_idx on public.inventory_waste_events(branch_id,created_at desc);

create table if not exists public.integration_connections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  provider text not null check (provider ~ '^[a-z0-9][a-z0-9_-]{1,60}$'),
  display_name text not null,
  status text not null default 'disabled' check (status in ('disabled','pending','active','degraded','revoked')),
  secret_reference text,
  config jsonb not null default '{}'::jsonb check (jsonb_typeof(config)='object'),
  last_success_at timestamptz,
  last_error_at timestamptz,
  last_error_code text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,provider,display_name)
);

create table if not exists public.integration_outbox (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete restrict,
  connection_id uuid references public.integration_connections(id) on delete set null,
  event_type text not null,
  aggregate_id uuid,
  idempotency_key text not null,
  payload jsonb not null check (jsonb_typeof(payload)='object'),
  status text not null default 'pending' check (status in ('pending','processing','delivered','retry','dead_letter','cancelled')),
  attempt_count integer not null default 0 check (attempt_count>=0),
  next_attempt_at timestamptz not null default now(),
  last_error_code text,
  last_error text,
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  unique(tenant_id,idempotency_key)
);
create index if not exists integration_outbox_retry_idx on public.integration_outbox(status,next_attempt_at) where status in ('pending','retry');

create table if not exists public.backup_restore_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete restrict,
  run_type text not null check (run_type in ('backup','restore','restore_drill')),
  status text not null default 'queued' check (status in ('queued','running','succeeded','failed','verified')),
  artifact_reference text,
  started_by uuid references auth.users(id) on delete set null,
  started_at timestamptz,
  completed_at timestamptz,
  verified_at timestamptz,
  restored_at timestamptz,
  checksum_sha256 text check (checksum_sha256 is null or checksum_sha256 ~ '^[0-9a-f]{64}$'),
  error_code text,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists backup_restore_runs_type_created_idx on public.backup_restore_runs(run_type,created_at desc);

create or replace function public.erp_record_inventory_waste(
  p_branch_id uuid,p_inventory_item_id uuid,p_quantity numeric,p_reason_code text,
  p_reason text,p_actor_user_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security invoker set search_path=public as $$
declare prior public.inventory_waste_events%rowtype; event_id uuid; tenant uuid; current_qty numeric(14,3);
begin
  if p_quantity is null or p_quantity<=0 or p_quantity>1000000 then raise exception 'invalid_waste_quantity'; end if;
  if p_reason_code not in ('expired','damaged','quality_reject','overproduction','spill','count_variance','other') then raise exception 'invalid_waste_reason'; end if;
  if p_reason is null or length(trim(p_reason))<3 or length(p_reason)>500 then raise exception 'waste_reason_required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>120 then raise exception 'invalid_idempotency_key'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_branch_id::text||':'||p_idempotency_key,0));
  select tenant_id into tenant from public.branches where id=p_branch_id and status='active';
  if not found then raise exception 'branch_not_active'; end if;
  select * into prior from public.inventory_waste_events where branch_id=p_branch_id and idempotency_key=p_idempotency_key for update;
  if found then return jsonb_build_object('ok',true,'waste_id',prior.id,'replayed',true,'quantity',prior.quantity); end if;
  insert into public.branch_inventory(branch_id,inventory_item_id,on_hand)
  values(p_branch_id,p_inventory_item_id,0) on conflict(branch_id,inventory_item_id) do nothing;
  select on_hand into current_qty from public.branch_inventory where branch_id=p_branch_id and inventory_item_id=p_inventory_item_id for update;
  if current_qty<p_quantity then raise exception 'insufficient_stock'; end if;
  insert into public.inventory_waste_events(tenant_id,branch_id,inventory_item_id,quantity,reason_code,reason,idempotency_key,created_by)
  values(tenant,p_branch_id,p_inventory_item_id,p_quantity,p_reason_code,left(trim(p_reason),500),p_idempotency_key,p_actor_user_id)
  returning id into event_id;
  update public.branch_inventory set on_hand=on_hand-p_quantity,updated_at=now()
  where branch_id=p_branch_id and inventory_item_id=p_inventory_item_id;
  insert into public.stock_movements(branch_id,inventory_item_id,movement_type,quantity,reference_type,reference_id,notes,created_by)
  values(p_branch_id,p_inventory_item_id,'waste',p_quantity,'inventory_waste',event_id,left(trim(p_reason),500),p_actor_user_id);
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'inventory_waste_posted','inventory_waste_event',event_id::text,jsonb_build_object('branch_id',p_branch_id,'inventory_item_id',p_inventory_item_id,'quantity',p_quantity,'reason_code',p_reason_code));
  return jsonb_build_object('ok',true,'waste_id',event_id,'replayed',false,'quantity',p_quantity,'on_hand',current_qty-p_quantity);
end $$;

do $$ declare t text; begin
  foreach t in array array['tenants','tenant_memberships','tenant_invites','warehouses','branch_settings','shift_handover_records','inventory_waste_events','integration_connections','integration_outbox','backup_restore_runs'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from anon,authenticated',t);
  end loop;
end $$;
revoke all on function public.erp_record_inventory_waste(uuid,uuid,numeric,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.erp_record_inventory_waste(uuid,uuid,numeric,text,text,uuid,text) to service_role;
