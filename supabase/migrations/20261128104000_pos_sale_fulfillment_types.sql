-- T05: persist POS dine-in, takeaway, pickup and delivery fulfillment details atomically with checkout.
begin;

create table if not exists public.pos_sale_fulfillments(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 sale_id uuid not null unique references public.pos_sales(id) on delete restrict,
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 idempotency_key text not null check(length(idempotency_key) between 8 and 120),
 payload_fingerprint text not null,
 order_type text not null check(order_type in ('dine_in','takeaway','pickup','delivery')),
 table_code text,
 pickup_at timestamptz,
 delivery_address text,
 delivery_area_id text,
 order_status text not null default 'received'
  check(order_status in ('received','confirmed','preparing','ready_for_pickup','waiting_for_courier','in_delivery','completed','cancelled','delivery_issue')),
 fulfillment_status text not null default 'queued'
  check(fulfillment_status in ('unassigned','queued','accepted','preparing','ready','dispatched','fulfilled','failed','cancelled')),
 version integer not null default 1 check(version>0),
 response jsonb not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,actor_user_id,idempotency_key),
 check((order_type='dine_in' and nullif(btrim(table_code),'') is not null and pickup_at is null and delivery_address is null)
    or (order_type='takeaway' and table_code is null and pickup_at is null and delivery_address is null)
    or (order_type='pickup' and table_code is null and pickup_at is not null and delivery_address is null)
    or (order_type='delivery' and table_code is null and pickup_at is null and nullif(btrim(delivery_address),'') is not null and nullif(btrim(delivery_area_id),'') is not null))
);
create index if not exists pos_sale_fulfillments_branch_queue_idx
 on public.pos_sale_fulfillments(tenant_id,branch_id,fulfillment_status,created_at desc);

create table if not exists public.pos_sale_fulfillment_events(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null,
 branch_id uuid not null,
 sale_id uuid not null references public.pos_sales(id) on delete restrict,
 fulfillment_id uuid not null references public.pos_sale_fulfillments(id) on delete restrict,
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 domain text not null check(domain in ('order','fulfillment')),
 previous_status text,
 next_status text not null,
 version integer not null check(version>0),
 event_type text not null,
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists pos_sale_fulfillment_events_history_idx
 on public.pos_sale_fulfillment_events(tenant_id,sale_id,created_at desc);

alter table public.pos_sale_fulfillments enable row level security;
alter table public.pos_sale_fulfillments force row level security;
drop policy if exists service_role_only on public.pos_sale_fulfillments;
create policy service_role_only on public.pos_sale_fulfillments for all to service_role using(true) with check(true);
revoke all on public.pos_sale_fulfillments from public,anon,authenticated;
grant select,insert,update on public.pos_sale_fulfillments to service_role;

alter table public.pos_sale_fulfillment_events enable row level security;
alter table public.pos_sale_fulfillment_events force row level security;
drop policy if exists service_role_only on public.pos_sale_fulfillment_events;
create policy service_role_only on public.pos_sale_fulfillment_events for all to service_role using(true) with check(true);
revoke all on public.pos_sale_fulfillment_events from public,anon,authenticated;
grant select,insert on public.pos_sale_fulfillment_events to service_role;

create or replace function public.pos_create_order_with_fulfillment_atomic(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_shift_id uuid,p_idempotency_key text,
 p_items jsonb,p_payment_method text,p_discount_idr bigint,p_customer_reference text,p_notes text,
 p_tenders jsonb,p_fulfillment jsonb
) returns jsonb language plpgsql security invoker set search_path=''
as $fn$
declare
 v_branch public.branches%rowtype;
 v_type text;
 v_table_code text;
 v_pickup_at timestamptz;
 v_delivery_address text;
 v_delivery_area_id text;
 v_fingerprint text;
 v_existing public.pos_sale_fulfillments%rowtype;
 v_sale jsonb;
 v_sale_id uuid;
 v_fulfillment_id uuid:=gen_random_uuid();
 v_event_id uuid:=gen_random_uuid();
 v_inner_key text;
 v_payment_status text;
 v_response jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then
  raise exception using errcode='42501',message='POS_SERVICE_ROLE_REQUIRED';
 end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then
  raise exception using errcode='42501',message='POS_BRANCH_SCOPE_DENIED';
 end if;
 if p_idempotency_key is null or length(trim(p_idempotency_key))<8 or length(p_idempotency_key)>120
  or jsonb_typeof(p_fulfillment)<>'object' then
  raise exception using errcode='22023',message='POS_FULFILLMENT_INPUT_INVALID';
 end if;
 select * into v_branch from public.branches where id=p_branch_id and tenant_id=p_tenant_id and status='active' for share;
 if not found then raise exception using errcode='23503',message='POS_BRANCH_NOT_ACTIVE';end if;
 v_type:=p_fulfillment->>'order_type';
 if v_type not in ('dine_in','takeaway','pickup','delivery') then
  raise exception using errcode='22023',message='POS_ORDER_TYPE_INVALID';
 end if;
 v_table_code:=nullif(left(btrim(coalesce(p_fulfillment->>'table_code','')),40),'');
 v_delivery_address:=nullif(left(btrim(coalesce(p_fulfillment->>'delivery_address','')),500),'');
 v_delivery_area_id:=nullif(left(btrim(coalesce(p_fulfillment->>'delivery_area_id','')),80),'');
 if nullif(p_fulfillment->>'pickup_at_local','') is not null then
  v_pickup_at:=(p_fulfillment->>'pickup_at_local')::timestamp without time zone at time zone v_branch.timezone;
 elsif nullif(p_fulfillment->>'pickup_at','') is not null then
  v_pickup_at:=(p_fulfillment->>'pickup_at')::timestamptz;
 end if;
 if v_pickup_at is not null and v_pickup_at<now() then
  raise exception using errcode='22023',message='POS_PICKUP_TIME_IN_PAST';
 end if;
 if (v_type='dine_in' and v_table_code is null) or (v_type<>'dine_in' and v_table_code is not null)
  or (v_type='pickup' and v_pickup_at is null) or (v_type<>'pickup' and v_pickup_at is not null)
  or (v_type='delivery' and (v_delivery_address is null or v_delivery_area_id is null))
  or (v_type<>'delivery' and (v_delivery_address is not null or v_delivery_area_id is not null)) then
  raise exception using errcode='22023',message='POS_ORDER_TYPE_DETAILS_INVALID';
 end if;
 v_fingerprint:=encode(extensions.digest(jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,
  'shift_id',p_shift_id,'items',p_items,'payment_method',p_payment_method,'discount_idr',p_discount_idr,
  'customer_reference',p_customer_reference,'notes',p_notes,'tenders',p_tenders,'fulfillment',p_fulfillment)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_actor_user_id::text||':'||p_idempotency_key,0));
 select * into v_existing from public.pos_sale_fulfillments
 where tenant_id=p_tenant_id and actor_user_id=p_actor_user_id and idempotency_key=p_idempotency_key for update;
 if found then
  if v_existing.payload_fingerprint<>v_fingerprint then
   raise exception using errcode='23505',message='POS_FULFILLMENT_IDEMPOTENCY_PAYLOAD_MISMATCH';
  end if;
  return v_existing.response||jsonb_build_object('idempotent_replay',true);
 end if;
 v_inner_key:='pos-order:'||substr(encode(extensions.digest(p_idempotency_key,'sha256'),'hex'),1,96);
 if jsonb_typeof(p_tenders)='array' and jsonb_array_length(p_tenders)>0 then
  v_sale:=public.erp_create_pos_sale_split_tender_idempotent(p_branch_id,p_shift_id,p_items,p_discount_idr,
   p_customer_reference,p_notes,p_actor_user_id,v_inner_key,p_tenders);
 else
  v_sale:=public.erp_create_pos_sale_idempotent(p_branch_id,p_shift_id,p_items,p_payment_method,p_discount_idr,
   p_customer_reference,p_notes,p_actor_user_id,v_inner_key);
 end if;
 v_sale_id:=(v_sale->>'sale_id')::uuid;
 select payment_status into v_payment_status from public.pos_sales where id=v_sale_id and branch_id=p_branch_id for update;
 if v_payment_status is null then raise exception using errcode='P0002',message='POS_FULFILLMENT_SALE_NOT_FOUND';end if;
 v_response:=jsonb_build_object('order_id',v_sale_id,'sale_id',v_sale_id,'fulfillment_id',v_fulfillment_id,
  'order_type',v_type,'payment_status',v_payment_status,'order_status','received','fulfillment_status','queued',
  'transaction_code',v_sale->>'transaction_code','idempotent_replay',false);
 insert into public.pos_sale_fulfillments(id,tenant_id,branch_id,sale_id,actor_user_id,idempotency_key,payload_fingerprint,
  order_type,table_code,pickup_at,delivery_address,delivery_area_id,order_status,fulfillment_status,version,response)
 values(v_fulfillment_id,p_tenant_id,p_branch_id,v_sale_id,p_actor_user_id,p_idempotency_key,v_fingerprint,
  v_type,v_table_code,v_pickup_at,v_delivery_address,v_delivery_area_id,'received','queued',1,v_response);
 insert into public.pos_sale_fulfillment_events(id,tenant_id,branch_id,sale_id,fulfillment_id,actor_user_id,domain,
  previous_status,next_status,version,event_type,metadata)
 values(v_event_id,p_tenant_id,p_branch_id,v_sale_id,v_fulfillment_id,p_actor_user_id,'order',null,'received',1,'created',
  jsonb_build_object('order_type',v_type,'table_code',v_table_code,'pickup_at',v_pickup_at,'delivery_area_id',v_delivery_area_id));
 insert into public.pos_sale_fulfillment_events(tenant_id,branch_id,sale_id,fulfillment_id,actor_user_id,domain,
  previous_status,next_status,version,event_type,metadata)
 values(p_tenant_id,p_branch_id,v_sale_id,v_fulfillment_id,p_actor_user_id,'fulfillment',null,'queued',1,'created','{}'::jsonb);
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'pos_order_fulfillment_created','pos_sale_fulfillment',v_fulfillment_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'sale_id',v_sale_id,'order_type',v_type));
 return v_response;
end;
$fn$;

revoke all on function public.pos_create_order_with_fulfillment_atomic(uuid,uuid,uuid,uuid,text,jsonb,text,bigint,text,text,jsonb,jsonb)
 from public,anon,authenticated;
grant execute on function public.pos_create_order_with_fulfillment_atomic(uuid,uuid,uuid,uuid,text,jsonb,text,bigint,text,text,jsonb,jsonb)
 to service_role;

commit;
