-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Delivery extensions are branch/tenant scoped. Tenant is derived by joining orders.branch_id
-- to branches; no caller-supplied tenant_id is trusted.
-- Provider webhook ingress must verify provider signatures in a dedicated endpoint before
-- inserting provider events. Authenticated staff actions below do not replace that verifier.

create table if not exists public.delivery_dispatches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  order_id uuid not null references public.orders(id) on delete restrict,
  provider text not null check (length(btrim(provider)) between 2 and 40),
  provider_service text null,
  provider_order_reference text null,
  tracking_number text null,
  tracking_url text null,
  courier_name text null,
  courier_phone text null,
  delivery_fee_idr bigint not null check (delivery_fee_idr>=0),
  cod_amount_idr bigint not null default 0 check (cod_amount_idr>=0),
  status text not null default 'quoted' check (status in ('quoted','booked','picked_up','in_transit','delivered','failed','cancelled')),
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  booked_at timestamptz null,
  delivered_at timestamptz null,
  failed_at timestamptz null,
  failure_reason text null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,idempotency_key),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check (cod_amount_idr=0 or cod_amount_idr>=0),
  check (status<>'delivered' or delivered_at is not null)
);
create unique index if not exists delivery_dispatch_provider_reference_uq
 on public.delivery_dispatches(tenant_id,provider,provider_order_reference)
 where provider_order_reference is not null;
create index if not exists delivery_dispatch_order_idx
 on public.delivery_dispatches(tenant_id,order_id,created_at desc);

create table if not exists public.delivery_provider_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  dispatch_id uuid not null,
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  provider_status text null,
  occurred_at timestamptz not null,
  payload_hash text not null check (length(payload_hash) between 32 and 128),
  processed_at timestamptz null,
  processing_status text not null default 'received' check (processing_status in ('received','processed','ignored','rejected')),
  processing_note text null,
  created_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,provider,provider_event_id),
  foreign key (tenant_id,dispatch_id) references public.delivery_dispatches(tenant_id,id) on delete restrict
);
create index if not exists delivery_provider_events_dispatch_idx
 on public.delivery_provider_events(tenant_id,dispatch_id,occurred_at desc);

create table if not exists public.delivery_proof_of_delivery (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  dispatch_id uuid not null,
  proof_type text not null check (proof_type in ('photo','signature','recipient_name','otp_verified','geo_check')),
  storage_object_path text null,
  recipient_name text null,
  latitude numeric(9,6) null,
  longitude numeric(9,6) null,
  verification_reference text null,
  captured_at timestamptz not null,
  captured_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (tenant_id,id),
  foreign key (tenant_id,dispatch_id) references public.delivery_dispatches(tenant_id,id) on delete restrict,
  check ((latitude is null)=(longitude is null)),
  check (latitude is null or latitude between -90 and 90),
  check (longitude is null or longitude between -180 and 180),
  check (proof_type not in ('photo','signature') or storage_object_path is not null),
  check (proof_type<>'recipient_name' or length(btrim(coalesce(recipient_name,'')))>=2),
  check (proof_type<>'otp_verified' or length(btrim(coalesce(verification_reference,'')))>=8)
);
create index if not exists delivery_pod_dispatch_idx
 on public.delivery_proof_of_delivery(tenant_id,dispatch_id,captured_at desc);

do $$
declare t text;
begin
 foreach t in array array['delivery_dispatches','delivery_provider_events','delivery_proof_of_delivery'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;

create or replace function public.delivery_audit_insert()
returns trigger language plpgsql security invoker set search_path=''
as $$
declare v jsonb:=to_jsonb(new); v_dispatch_id text;
begin
 v_dispatch_id:=coalesce(v->>'id',v->>'dispatch_id');
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values (nullif(coalesce(v->>'created_by',v->>'captured_by'),'')::uuid,
   'delivery.'||tg_table_name||'.insert',tg_table_name,v->>'id',
   jsonb_build_object('tenant_id',v->>'tenant_id','branch_id',v->>'branch_id','dispatch_id',v_dispatch_id));
 return new;
end $$;
revoke all on function public.delivery_audit_insert() from public,anon,authenticated;
drop trigger if exists delivery_dispatch_audit_insert on public.delivery_dispatches;
create trigger delivery_dispatch_audit_insert after insert on public.delivery_dispatches
for each row execute function public.delivery_audit_insert();
drop trigger if exists delivery_pod_audit_insert on public.delivery_proof_of_delivery;
create trigger delivery_pod_audit_insert after insert on public.delivery_proof_of_delivery
for each row execute function public.delivery_audit_insert();

-- Required before production use:
-- 1) Dedicated provider webhook signature verification + raw-body hashing.
-- 2) Atomic dispatch/status transition RPC that locks the order and dispatch.
-- 3) POD storage object existence, MIME, size and ownership verification.
-- 4) Reconciliation of provider fee, customer charge, COD and settlement to Finance.
