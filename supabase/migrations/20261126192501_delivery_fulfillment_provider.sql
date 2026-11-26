-- D'Lice FnB OS official migration generated from reviewed domain SQL drafts.
-- Source files:
--   docs/implementation/sql/DELIVERY_FULFILLMENT_SCHEMA_DRAFT.sql
--   docs/implementation/sql/DELIVERY_PROVIDER_STORAGE_SCHEMA_DRAFT.sql
--   docs/implementation/sql/DELIVERY_ATOMIC_ADAPTERS_EXTENSION_DRAFT.sql

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
as $$
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
end $$;
revoke all on function public.delivery_book_dispatch(uuid,text,text,text,text,bigint,bigint,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_book_dispatch(uuid,text,text,text,text,bigint,bigint,text,uuid) to service_role;

create or replace function public.delivery_transition_dispatch(
 p_dispatch_id uuid,p_next_status text,p_event_id text,p_payload_hash text,p_actor_user_id uuid,p_note text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
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
 if p_next_status='failed' then
  update public.orders set fulfillment_status='failed',updated_at=now() where id=v.order_id and fulfillment_status='dispatched';
  if found then
   insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
    values(v.order_id,'operational','dispatched','failed','Delivery dispatch failed: '||left(coalesce(p_note,''),300));
  end if;
 elsif p_next_status='cancelled' then
  update public.orders set fulfillment_status='ready',updated_at=now() where id=v.order_id and fulfillment_status='dispatched';
  if found then
   insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
    values(v.order_id,'operational','dispatched','ready','Delivery booking cancelled; order returned to ready');
  end if;
 end if;
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
end $$;
revoke all on function public.delivery_transition_dispatch(uuid,text,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.delivery_transition_dispatch(uuid,text,text,text,uuid,text) to service_role;

-- POD is accepted only after the exact object exists in the private delivery-proof bucket.
-- The client cannot mark an order delivered by merely supplying a path.
create or replace function public.delivery_record_proof(
 p_dispatch_id uuid,p_proof_type text,p_storage_object_path text,p_recipient_name text,
 p_latitude numeric,p_longitude numeric,p_verification_reference text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_dispatches%rowtype; v_proof public.delivery_proof_of_delivery%rowtype;
 v_object storage.objects%rowtype; v_prefix text;
begin
 select * into v from public.delivery_dispatches where id=p_dispatch_id for update;
 if not found then raise exception using errcode='P0002',message='DELIVERY_DISPATCH_NOT_FOUND'; end if;
 if v.status not in ('booked','picked_up','in_transit') then raise exception using errcode='23514',message='DISPATCH_NOT_ACCEPTING_POD'; end if;
 if p_proof_type not in ('photo','signature','recipient_name','otp_verified','geo_check') then raise exception using errcode='22023',message='INVALID_POD_TYPE'; end if;
 if p_latitude is not null and (p_latitude not between -90 and 90 or p_longitude is null or p_longitude not between -180 and 180) then raise exception using errcode='22023',message='INVALID_POD_COORDINATES'; end if;
 if p_proof_type in ('photo','signature') then
  v_prefix:=v.tenant_id::text||'/'||v.branch_id::text||'/'||v.id::text||'/';
  if p_storage_object_path is null or left(p_storage_object_path,length(v_prefix))<>v_prefix then
   raise exception using errcode='42501',message='POD_OBJECT_PATH_SCOPE_INVALID';
  end if;
  select * into v_object from storage.objects where bucket_id='delivery-proof' and name=p_storage_object_path;
  if not found then raise exception using errcode='23514',message='POD_STORAGE_OBJECT_NOT_FOUND'; end if;
  if coalesce(v_object.metadata->>'mimetype','') not in ('image/jpeg','image/png','image/webp','application/pdf') then
   raise exception using errcode='23514',message='POD_MIME_TYPE_NOT_ALLOWED';
  end if;
  if coalesce((v_object.metadata->>'size')::bigint,0)<=0 or (v_object.metadata->>'size')::bigint>10485760 then
   raise exception using errcode='23514',message='POD_FILE_SIZE_INVALID';
  end if;
 elsif p_proof_type='recipient_name' and length(btrim(coalesce(p_recipient_name,'')))<2 then
  raise exception using errcode='22023',message='POD_RECIPIENT_REQUIRED';
 elsif p_proof_type='otp_verified' and length(btrim(coalesce(p_verification_reference,'')))<8 then
  raise exception using errcode='22023',message='POD_OTP_REFERENCE_REQUIRED';
 end if;
 insert into public.delivery_proof_of_delivery(tenant_id,dispatch_id,proof_type,storage_object_path,recipient_name,latitude,longitude,verification_reference,captured_at,captured_by)
 values(v.tenant_id,v.id,p_proof_type,p_storage_object_path,p_recipient_name,p_latitude,p_longitude,p_verification_reference,now(),p_actor_user_id)
 returning * into v_proof;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.proof.recorded','delivery_proof_of_delivery',v_proof.id::text,
  jsonb_build_object('tenant_id',v.tenant_id,'branch_id',v.branch_id,'dispatch_id',v.id,'proof_type',p_proof_type,'storage_path',p_storage_object_path));
 return jsonb_build_object('proof_id',v_proof.id,'dispatch_id',v.id,'proof_type',v_proof.proof_type,'captured_at',v_proof.captured_at);
end $$;
revoke all on function public.delivery_record_proof(uuid,text,text,text,numeric,numeric,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_record_proof(uuid,text,text,text,numeric,numeric,text,uuid) to service_role;

-- Required before production use:
-- 1) Dedicated provider webhook signature verification + raw-body hashing.
-- 2) Atomic dispatch/status transition RPC that locks the order and dispatch.
-- 3) POD storage object existence, MIME, size and ownership verification.
-- 4) Reconciliation of provider fee, customer charge, COD and settlement to Finance.

create table if not exists public.delivery_provider_configs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid null,
  provider_key text not null check(length(btrim(provider_key)) between 2 and 60),
  display_name text not null check(length(btrim(display_name)) between 2 and 100),
  credential_secret_reference text not null check(length(btrim(credential_secret_reference)) between 3 and 120),
  integration_mode text not null default 'manual' check(integration_mode in ('manual','api')),
  status text not null default 'pending' check(status in ('pending','active','suspended','revoked')),
  approved_by uuid null references auth.users(id) on delete restrict,
  approved_at timestamptz null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  unique(tenant_id,branch_id,provider_key),
  check(status<>'active' or (approved_by is not null and approved_at is not null))
);
create index if not exists delivery_provider_configs_active_idx
  on public.delivery_provider_configs(tenant_id,branch_id,status);

create table if not exists public.delivery_provider_quotes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  order_id uuid not null references public.orders(id) on delete restrict,
  provider_config_id uuid not null,
  provider_quote_id text not null,
  service_level text not null,
  currency text not null default 'IDR' check(currency='IDR'),
  quoted_cost_idr bigint not null check(quoted_cost_idr>=0),
  cod_supported boolean not null default false,
  expires_at timestamptz not null,
  provider_payload_sha256 text not null check(provider_payload_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null default 'quoted' check(status in ('quoted','selected','expired','rejected')),
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,provider_config_id,provider_quote_id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,provider_config_id) references public.delivery_provider_configs(tenant_id,id) on delete restrict
);
create index if not exists delivery_quotes_order_idx
  on public.delivery_provider_quotes(tenant_id,order_id,expires_at desc,status);

-- Extend the baseline dispatch model without changing its established order/status
-- lifecycle. The existing provider/provider_service and cod_amount_idr columns
-- remain the compatibility source for current ERP actions.
alter table public.delivery_dispatches
  add column if not exists quote_id uuid null,
  add column if not exists provider_booking_reference text null,
  add column if not exists cod_collected_idr bigint null check(cod_collected_idr is null or cod_collected_idr>=0),
  add column if not exists cod_remitted_idr bigint null check(cod_remitted_idr is null or cod_remitted_idr>=0),
  add column if not exists courier_cost_expected_idr bigint null check(courier_cost_expected_idr is null or courier_cost_expected_idr>=0),
  add column if not exists courier_cost_final_idr bigint null check(courier_cost_final_idr is null or courier_cost_final_idr>=0);

do $$
begin
  if not exists(select 1 from pg_constraint where conname='delivery_dispatch_quote_fk') then
    alter table public.delivery_dispatches add constraint delivery_dispatch_quote_fk
      foreign key(tenant_id,quote_id) references public.delivery_provider_quotes(tenant_id,id) on delete restrict;
  end if;
end $$;
create unique index if not exists delivery_dispatch_provider_booking_reference_uq
  on public.delivery_dispatches(tenant_id,provider,provider_booking_reference)
  where provider_booking_reference is not null;

-- Keep the baseline provider-event identity/dedupe columns; add evidence that
-- the raw provider signature was verified before an event was applied.
alter table public.delivery_provider_events
  add column if not exists signature_verified_at timestamptz null,
  add column if not exists signature_key_version text null;

create table if not exists public.delivery_storage_evidence (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  dispatch_id uuid not null,
  evidence_type text not null check(evidence_type in ('pickup_photo','delivery_photo','recipient_signature','exception_photo')),
  bucket_id text not null check(bucket_id='delivery-proof'),
  object_path text not null,
  content_type text not null check(content_type in ('image/jpeg','image/png','image/webp')),
  size_bytes bigint not null check(size_bytes>0 and size_bytes<=5242880),
  sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  uploaded_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(bucket_id,object_path),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,dispatch_id) references public.delivery_dispatches(tenant_id,id) on delete restrict,
  check(object_path like tenant_id::text||'/'||branch_id::text||'/'||dispatch_id::text||'/%')
);

create table if not exists public.delivery_cost_reconciliations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  dispatch_id uuid not null,
  customer_fee_idr bigint not null check(customer_fee_idr>=0),
  merchant_subsidy_idr bigint not null check(merchant_subsidy_idr>=0),
  cod_expected_idr bigint not null check(cod_expected_idr>=0),
  cod_collected_idr bigint not null check(cod_collected_idr>=0),
  cod_remitted_idr bigint not null check(cod_remitted_idr>=0),
  courier_cost_expected_idr bigint not null check(courier_cost_expected_idr>=0),
  courier_cost_final_idr bigint not null check(courier_cost_final_idr>=0),
  provider_settlement_idr bigint not null check(provider_settlement_idr>=0),
  provider_fee_idr bigint not null check(provider_fee_idr>=0),
  finance_source_reconciliation_id uuid not null,
  status text not null check(status in ('reconciled','exception')),
  evidence_sha256 text not null check(evidence_sha256 ~ '^[0-9a-f]{64}$'),
  reconciled_by uuid null references auth.users(id) on delete restrict,
  reconciled_at timestamptz null,
  unique(tenant_id,id),
  unique(tenant_id,dispatch_id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,dispatch_id) references public.delivery_dispatches(tenant_id,id) on delete restrict,
  check(cod_remitted_idr<=cod_collected_idr),
  check(status<>'reconciled' or (
    cod_collected_idr=cod_remitted_idr and
    courier_cost_final_idr=customer_fee_idr+merchant_subsidy_idr and
    provider_settlement_idr=courier_cost_final_idr-provider_fee_idr and
    reconciled_by is not null and reconciled_at is not null
  ))
);

create table if not exists public.delivery_outbox (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  dispatch_id uuid not null,
  event_type text not null check(event_type in ('book','cancel','compensate','refresh_status')),
  status text not null default 'queued' check(status in ('queued','claimed','completed','retry','dead_letter')),
  attempts integer not null default 0 check(attempts>=0),
  next_attempt_at timestamptz not null default now(),
  idempotency_key text not null check(length(btrim(idempotency_key)) between 8 and 160),
  last_error_code text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,idempotency_key),
  foreign key(tenant_id,dispatch_id) references public.delivery_dispatches(tenant_id,id) on delete restrict
);
create index if not exists delivery_outbox_due_idx
  on public.delivery_outbox(status,next_attempt_at) where status in ('queued','retry');

do $$
declare t text;
begin
  foreach t in array array[
    'delivery_provider_configs','delivery_provider_quotes',
    'delivery_storage_evidence','delivery_cost_reconciliations','delivery_outbox'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;

-- The existing delivery-proof bucket must be PRIVATE. No client upload policy
-- is granted; the Edge Function verifies actor/branch, file signature, size,
-- hashes the bytes and records immutable metadata after server-side upload.


create or replace function public.delivery_approve_provider_config(
  p_config_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_provider_configs%rowtype;
begin
  select * into v from public.delivery_provider_configs where id=p_config_id for update;
  if not found then raise exception using errcode='P0002',message='DELIVERY_PROVIDER_CONFIG_NOT_FOUND'; end if;
  if v.status<>'pending' then raise exception using errcode='23514',message='DELIVERY_PROVIDER_CONFIG_NOT_PENDING'; end if;
  if v.created_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_DELIVERY_PROVIDER_APPROVER_REQUIRED'; end if;
  if length(btrim(coalesce(v.credential_secret_reference,'')))<3 then
    raise exception using errcode='22023',message='DELIVERY_PROVIDER_SECRET_REFERENCE_REQUIRED';
  end if;
  update public.delivery_provider_configs set status='active',approved_by=p_actor_user_id,
    approved_at=now(),updated_at=now() where id=p_config_id returning * into v;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'delivery.provider_config.approved','delivery_provider_config',v.id::text,
    jsonb_build_object('tenant_id',v.tenant_id,'branch_id',v.branch_id,'provider_key',v.provider_key,
      'integration_mode',v.integration_mode,'credential_secret_reference',v.credential_secret_reference));
  return jsonb_build_object('provider_config_id',v.id,'status',v.status,'provider_key',v.provider_key);
end $$;
revoke all on function public.delivery_approve_provider_config(uuid,uuid) from public,anon,authenticated;
grant execute on function public.delivery_approve_provider_config(uuid,uuid) to service_role;

alter table public.delivery_dispatches
 add column if not exists provider_booking_status text not null default 'confirmed'
 check(provider_booking_status in ('pending','confirmed','failed'));
alter table public.delivery_provider_quotes add column if not exists idempotency_key text null;
create unique index if not exists delivery_provider_quotes_idempotency_uq
 on public.delivery_provider_quotes(tenant_id,idempotency_key) where idempotency_key is not null;
alter table public.delivery_outbox add column if not exists claimed_by text null;
alter table public.delivery_outbox add column if not exists claimed_at timestamptz null;

alter table public.delivery_cost_reconciliations alter column finance_source_reconciliation_id drop not null;
alter table public.delivery_cost_reconciliations drop constraint if exists delivery_cost_reconciled_requires_finance_fk;
alter table public.delivery_cost_reconciliations add constraint delivery_cost_reconciled_requires_finance_fk
 check(status<>'reconciled' or finance_source_reconciliation_id is not null);
do $$ begin
 if not exists(select 1 from pg_constraint where conname='delivery_cost_finance_journal_fk'
   and conrelid='public.delivery_cost_reconciliations'::regclass) then
  alter table public.delivery_cost_reconciliations add constraint delivery_cost_finance_journal_fk
   foreign key(finance_source_reconciliation_id) references public.finance_journal_entries(id) on delete restrict;
 end if;
end $$;

create or replace function public.delivery_reject_evidence_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$ begin raise exception using errcode='55000',message='DELIVERY_EVIDENCE_APPEND_ONLY'; end $$;
revoke all on function public.delivery_reject_evidence_mutation() from public,anon,authenticated;
drop trigger if exists delivery_provider_events_append_only on public.delivery_provider_events;
create trigger delivery_provider_events_append_only before update or delete on public.delivery_provider_events
 for each row execute function public.delivery_reject_evidence_mutation();
drop trigger if exists delivery_cost_reconciliations_append_only on public.delivery_cost_reconciliations;
create trigger delivery_cost_reconciliations_append_only before update or delete on public.delivery_cost_reconciliations
 for each row execute function public.delivery_reject_evidence_mutation();
drop trigger if exists delivery_storage_evidence_append_only on public.delivery_storage_evidence;
create trigger delivery_storage_evidence_append_only before update or delete on public.delivery_storage_evidence
 for each row execute function public.delivery_reject_evidence_mutation();

create or replace function public.delivery_request_provider_config(
 p_tenant_id uuid,p_branch_id uuid,p_provider_key text,p_display_name text,
 p_secret_reference text,p_integration_mode text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_provider_configs%rowtype;
begin
 if length(btrim(coalesce(p_provider_key,''))) not between 2 and 60
  or length(btrim(coalesce(p_display_name,''))) not between 2 and 100
  or p_secret_reference !~ '^[A-Z][A-Z0-9_]{2,119}$'
  or p_integration_mode not in ('manual','api') then
  raise exception using errcode='22023',message='INVALID_DELIVERY_PROVIDER_CONFIG';
 end if;
 if not exists(select 1 from public.branches where tenant_id=p_tenant_id and id=p_branch_id) then
  raise exception using errcode='23503',message='DELIVERY_PROVIDER_BRANCH_NOT_IN_TENANT';
 end if;
 insert into public.delivery_provider_configs(tenant_id,branch_id,provider_key,display_name,
  credential_secret_reference,integration_mode,status,created_by)
 values(p_tenant_id,p_branch_id,lower(btrim(p_provider_key)),btrim(p_display_name),
  p_secret_reference,p_integration_mode,'pending',p_actor_user_id) returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.provider_config.requested','delivery_provider_config',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'provider_key',v.provider_key,
   'integration_mode',v.integration_mode,'secret_reference',v.credential_secret_reference));
 return jsonb_build_object('provider_config_id',v.id,'status',v.status,'provider_key',v.provider_key);
end; $$;
revoke all on function public.delivery_request_provider_config(uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_request_provider_config(uuid,uuid,text,text,text,text,uuid) to service_role;

create or replace function public.delivery_create_provider_quote(
 p_tenant_id uuid,p_branch_id uuid,p_order_id uuid,p_provider_config_id uuid,
 p_provider_quote_id text,p_service_level text,p_quoted_cost_idr bigint,p_cod_supported boolean,
 p_expires_at timestamptz,p_payload_sha256 text,p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_provider_quotes%rowtype; v_order public.orders%rowtype; v_config public.delivery_provider_configs%rowtype;
begin
 if length(btrim(coalesce(p_provider_quote_id,''))) not between 1 and 160
  or length(btrim(coalesce(p_service_level,''))) not between 1 and 80 or p_quoted_cost_idr<0
  or p_expires_at<=now() or p_expires_at>now()+interval '2 hours'
  or p_payload_sha256 !~ '^[0-9a-f]{64}
  raise exception using errcode='22023',message='INVALID_DELIVERY_PROVIDER_QUOTE';
 end if;
 select * into v from public.delivery_provider_quotes where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then
  if v.branch_id<>p_branch_id or v.order_id<>p_order_id or v.provider_config_id<>p_provider_config_id
   or v.provider_quote_id<>p_provider_quote_id or v.quoted_cost_idr<>p_quoted_cost_idr
   or v.service_level<>p_service_level or v.cod_supported<>p_cod_supported or v.expires_at<>p_expires_at
   or v.provider_payload_sha256<>p_payload_sha256 then
   raise exception using errcode='23505',message='DELIVERY_QUOTE_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','quote_id',v.id);
 end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found or v_order.branch_id<>p_branch_id or v_order.payment_status not in ('paid','verified','settled')
  or v_order.fulfillment_status<>'ready' then raise exception using errcode='23514',message='DELIVERY_ORDER_NOT_QUOTE_ELIGIBLE'; end if;
 select * into v_config from public.delivery_provider_configs where tenant_id=p_tenant_id and id=p_provider_config_id
  and status='active' and (branch_id is null or branch_id=p_branch_id) for share;
 if not found then raise exception using errcode='42501',message='APPROVED_DELIVERY_PROVIDER_REQUIRED'; end if;
 insert into public.delivery_provider_quotes(tenant_id,branch_id,order_id,provider_config_id,provider_quote_id,
  service_level,quoted_cost_idr,cod_supported,expires_at,provider_payload_sha256,idempotency_key)
 values(p_tenant_id,p_branch_id,p_order_id,p_provider_config_id,p_provider_quote_id,p_service_level,
  p_quoted_cost_idr,p_cod_supported,p_expires_at,p_payload_sha256,p_idempotency_key) returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.quote.created','delivery_provider_quote',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'order_id',p_order_id,
   'provider_config_id',p_provider_config_id,'quoted_cost_idr',p_quoted_cost_idr));
 return jsonb_build_object('status','quoted','quote_id',v.id,'expires_at',v.expires_at,'quoted_cost_idr',v.quoted_cost_idr);
end; $$;
revoke all on function public.delivery_create_provider_quote(uuid,uuid,uuid,uuid,text,text,bigint,boolean,timestamptz,text,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_create_provider_quote(uuid,uuid,uuid,uuid,text,text,bigint,boolean,timestamptz,text,text,uuid) to service_role;

create or replace function public.delivery_book_dispatch_from_quote(
 p_tenant_id uuid,p_branch_id uuid,p_quote_id uuid,p_cod_amount_idr bigint,
 p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_quote public.delivery_provider_quotes%rowtype; v_config public.delivery_provider_configs%rowtype;
 v_order public.orders%rowtype; v_dispatch public.delivery_dispatches%rowtype; v_outbox public.delivery_outbox%rowtype;
begin
 if p_cod_amount_idr<0 or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_DELIVERY_DISPATCH_COMMAND';
 end if;
 select * into v_dispatch from public.delivery_dispatches where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then
  if v_dispatch.quote_id<>p_quote_id or v_dispatch.cod_amount_idr<>p_cod_amount_idr then
   raise exception using errcode='23505',message='DELIVERY_DISPATCH_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','dispatch_id',v_dispatch.id,'provider_booking_status',v_dispatch.provider_booking_status);
 end if;
 select * into v_quote from public.delivery_provider_quotes where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_quote_id for update;
 if not found or v_quote.status<>'quoted' or v_quote.expires_at<=now() then raise exception using errcode='23514',message='DELIVERY_QUOTE_NOT_SELECTABLE'; end if;
 select * into v_config from public.delivery_provider_configs where tenant_id=p_tenant_id and id=v_quote.provider_config_id
  and status='active' for share;
 if not found then raise exception using errcode='42501',message='APPROVED_DELIVERY_PROVIDER_REQUIRED'; end if;
 select * into v_order from public.orders where id=v_quote.order_id for update;
 if not found or v_order.branch_id<>p_branch_id or v_order.payment_status not in ('paid','verified','settled')
  or v_order.fulfillment_status<>'ready' then raise exception using errcode='23514',message='DELIVERY_ORDER_NOT_BOOKABLE'; end if;
 if exists(select 1 from public.delivery_dispatches where tenant_id=p_tenant_id and order_id=v_order.id and status not in ('failed','cancelled')) then
  raise exception using errcode='23505',message='ACTIVE_DISPATCH_ALREADY_EXISTS';
 end if;
 insert into public.delivery_dispatches(tenant_id,branch_id,order_id,provider,provider_service,delivery_fee_idr,
  cod_amount_idr,status,idempotency_key,booked_at,created_by,quote_id,provider_booking_status,courier_cost_expected_idr)
 values(p_tenant_id,p_branch_id,v_order.id,v_config.provider_key,v_quote.service_level,v_quote.quoted_cost_idr,
  p_cod_amount_idr,'booked',p_idempotency_key,now(),p_actor_user_id,v_quote.id,'pending',v_quote.quoted_cost_idr)
 returning * into v_dispatch;
 update public.delivery_provider_quotes set status='selected' where tenant_id=p_tenant_id and id=v_quote.id;
 update public.orders set fulfillment_status='dispatched',updated_at=now() where id=v_order.id and fulfillment_status='ready';
 if not found then raise exception using errcode='40001',message='ORDER_FULFILLMENT_RACE'; end if;
 insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
 values(v_order.id,'operational','ready','dispatched','Delivery quote selected; provider booking queued');
 insert into public.delivery_outbox(tenant_id,dispatch_id,event_type,status,idempotency_key)
 values(p_tenant_id,v_dispatch.id,'book','queued','delivery-book:'||v_dispatch.id::text) returning * into v_outbox;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.dispatch.booking_queued','delivery_dispatch',v_dispatch.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'order_id',v_order.id,'quote_id',v_quote.id,'outbox_id',v_outbox.id));
 return jsonb_build_object('status','queued','dispatch_id',v_dispatch.id,'outbox_id',v_outbox.id,'provider_booking_status','pending');
end; $$;
revoke all on function public.delivery_book_dispatch_from_quote(uuid,uuid,uuid,bigint,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_book_dispatch_from_quote(uuid,uuid,uuid,bigint,text,uuid) to service_role;

create or replace function public.delivery_confirm_provider_booking(
 p_tenant_id uuid,p_dispatch_id uuid,p_provider_booking_reference text,p_tracking_number text,
 p_tracking_url text,p_succeeded boolean,p_error_code text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_dispatches%rowtype;
begin
 select * into v from public.delivery_dispatches where tenant_id=p_tenant_id and id=p_dispatch_id for update;
 if not found then raise exception using errcode='P0002',message='DELIVERY_DISPATCH_NOT_FOUND'; end if;
 if v.provider_booking_status='confirmed' and p_succeeded and v.provider_booking_reference=p_provider_booking_reference then
  return jsonb_build_object('status','duplicate','dispatch_id',v.id);
 end if;
 if v.provider_booking_status='failed' and not p_succeeded and v.failure_reason=left(coalesce(p_error_code,'PROVIDER_BOOKING_FAILED'),500) then
  return jsonb_build_object('status','duplicate','dispatch_id',v.id);
 end if;
 if v.provider_booking_status<>'pending' then raise exception using errcode='23514',message='DELIVERY_BOOKING_RESULT_ALREADY_FINAL'; end if;
 if p_succeeded then
  if length(btrim(coalesce(p_provider_booking_reference,'')))<2 then raise exception using errcode='22023',message='PROVIDER_BOOKING_REFERENCE_REQUIRED'; end if;
  update public.delivery_dispatches set provider_booking_status='confirmed',provider_booking_reference=p_provider_booking_reference,
   tracking_number=p_tracking_number,tracking_url=p_tracking_url,updated_by=p_actor_user_id,updated_at=now()
   where tenant_id=p_tenant_id and id=p_dispatch_id returning * into v;
 else
  update public.delivery_dispatches set provider_booking_status='failed',status='failed',failed_at=now(),
   failure_reason=left(coalesce(p_error_code,'PROVIDER_BOOKING_FAILED'),500),updated_by=p_actor_user_id,updated_at=now()
   where tenant_id=p_tenant_id and id=p_dispatch_id returning * into v;
  update public.orders set fulfillment_status='failed',updated_at=now() where id=v.order_id and fulfillment_status='dispatched';
  if found then
   insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
   values(v.order_id,'operational','dispatched','failed','Provider booking failed: '||left(coalesce(p_error_code,''),300));
  end if;
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,case when p_succeeded then 'delivery.provider_booking.confirmed' else 'delivery.provider_booking.failed' end,
  'delivery_dispatch',v.id::text,jsonb_build_object('tenant_id',p_tenant_id,'provider_booking_reference',v.provider_booking_reference,'error_code',p_error_code));
 return jsonb_build_object('dispatch_id',v.id,'provider_booking_status',v.provider_booking_status,'status',v.status);
end; $$;
revoke all on function public.delivery_confirm_provider_booking(uuid,uuid,text,text,text,boolean,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_confirm_provider_booking(uuid,uuid,text,text,text,boolean,text,uuid) to service_role;

create or replace function public.delivery_ingest_verified_provider_event(
 p_tenant_id uuid,p_branch_id uuid,p_dispatch_id uuid,p_provider_event_id text,p_next_status text,
 p_occurred_at timestamptz,p_payload_sha256 text,p_signature_key_version text,p_signature_verified boolean,
 p_actor_user_id uuid,p_note text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_dispatches%rowtype; v_event public.delivery_provider_events%rowtype;
begin
 if not p_signature_verified or length(btrim(coalesce(p_provider_event_id,''))) not between 8 and 160
  or p_next_status not in ('picked_up','in_transit','delivered','failed','cancelled')
  or p_payload_sha256 !~ '^[0-9a-f]{64}$'
  raise exception using errcode='22023',message='INVALID_OR_UNVERIFIED_DELIVERY_WEBHOOK';
 end if;
 select * into v from public.delivery_dispatches where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_dispatch_id for update;
 if not found or v.provider_booking_status<>'confirmed' then raise exception using errcode='23514',message='CONFIRMED_DISPATCH_REQUIRED'; end if;
 if not exists(select 1 from public.delivery_provider_configs c where c.tenant_id=p_tenant_id and c.provider_key=v.provider
  and c.status='active' and (c.branch_id is null or c.branch_id=p_branch_id)) then
  raise exception using errcode='42501',message='ACTIVE_PROVIDER_CONFIG_REQUIRED';
 end if;
 select * into v_event from public.delivery_provider_events where tenant_id=p_tenant_id and provider=v.provider and provider_event_id=p_provider_event_id;
 if found then
  if v_event.payload_hash<>p_payload_sha256 or v_event.dispatch_id<>p_dispatch_id then
   raise exception using errcode='23505',message='DELIVERY_PROVIDER_EVENT_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','dispatch_id',v.id,'event_id',v_event.id);
 end if;
 if not ((v.status='booked' and p_next_status in ('picked_up','failed','cancelled')) or
  (v.status='picked_up' and p_next_status in ('in_transit','failed')) or
  (v.status='in_transit' and p_next_status in ('delivered','failed'))) then
  raise exception using errcode='23514',message='INVALID_DELIVERY_TRANSITION';
 end if;
 if p_next_status='delivered' and not exists(select 1 from public.delivery_proof_of_delivery where tenant_id=p_tenant_id and dispatch_id=v.id) then
  raise exception using errcode='23514',message='DELIVERY_PROOF_REQUIRED';
 end if;
 insert into public.delivery_provider_events(tenant_id,dispatch_id,provider,provider_event_id,event_type,provider_status,
  occurred_at,payload_hash,processed_at,processing_status,processing_note,signature_verified_at,signature_key_version)
 values(p_tenant_id,v.id,v.provider,p_provider_event_id,'provider_webhook',p_next_status,p_occurred_at,p_payload_sha256,
  now(),'processed',left(coalesce(p_note,''),500),now(),p_signature_key_version) returning * into v_event;
 update public.delivery_dispatches set status=p_next_status,
  delivered_at=case when p_next_status='delivered' then now() else delivered_at end,
  failed_at=case when p_next_status='failed' then now() else failed_at end,
  failure_reason=case when p_next_status='failed' then left(coalesce(p_note,''),500) else failure_reason end,
  updated_by=p_actor_user_id,updated_at=now() where tenant_id=p_tenant_id and id=v.id returning * into v;
 if p_next_status='delivered' then
  update public.orders set fulfillment_status='fulfilled',fulfilled_at=now(),updated_at=now()
   where id=v.order_id and fulfillment_status='dispatched';
  if not found then raise exception using errcode='40001',message='ORDER_FULFILLMENT_STATE_MISMATCH'; end if;
  insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
   values(v.order_id,'operational','dispatched','fulfilled','Provider webhook confirmed delivery with proof');
 elsif p_next_status='failed' then
  update public.orders set fulfillment_status='failed',updated_at=now() where id=v.order_id and fulfillment_status='dispatched';
  if found then insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
   values(v.order_id,'operational','dispatched','failed','Provider webhook: '||left(coalesce(p_note,''),300)); end if;
 elsif p_next_status='cancelled' then
  update public.orders set fulfillment_status='ready',updated_at=now() where id=v.order_id and fulfillment_status='dispatched';
  if found then insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
   values(v.order_id,'operational','dispatched','ready','Provider dispatch cancelled'); end if;
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.provider_webhook.'||p_next_status,'delivery_dispatch',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'event_id',p_provider_event_id,'payload_sha256',p_payload_sha256));
 return jsonb_build_object('status','processed','dispatch_id',v.id,'event_id',v_event.id,'dispatch_status',v.status);
end; $$;
revoke all on function public.delivery_ingest_verified_provider_event(uuid,uuid,uuid,text,text,timestamptz,text,text,boolean,uuid,text) from public,anon,authenticated;
grant execute on function public.delivery_ingest_verified_provider_event(uuid,uuid,uuid,text,text,timestamptz,text,text,boolean,uuid,text) to service_role;

create or replace function public.delivery_claim_outbox_batch(p_worker_id text,p_limit integer)
returns setof public.delivery_outbox language plpgsql security invoker set search_path=''
as $$
begin
 if length(btrim(coalesce(p_worker_id,''))) not between 3 and 120 or p_limit not between 1 and 50 then
  raise exception using errcode='22023',message='INVALID_DELIVERY_WORKER_CLAIM';
 end if;
 return query
 with candidates as (
  select id from public.delivery_outbox where status in ('queued','retry') and next_attempt_at<=now()
   order by next_attempt_at,created_at for update skip locked limit p_limit
 )
 update public.delivery_outbox o set status='claimed',attempts=attempts+1,claimed_by=p_worker_id,
  claimed_at=now(),updated_at=now()
 from candidates c where o.id=c.id returning o.*;
end; $$;
revoke all on function public.delivery_claim_outbox_batch(text,integer) from public,anon,authenticated;
grant execute on function public.delivery_claim_outbox_batch(text,integer) to service_role;

create or replace function public.delivery_finish_outbox(
 p_outbox_id uuid,p_worker_id text,p_succeeded boolean,p_error_code text,p_retry_after_seconds integer
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_outbox%rowtype;
begin
 select * into v from public.delivery_outbox where id=p_outbox_id for update;
 if not found then raise exception using errcode='P0002',message='DELIVERY_OUTBOX_NOT_FOUND'; end if;
 if v.status='completed' and p_succeeded then return jsonb_build_object('outbox_id',v.id,'status','duplicate','attempts',v.attempts); end if;
 if v.status<>'claimed' or v.claimed_by<>p_worker_id then raise exception using errcode='42501',message='DELIVERY_OUTBOX_CLAIM_MISMATCH'; end if;
 if p_succeeded then
  update public.delivery_outbox set status='completed',claimed_by=null,claimed_at=null,last_error_code=null,updated_at=now()
   where id=p_outbox_id returning * into v;
 else
  update public.delivery_outbox set status=case when attempts>=5 then 'dead_letter' else 'retry' end,
   next_attempt_at=now()+make_interval(secs=>greatest(30,least(coalesce(p_retry_after_seconds,60),3600))),
   last_error_code=left(coalesce(p_error_code,'PROVIDER_REQUEST_FAILED'),120),
   claimed_by=null,claimed_at=null,updated_at=now()
   where id=p_outbox_id returning * into v;
 end if;
 return jsonb_build_object('outbox_id',v.id,'status',v.status,'attempts',v.attempts,'next_attempt_at',v.next_attempt_at);
end; $$;
revoke all on function public.delivery_finish_outbox(uuid,text,boolean,text,integer) from public,anon,authenticated;
grant execute on function public.delivery_finish_outbox(uuid,text,boolean,text,integer) to service_role;

create or replace function public.delivery_reconcile_cost(
 p_tenant_id uuid,p_branch_id uuid,p_dispatch_id uuid,p_customer_fee_idr bigint,p_merchant_subsidy_idr bigint,
 p_cod_expected_idr bigint,p_cod_collected_idr bigint,p_cod_remitted_idr bigint,
 p_courier_cost_expected_idr bigint,p_courier_cost_final_idr bigint,p_provider_settlement_idr bigint,
 p_provider_fee_idr bigint,p_finance_journal_entry_id uuid,p_evidence_sha256 text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_dispatches%rowtype; v_journal public.finance_journal_entries%rowtype;
 v_existing public.delivery_cost_reconciliations%rowtype; v_status text; v_id uuid; v_journal_found boolean;
begin
 if least(p_customer_fee_idr,p_merchant_subsidy_idr,p_cod_expected_idr,p_cod_collected_idr,p_cod_remitted_idr,
  p_courier_cost_expected_idr,p_courier_cost_final_idr,p_provider_settlement_idr,p_provider_fee_idr)<0
  or p_evidence_sha256 !~ '^[0-9a-f]{64}$' then
  raise exception using errcode='22023',message='INVALID_DELIVERY_RECONCILIATION';
 end if;
 select * into v from public.delivery_dispatches where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_dispatch_id for update;
 if not found or v.status<>'delivered' or v.provider_booking_status<>'confirmed' then
  raise exception using errcode='23514',message='DELIVERED_CONFIRMED_DISPATCH_REQUIRED';
 end if;
 if p_cod_expected_idr<>v.cod_amount_idr then raise exception using errcode='23514',message='DELIVERY_COD_EXPECTED_AMOUNT_MISMATCH'; end if;
 select * into v_existing from public.delivery_cost_reconciliations where tenant_id=p_tenant_id and dispatch_id=p_dispatch_id;
 if found then
  if v_existing.evidence_sha256<>p_evidence_sha256 or v_existing.customer_fee_idr<>p_customer_fee_idr
   or v_existing.merchant_subsidy_idr<>p_merchant_subsidy_idr or v_existing.cod_expected_idr<>p_cod_expected_idr
   or v_existing.cod_collected_idr<>p_cod_collected_idr or v_existing.cod_remitted_idr<>p_cod_remitted_idr
   or v_existing.courier_cost_expected_idr<>p_courier_cost_expected_idr or v_existing.courier_cost_final_idr<>p_courier_cost_final_idr
   or v_existing.provider_settlement_idr<>p_provider_settlement_idr or v_existing.provider_fee_idr<>p_provider_fee_idr
   or v_existing.finance_source_reconciliation_id is distinct from p_finance_journal_entry_id then
   raise exception using errcode='23505',message='DELIVERY_RECONCILIATION_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','reconciliation_id',v_existing.id,'reconciliation_status',v_existing.status);
 end if;
 select * into v_journal from public.finance_journal_entries where id=p_finance_journal_entry_id
  and branch_id=p_branch_id and source_type='delivery_dispatch' and source_id=p_dispatch_id and status='posted'
  and amount_idr=p_provider_settlement_idr;
 v_journal_found:=found;
 v_status:=case when v_journal_found and p_cod_expected_idr=p_cod_collected_idr and p_cod_collected_idr=p_cod_remitted_idr
  and p_courier_cost_final_idr=p_customer_fee_idr+p_merchant_subsidy_idr
  and p_provider_settlement_idr=p_courier_cost_final_idr-p_provider_fee_idr
  then 'reconciled' else 'exception' end;
 insert into public.delivery_cost_reconciliations(tenant_id,branch_id,dispatch_id,customer_fee_idr,merchant_subsidy_idr,
  cod_expected_idr,cod_collected_idr,cod_remitted_idr,courier_cost_expected_idr,courier_cost_final_idr,
  provider_settlement_idr,provider_fee_idr,finance_source_reconciliation_id,status,evidence_sha256,reconciled_by,reconciled_at)
 values(p_tenant_id,p_branch_id,p_dispatch_id,p_customer_fee_idr,p_merchant_subsidy_idr,p_cod_expected_idr,
  p_cod_collected_idr,p_cod_remitted_idr,p_courier_cost_expected_idr,p_courier_cost_final_idr,
  p_provider_settlement_idr,p_provider_fee_idr,case when v_journal_found then p_finance_journal_entry_id else null end,v_status,p_evidence_sha256,
  case when v_status='reconciled' then p_actor_user_id else null end,
  case when v_status='reconciled' then now() else null end) returning id into v_id;
 update public.delivery_dispatches set cod_collected_idr=p_cod_collected_idr,cod_remitted_idr=p_cod_remitted_idr,
  courier_cost_expected_idr=p_courier_cost_expected_idr,courier_cost_final_idr=p_courier_cost_final_idr,updated_at=now()
  where tenant_id=p_tenant_id and id=p_dispatch_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.cost.'||v_status,'delivery_cost_reconciliation',v_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'dispatch_id',p_dispatch_id,
   'finance_journal_entry_id',p_finance_journal_entry_id,'evidence_sha256',p_evidence_sha256));
 return jsonb_build_object('reconciliation_id',v_id,'status',v_status,'finance_journal_entry_id',p_finance_journal_entry_id);
end; $$;
revoke all on function public.delivery_reconcile_cost(uuid,uuid,uuid,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_reconcile_cost(uuid,uuid,uuid,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,uuid,text,uuid) to service_role;
create or replace function public.delivery_get_outbox_job_context(p_outbox_id uuid,p_worker_id text)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_outbox%rowtype; d public.delivery_dispatches%rowtype;
 q public.delivery_provider_quotes%rowtype; c public.delivery_provider_configs%rowtype; o public.orders%rowtype;
begin
 select * into v from public.delivery_outbox where id=p_outbox_id and status='claimed' and claimed_by=p_worker_id for update;
 if not found then raise exception using errcode='42501',message='DELIVERY_OUTBOX_CLAIM_MISMATCH'; end if;
 select * into d from public.delivery_dispatches where tenant_id=v.tenant_id and id=v.dispatch_id;
 if not found then raise exception using errcode='P0002',message='DELIVERY_DISPATCH_NOT_FOUND'; end if;
 select * into c from public.delivery_provider_configs where tenant_id=d.tenant_id and provider_key=d.provider
  and status='active' and (branch_id is null or branch_id=d.branch_id) order by branch_id nulls last limit 1;
 if not found then raise exception using errcode='42501',message='ACTIVE_DELIVERY_PROVIDER_CONFIG_NOT_FOUND'; end if;
 select * into q from public.delivery_provider_quotes where tenant_id=d.tenant_id and id=d.quote_id;
 select * into o from public.orders where id=d.order_id;
 return jsonb_build_object('outbox',to_jsonb(v),'dispatch',to_jsonb(d),'quote',case when q.id is null then null else to_jsonb(q) end,
  'provider_config',jsonb_build_object('id',c.id,'provider_key',c.provider_key,'display_name',c.display_name,
   'credential_secret_reference',c.credential_secret_reference,'integration_mode',c.integration_mode),
  'order',jsonb_build_object('id',o.id,'branch_id',o.branch_id,'delivery_address',o.delivery_address,
   'customer_name',o.customer_name,'customer_whatsapp',o.customer_whatsapp,'payment_status',o.payment_status));
end; $$;
revoke all on function public.delivery_get_outbox_job_context(uuid,text) from public,anon,authenticated;
grant execute on function public.delivery_get_outbox_job_context(uuid,text) to service_role;
