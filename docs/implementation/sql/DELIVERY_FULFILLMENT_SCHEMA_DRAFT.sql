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

-- Atomically create a dispatch and advance a ready, paid order to dispatched.
create or replace function public.delivery_book_dispatch(
 p_order_id uuid,p_provider text,p_provider_service text,p_tracking_number text,
 p_tracking_url text,p_delivery_fee_idr bigint,p_cod_amount_idr bigint,
 p_idempotency_key text,p_actor_user_id uuid
) returns jsonb
language plpgsql security invoker set search_path=''
as $
declare v_order public.orders%rowtype; v_branch public.branches%rowtype; v_dispatch public.delivery_dispatches%rowtype;
begin
 if length(btrim(coalesce(p_provider,''))) not between 2 and 40
   or length(coalesce(p_idempotency_key,'')) not between 8 and 120
   or p_delivery_fee_idr<0 or p_cod_amount_idr<0 then
   raise exception using errcode='22023',message='INVALID_DELIVERY_BOOKING';
 end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found then raise exception using errcode='P0002',message='ORDER_NOT_FOUND'; end if;
 select * into v_branch from public.branches where id=v_order.branch_id and status='active';
 if not found then raise exception using errcode='23514',message='ORDER_BRANCH_NOT_ACTIVE'; end if;
 if v_order.fulfillment_status<>'ready' then raise exception using errcode='23514',message='ORDER_NOT_READY'; end if;
 if v_order.payment_status not in ('paid','verified','settled') then
   raise exception using errcode='23514',message='ORDER_PAYMENT_NOT_SETTLED';
 end if;
 if exists(select 1 from public.delivery_dispatches where tenant_id=v_branch.tenant_id and idempotency_key=p_idempotency_key) then
   raise exception using errcode='23505',message='DUPLICATE_DELIVERY_BOOKING';
 end if;
 if exists(select 1 from public.delivery_dispatches where tenant_id=v_branch.tenant_id and order_id=p_order_id and status not in ('failed','cancelled')) then
   raise exception using errcode='23505',message='ACTIVE_DISPATCH_ALREADY_EXISTS';
 end if;
 insert into public.delivery_dispatches
 (tenant_id,branch_id,order_id,provider,provider_service,tracking_number,tracking_url,
  delivery_fee_idr,cod_amount_idr,status,idempotency_key,booked_at,created_by)
 values(v_branch.tenant_id,v_branch.id,p_order_id,p_provider,p_provider_service,p_tracking_number,
  p_tracking_url,p_delivery_fee_idr,p_cod_amount_idr,'booked',p_idempotency_key,now(),p_actor_user_id)
 returning * into v_dispatch;

 update public.orders set fulfillment_status='dispatched',updated_at=now()
 where id=p_order_id and fulfillment_status='ready';
 if not found then raise exception using errcode='40001',message='ORDER_FULFILLMENT_RACE'; end if;

 insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
 values(p_order_id,'operational','ready','dispatched','Delivery dispatch booked: '||p_provider);
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.dispatch.booked','delivery_dispatch',v_dispatch.id::text,
  jsonb_build_object('tenant_id',v_branch.tenant_id,'branch_id',v_branch.id,'order_id',p_order_id,
   'provider',p_provider,'delivery_fee_idr',p_delivery_fee_idr,'cod_amount_idr',p_cod_amount_idr));
 return jsonb_build_object('dispatch_id',v_dispatch.id,'order_id',p_order_id,
  'status',v_dispatch.status,'tracking_number',v_dispatch.tracking_number,
  'delivery_fee_idr',v_dispatch.delivery_fee_idr);
end $;
revoke all on function public.delivery_book_dispatch(uuid,text,text,text,text,bigint,bigint,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_book_dispatch(uuid,text,text,text,text,bigint,bigint,text,uuid) to service_role;

create or replace function public.delivery_transition_dispatch(
 p_dispatch_id uuid,p_next_status text,p_event_id text,p_payload_hash text,p_actor_user_id uuid,p_note text
) returns jsonb language plpgsql security invoker set search_path=''
as $
declare v public.delivery_dispatches%rowtype; v_next_order_status text;
begin
 if p_next_status not in ('picked_up','in_transit','delivered','failed','cancelled')
  or length(btrim(coalesce(p_event_id,''))) not between 8 and 160
  or length(coalesce(p_payload_hash,'')) not between 32 and 128 then
  raise exception using errcode='22023',message='INVALID_DELIVERY_EVENT';
 end if;
 select * into v from public.delivery_dispatches where id=p_dispatch_id for update;
 if not found then raise exception using errcode='P0002',message='DELIVERY_DISPATCH_NOT_FOUND'; end if;
 if exists(select 1 from public.delivery_provider_events where tenant_id=v.tenant_id and provider=v.provider and provider_event_id=p_event_id) then
  raise exception using errcode='23505',message='DUPLICATE_DELIVERY_EVENT';
 end if;
 if not (
  (v.status='booked' and p_next_status in ('picked_up','failed','cancelled')) or
  (v.status='picked_up' and p_next_status in ('in_transit','failed')) or
  (v.status='in_transit' and p_next_status in ('delivered','failed'))
 ) then raise exception using errcode='23514',message='INVALID_DELIVERY_TRANSITION'; end if;
 if p_next_status='delivered' and not exists(select 1 from public.delivery_proof_of_delivery where tenant_id=v.tenant_id and dispatch_id=v.id) then
  raise exception using errcode='23514',message='DELIVERY_PROOF_REQUIRED';
 end if;
 insert into public.delivery_provider_events(tenant_id,dispatch_id,provider,provider_event_id,event_type,provider_status,occurred_at,payload_hash,processed_at,processing_status,processing_note)
 values(v.tenant_id,v.id,v.provider,p_event_id,'manual_status_update',p_next_status,now(),p_payload_hash,now(),'processed',left(coalesce(p_note,''),500));
 update public.delivery_dispatches set status=p_next_status,delivered_at=case when p_next_status='delivered' then now() else delivered_at end,
  failed_at=case when p_next_status='failed' then now() else failed_at end,
  failure_reason=case when p_next_status='failed' then left(coalesce(p_note,''),500) else failure_reason end,
  updated_by=p_actor_user_id,updated_at=now() where id=v.id returning * into v;
 if p_next_status='delivered' then
  update public.orders set fulfillment_status='fulfilled',fulfilled_at=now(),updated_at=now()
   where id=v.order_id and fulfillment_status='dispatched';
  if not found then raise exception using errcode='40001',message='ORDER_FULFILLMENT_STATE_MISMATCH'; end if;
  insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
   values(v.order_id,'operational','dispatched','fulfilled','Delivery confirmed with proof of delivery');
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.dispatch.'||p_next_status,'delivery_dispatch',v.id::text,
  jsonb_build_object('tenant_id',v.tenant_id,'branch_id',v.branch_id,'order_id',v.order_id,'event_id',p_event_id,'note',left(coalesce(p_note,''),500)));
 return jsonb_build_object('dispatch_id',v.id,'status',v.status,'order_id',v.order_id);
end $;
revoke all on function public.delivery_transition_dispatch(uuid,text,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.delivery_transition_dispatch(uuid,text,text,text,uuid,text) to service_role;

-- Required before production use:
-- 1) Dedicated provider webhook signature verification + raw-body hashing.
-- 2) Atomic dispatch/status transition RPC that locks the order and dispatch.
-- 3) POD storage object existence, MIME, size and ownership verification.
-- 4) Reconciliation of provider fee, customer charge, COD and settlement to Finance.
