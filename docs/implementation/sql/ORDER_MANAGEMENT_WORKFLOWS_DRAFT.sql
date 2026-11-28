-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- D03-F01/F03/F04/F05/F06/F09/F10: order routing, availability, timeline, history and notification outbox.
-- Requires disposable replay and independent RLS/ACL review before any migration is generated.
begin;

alter table public.orders add column if not exists business_order_number text;
alter table public.orders add column if not exists version integer not null default 1;
alter table public.orders drop constraint if exists orders_payment_status_check;
alter table public.orders add constraint orders_payment_status_check
 check(payment_status=any(array['unpaid','pending_verification','paid','partially_refunded','rejected','refunded']));
alter table public.order_status_history drop constraint if exists order_status_history_status_type_check;
alter table public.order_status_history add constraint order_status_history_status_type_check
 check(status_type=any(array['payment','operational','fulfillment','reservation']));
create unique index if not exists orders_business_order_number_key
 on public.orders(business_order_number) where business_order_number is not null;

create table if not exists public.branch_operating_hours (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,weekday smallint not null check(weekday between 0 and 6),
 opens_at time not null,closes_at time not null,cutoff_minutes integer not null default 0 check(cutoff_minutes>=0),
 max_orders_per_slot integer not null default 50 check(max_orders_per_slot>0),is_active boolean not null default true,
 unique(tenant_id,branch_id,weekday),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check(closes_at>opens_at)
);
create table if not exists public.branch_operating_exceptions (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,service_date date not null,is_closed boolean not null default false,
 opens_at time,closes_at time,capacity_override integer check(capacity_override is null or capacity_override>=0),
 reason text not null,created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),
 unique(tenant_id,branch_id,service_date),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check((is_closed=true) or (opens_at is not null and closes_at is not null and closes_at>opens_at))
);
create table if not exists public.branch_service_areas (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,area_code text not null,postal_codes text[] not null check(cardinality(postal_codes)>0),
 priority integer not null default 100,is_active boolean not null default true,created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,branch_id,area_code)
);
create index if not exists branch_service_areas_postal_idx on public.branch_service_areas using gin(postal_codes);
create table if not exists public.branch_capacity_slots (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,service_date date not null,slot_time time not null,capacity integer not null check(capacity>=0),
 reserved_count integer not null default 0 check(reserved_count>=0 and reserved_count<=capacity),updated_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,branch_id,service_date,slot_time)
);
create table if not exists public.order_branch_routing_decisions (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 order_id uuid not null references public.orders(id) on delete restrict,branch_id uuid not null,postal_code text not null,
 reservation_id uuid,reason text not null,capacity_reserved integer not null check(capacity_reserved>=0),
 idempotency_key text not null,created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,order_id),unique(tenant_id,idempotency_key)
);

create table if not exists public.order_timeline_events (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,order_id uuid not null references public.orders(id) on delete restrict,
 source text not null,source_event_id text not null,actor_user_id uuid references auth.users(id) on delete set null,
 status_type text not null check(status_type in ('payment','operational','fulfillment','reservation')),
 old_status text,new_status text not null,reason text,version integer not null,created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,source,source_event_id)
);
create index if not exists order_timeline_events_order_idx on public.order_timeline_events(tenant_id,order_id,created_at,id);

create table if not exists public.order_cancellation_requests (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,order_id uuid not null references public.orders(id) on delete restrict,
 actor_user_id uuid references auth.users(id) on delete set null,reason text not null,
 status text not null check(status in ('requested','approved','rejected','completed')),
 refund_status text not null check(refund_status in ('not_required','refund_requested','refunded','failed')),
 idempotency_key text not null,created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,order_id,idempotency_key)
);
create table if not exists public.order_notification_preferences (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 customer_token_hash text not null,channel text not null check(channel in ('whatsapp','email','sms')),
 consent boolean not null,updated_at timestamptz not null default now(),
 unique(tenant_id,customer_token_hash,channel)
);
create table if not exists public.order_notification_outbox (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,order_id uuid not null references public.orders(id) on delete restrict,
 customer_token_hash text not null,channel text not null check(channel in ('whatsapp','email','sms')),
 recipient text not null,message text not null,idempotency_key text not null,
 status text not null default 'queued' check(status in ('queued','processing','sent','suppressed','retry_pending','dead_letter')),
 attempt_count integer not null default 0 check(attempt_count>=0),next_attempt_at timestamptz not null default now(),
 lease_owner text,lease_expires_at timestamptz,provider_message_id text,last_error text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,idempotency_key)
);
create index if not exists order_notification_outbox_claim_idx
 on public.order_notification_outbox(status,next_attempt_at,lease_expires_at,created_at);
create table if not exists public.order_notification_attempts (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 outbox_id uuid not null references public.order_notification_outbox(id) on delete restrict,
 attempt_number integer not null,status text not null,provider_message_id text,error_code text,created_at timestamptz not null default now(),
 unique(outbox_id,attempt_number)
);

do $$ declare t text; begin
 foreach t in array array['branch_operating_hours','branch_operating_exceptions','branch_service_areas','branch_capacity_slots',
  'order_branch_routing_decisions','order_timeline_events','order_cancellation_requests','order_notification_preferences',
  'order_notification_outbox','order_notification_attempts'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('alter table public.%I force row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update on public.%I to service_role',t);
 end loop;
end $$;

create or replace view public.unified_order_queue_source with(security_invoker=true) as
select b.tenant_id,o.branch_id,'online'::text channel,o.id source_id,o.order_number,
 o.payment_status,o.operational_status,o.fulfillment_status,o.created_at,o.requested_date,o.requested_time,
 o.customer_name,o.receiving_method,null::text transaction_code
from public.orders o join public.branches b on b.id=o.branch_id
union all
select b.tenant_id,s.branch_id,'pos'::text channel,s.id source_id,null::bigint order_number,
 s.payment_status,null::text operational_status,null::text fulfillment_status,s.created_at,
 null::date requested_date,null::text requested_time,null::text customer_name,null::text receiving_method,s.transaction_code
from public.pos_sales s join public.branches b on b.id=s.branch_id;
revoke all on public.unified_order_queue_source from public,anon,authenticated;
grant select on public.unified_order_queue_source to service_role;

create or replace function public.list_unified_order_queue(
 p_tenant_id uuid,p_actor_user_id uuid,p_branch_ids uuid[],p_channels text[],p_cursor timestamptz,p_limit integer,p_statuses text[]
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_allowed uuid[];v_requested uuid[];v_rows jsonb;v_next timestamptz;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='ORDER_SERVICE_ROLE_REQUIRED';end if;
 if p_limit<1 or p_limit>200 then raise exception 'invalid_order_queue_limit';end if;
 if not exists(select 1 from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active') then raise exception using errcode='42501',message='ORDER_TENANT_SCOPE_DENIED';end if;
 select coalesce(array_agg(b.id),'{}'::uuid[]) into v_allowed from public.branches b where b.tenant_id=p_tenant_id
  and public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,b.id);
 v_requested:=case when coalesce(cardinality(p_branch_ids),0)=0 then v_allowed else p_branch_ids end;
 if not(v_requested<@v_allowed) then raise exception using errcode='42501',message='ORDER_BRANCH_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb),max(q.created_at)
 into v_rows,v_next from (
  select * from public.unified_order_queue_source q where q.tenant_id=p_tenant_id and q.branch_id=any(v_requested)
   and (p_channels is null or q.channel=any(p_channels))
   and (p_statuses is null or q.payment_status=any(p_statuses) or q.operational_status=any(p_statuses) or q.fulfillment_status=any(p_statuses))
   and (p_cursor is null or q.created_at<p_cursor)
  order by q.created_at desc limit p_limit
 ) q;
 return jsonb_build_object('scope',jsonb_build_object('tenantId',p_tenant_id,'branchIds',v_requested),
  'rows',v_rows,'nextCursor',v_next);
end $$;
revoke all on function public.list_unified_order_queue(uuid,uuid,uuid[],text[],timestamptz,integer,text[]) from public,anon,authenticated;
grant execute on function public.list_unified_order_queue(uuid,uuid,uuid[],text[],timestamptz,integer,text[]) to service_role;

create or replace function public.generate_business_order_number(
 p_tenant_id uuid,p_branch_id uuid,p_order_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_order public.orders%rowtype;v_branch public.branches%rowtype;v_date date;v_seq integer;v_code text;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='ORDER_SERVICE_ROLE_REQUIRED';end if;
 select * into v_order from public.orders where id=p_order_id and branch_id=p_branch_id for update;
 if not found then raise exception 'order_not_found';end if;
 select * into v_branch from public.branches where id=p_branch_id and tenant_id=p_tenant_id;
 if not found then raise exception using errcode='42501',message='ORDER_TENANT_SCOPE_DENIED';end if;
 if v_order.business_order_number is not null then
  return jsonb_build_object('tenantId',p_tenant_id,'branchId',p_branch_id,'orderId',p_order_id,'businessOrderNumber',v_order.business_order_number,'reused',true);
 end if;
 v_date:=((v_order.created_at at time zone v_branch.timezone)::date
  - case when (v_order.created_at at time zone v_branch.timezone)::time < v_branch.business_day_cutoff then 1 else 0 end);
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||v_date::text,0));
 insert into public.order_business_number_sequences(tenant_id,business_date,last_value)
 values(p_tenant_id,v_date,1) on conflict(tenant_id,business_date) do update set last_value=order_business_number_sequences.last_value+1
 returning last_value into v_seq;
 if v_seq>99999 then raise exception 'business_order_number_daily_limit_exceeded';end if;
 v_code:='DLC-'||to_char(v_date,'DD/MM/YYYY')||'-'||lpad(v_seq::text,5,'0');
 update public.orders set business_order_number=v_code,version=version+1,updated_at=now() where id=p_order_id and business_order_number is null;
 if not found then raise exception 'business_order_number_race';end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(auth.uid(),'business_order_number_generated','order',p_order_id::text,jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'business_date',v_date,'business_order_number',v_code));
 return jsonb_build_object('tenantId',p_tenant_id,'branchId',p_branch_id,'orderId',p_order_id,'businessOrderNumber',v_code,'reused',false);
end $$;
revoke all on function public.generate_business_order_number(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.generate_business_order_number(uuid,uuid,uuid,text) to service_role;

create table if not exists public.order_business_number_sequences (
 tenant_id uuid not null references public.tenants(id) on delete restrict,business_date date not null,last_value integer not null check(last_value between 1 and 99999),
 primary key(tenant_id,business_date)
);

create or replace function public.append_order_timeline_event(
 p_tenant_id uuid,p_branch_id uuid,p_order_id uuid,p_source text,p_source_event_id text,p_actor_user_id uuid,
 p_status_type text,p_old_status text,p_new_status text,p_reason text,p_expected_version integer,p_idempotency_key text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_order public.orders%rowtype;v_event public.order_timeline_events%rowtype;v_new_version integer;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='ORDER_SERVICE_ROLE_REQUIRED';end if;
 if p_status_type not in ('payment','operational','fulfillment','reservation') then raise exception 'invalid_timeline_type';end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='ORDER_BRANCH_SCOPE_DENIED';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_source||':'||p_source_event_id,0));
 select * into v_order from public.orders where id=p_order_id and branch_id=p_branch_id for update;
 if not found then raise exception 'order_not_found';end if;
 if v_order.version<>p_expected_version then raise exception using errcode='40001',message='ORDER_TIMELINE_STALE_VERSION';end if;
 insert into public.order_timeline_events(tenant_id,branch_id,order_id,source,source_event_id,actor_user_id,status_type,old_status,new_status,reason,version)
 values(p_tenant_id,p_branch_id,p_order_id,p_source,p_source_event_id,p_actor_user_id,p_status_type,p_old_status,p_new_status,left(p_reason,500),p_expected_version+1)
 on conflict(tenant_id,source,source_event_id) do nothing returning * into v_event;
 if not found then
  select * into v_event from public.order_timeline_events where tenant_id=p_tenant_id and source=p_source and source_event_id=p_source_event_id;
  return jsonb_build_object('eventId',v_event.id,'tenantId',p_tenant_id,'orderId',p_order_id,'sourceEventId',p_source_event_id,'version',v_event.version,'duplicate',true);
 end if;
 if p_status_type='payment' then update public.orders set payment_status=p_new_status,version=version+1,updated_at=now() where id=p_order_id;
 elsif p_status_type='operational' then update public.orders set operational_status=p_new_status,version=version+1,updated_at=now() where id=p_order_id;
 elsif p_status_type='fulfillment' then update public.orders set fulfillment_status=p_new_status,version=version+1,updated_at=now() where id=p_order_id;
 else update public.orders set version=version+1,updated_at=now() where id=p_order_id;
 end if;
 insert into public.order_status_history(order_id,status_type,old_status,new_status,changed_by,note)
 values(p_order_id,p_status_type,p_old_status,p_new_status,p_actor_user_id,left(p_reason,500));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'order_timeline_event_appended','order',p_order_id::text,jsonb_build_object('tenant_id',p_tenant_id,'source',p_source,'source_event_id',p_source_event_id,'status_type',p_status_type,'new_status',p_new_status));
 return jsonb_build_object('eventId',v_event.id,'tenantId',p_tenant_id,'orderId',p_order_id,'sourceEventId',p_source_event_id,'version',p_expected_version+1,'duplicate',false);
end $$;
revoke all on function public.append_order_timeline_event(uuid,uuid,uuid,text,text,uuid,text,text,text,text,integer,text) from public,anon,authenticated;
grant execute on function public.append_order_timeline_event(uuid,uuid,uuid,text,text,uuid,text,text,text,text,integer,text) to service_role;

create or replace function public.list_order_timeline(p_tenant_id uuid,p_branch_id uuid,p_order_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_rows jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='ORDER_SERVICE_ROLE_REQUIRED';end if;
 if not exists(select 1 from public.orders o join public.branches b on b.id=o.branch_id where o.id=p_order_id and o.branch_id=p_branch_id and b.tenant_id=p_tenant_id) then raise exception using errcode='42501',message='ORDER_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at,e.id),'[]'::jsonb) into v_rows from public.order_timeline_events e
 where e.tenant_id=p_tenant_id and e.branch_id=p_branch_id and e.order_id=p_order_id;
 return v_rows;
end $$;
revoke all on function public.list_order_timeline(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.list_order_timeline(uuid,uuid,uuid) to service_role;

create or replace function public.get_customer_order_history_by_token(p_tracking_token text)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_hash text;v_rows jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='ORDER_SERVICE_ROLE_REQUIRED';end if;
 if length(coalesce(p_tracking_token,''))<24 then raise exception using errcode='42501',message='ORDER_TRACKING_TOKEN_INVALID';end if;
 v_hash:=encode(extensions.digest(p_tracking_token,'sha256'),'hex');
 select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'order_number',o.order_number,'business_order_number',o.business_order_number,
  'payment_status',o.payment_status,'operational_status',o.operational_status,'fulfillment_status',o.fulfillment_status,
  'requested_date',o.requested_date,'requested_time',o.requested_time,'created_at',o.created_at,
  'timeline',(select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at),'[]'::jsonb) from public.order_status_history h where h.order_id=o.id),
  'customerScopeVerified',true) order by o.created_at desc),'[]'::jsonb) into v_rows
 from public.orders o where o.tracking_token_hash=v_hash;
 return jsonb_build_object('orders',v_rows);
end $$;
revoke all on function public.get_customer_order_history_by_token(text) from public,anon,authenticated;
grant execute on function public.get_customer_order_history_by_token(text) to service_role;

create or replace function public.cancel_order_with_compensations(
 p_tenant_id uuid,p_order_id uuid,p_actor_user_id uuid,p_tracking_token text,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_order public.orders%rowtype;v_branch public.branches%rowtype;v_token_ok boolean:=false;v_refund_status text:='not_required';v_request_id uuid;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='ORDER_SERVICE_ROLE_REQUIRED';end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found then raise exception 'order_not_found';end if;
 select * into v_branch from public.branches where id=v_order.branch_id and tenant_id=p_tenant_id;
 if not found then raise exception using errcode='42501',message='ORDER_TENANT_SCOPE_DENIED';end if;
 if p_tracking_token is not null then
  v_token_ok:=v_order.tracking_token_hash=encode(extensions.digest(p_tracking_token,'sha256'),'hex');
 end if;
 if not v_token_ok and (p_actor_user_id is null or not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,v_order.branch_id))
  then raise exception using errcode='42501',message='ORDER_CANCEL_SCOPE_DENIED';end if;
 if v_order.operational_status in ('completed','cancelled') or v_order.fulfillment_status in ('fulfilled','dispatched')
  then raise exception 'ORDER_CANCELLATION_NOT_ALLOWED';end if;
 if v_order.payment_status='paid' then
  insert into public.order_cancellation_requests(tenant_id,branch_id,order_id,actor_user_id,reason,status,refund_status,idempotency_key)
  values(p_tenant_id,v_order.branch_id,p_order_id,p_actor_user_id,left(p_reason,500),'requested','refund_requested',p_idempotency_key)
  on conflict(tenant_id,order_id,idempotency_key) do nothing returning id into v_request_id;
  v_refund_status:='refund_requested';
 end if;
 update public.order_reservations set status='released',released_at=now(),updated_at=now()
 where order_id=p_order_id and status in ('active','held_for_verification');
 update public.orders set operational_status='cancelled',version=version+1,updated_at=now() where id=p_order_id;
 insert into public.order_status_history(order_id,status_type,old_status,new_status,changed_by,note)
 values(p_order_id,'operational',v_order.operational_status,'cancelled',p_actor_user_id,left(p_reason,500));
 insert into public.order_notification_outbox(tenant_id,branch_id,order_id,customer_token_hash,channel,recipient,message,idempotency_key)
 values(p_tenant_id,v_order.branch_id,p_order_id,v_order.tracking_token_hash,'whatsapp',v_order.customer_whatsapp,
  'Pesanan dibatalkan. Status pengembalian dana: '||v_refund_status,'order-cancel:'||p_order_id::text)
 on conflict(tenant_id,idempotency_key) do nothing;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'order_cancelled','order',p_order_id::text,jsonb_build_object('tenant_id',p_tenant_id,'reason',p_reason,'refund_status',v_refund_status,'refund_request_id',v_request_id));
 return jsonb_build_object('tenantId',p_tenant_id,'orderId',p_order_id,'operationalStatus','cancelled',
  'compensation',jsonb_build_object('refundStatus',v_refund_status,'refundRequestId',v_request_id,'reservationsReleased',true));
end $$;
revoke all on function public.cancel_order_with_compensations(uuid,uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.cancel_order_with_compensations(uuid,uuid,uuid,text,text,text) to service_role;

create or replace function public.claim_order_notification_outbox(p_worker_id text,p_lease_seconds integer)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.order_notification_outbox%rowtype;v_consent boolean;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='NOTIFICATION_SERVICE_ROLE_REQUIRED';end if;
 if p_lease_seconds<10 or p_lease_seconds>300 then raise exception 'invalid_notification_lease';end if;
 select * into v from public.order_notification_outbox
 where ((status in ('queued','retry_pending') and next_attempt_at<=now()) or (status='processing' and lease_expires_at<=now()))
 order by next_attempt_at,created_at for update skip locked limit 1;
 if not found then return null;end if;
 select consent into v_consent from public.order_notification_preferences
 where tenant_id=v.tenant_id and customer_token_hash=v.customer_token_hash and channel=v.channel;
 if not coalesce(v_consent,false) then
  update public.order_notification_outbox set status='suppressed',updated_at=now() where id=v.id returning * into v;
  return jsonb_build_object('id',v.id,'consent',false);
 end if;
 update public.order_notification_outbox set status='processing',lease_owner=p_worker_id,lease_expires_at=now()+make_interval(secs=>p_lease_seconds),
  attempt_count=attempt_count+1,updated_at=now() where id=v.id returning * into v;
 return jsonb_build_object('id',v.id,'orderId',v.order_id,'idempotencyKey',v.idempotency_key,'recipient',v.recipient,
  'message',v.message,'consent',true,'attemptCount',v.attempt_count);
end $$;
revoke all on function public.claim_order_notification_outbox(text,integer) from public,anon,authenticated;
grant execute on function public.claim_order_notification_outbox(text,integer) to service_role;

create or replace function public.complete_order_notification_attempt(
 p_event_id uuid,p_worker_id text,p_status text,p_reason text,p_provider_message_id text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.order_notification_outbox%rowtype;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='NOTIFICATION_SERVICE_ROLE_REQUIRED';end if;
 if p_status not in ('sent','suppressed') then raise exception 'invalid_notification_completion';end if;
 update public.order_notification_outbox set status=p_status,provider_message_id=p_provider_message_id,last_error=p_reason,
  lease_owner=null,lease_expires_at=null,updated_at=now()
 where id=p_event_id and status='processing' and lease_owner=p_worker_id returning * into v;
 if not found then raise exception 'notification_lease_lost';end if;
 insert into public.order_notification_attempts(tenant_id,outbox_id,attempt_number,status,provider_message_id,error_code)
 values(v.tenant_id,v.id,v.attempt_count,p_status,p_provider_message_id,p_reason);
 return jsonb_build_object('eventId',v.id,'status',v.status,'providerMessageId',v.provider_message_id);
end $$;
revoke all on function public.complete_order_notification_attempt(uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.complete_order_notification_attempt(uuid,text,text,text,text) to service_role;

create or replace function public.record_order_notification_failure(
 p_event_id uuid,p_worker_id text,p_error_code text,p_retryable boolean
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.order_notification_outbox%rowtype;v_status text;v_delay integer;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='NOTIFICATION_SERVICE_ROLE_REQUIRED';end if;
 select * into v from public.order_notification_outbox where id=p_event_id and status='processing' and lease_owner=p_worker_id for update;
 if not found then raise exception 'notification_lease_lost';end if;
 v_status:=case when not coalesce(p_retryable,false) or v.attempt_count>=5 then 'dead_letter' else 'retry_pending' end;
 v_delay:=least(3600,(30*(2^greatest(v.attempt_count-1,0)))::integer);
 update public.order_notification_outbox set status=v_status,last_error=left(p_error_code,200),
  next_attempt_at=now()+make_interval(secs=>v_delay),lease_owner=null,lease_expires_at=null,updated_at=now()
 where id=v.id returning * into v;
 insert into public.order_notification_attempts(tenant_id,outbox_id,attempt_number,status,error_code)
 values(v.tenant_id,v.id,v.attempt_count,v.status,p_error_code);
 return jsonb_build_object('eventId',v.id,'status',v.status,'attemptCount',v.attempt_count,'nextAttemptAt',v.next_attempt_at);
end $$;
revoke all on function public.record_order_notification_failure(uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.record_order_notification_failure(uuid,text,text,boolean) to service_role;

rollback;