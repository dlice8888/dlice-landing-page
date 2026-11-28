-- T09 / D02-F13: keep order, payment and fulfillment state machines independent and atomic.
begin;

alter table public.orders
 add column if not exists state_version integer not null default 1;

alter table public.orders drop constraint if exists orders_payment_status_check;
alter table public.orders add constraint orders_payment_status_check
 check(payment_status in ('unpaid','pending_verification','paid','rejected','partially_refunded','refunded'));

create table if not exists public.order_state_transition_events(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 order_id uuid not null references public.orders(id) on delete restrict,
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 domain text not null check(domain in ('order','payment','fulfillment')),
 previous_status text not null,
 next_status text not null,
 expected_version integer not null check(expected_version>0),
 version integer not null check(version>expected_version),
 idempotency_key text not null check(length(idempotency_key) between 8 and 120),
 payload_fingerprint text not null,
 reason text,
 evidence jsonb not null default '{}'::jsonb,
 result jsonb not null,
 created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,actor_user_id,idempotency_key)
);
create index if not exists order_state_transition_history_idx
 on public.order_state_transition_events(tenant_id,order_id,created_at desc);

alter table public.order_state_transition_events enable row level security;
alter table public.order_state_transition_events force row level security;
drop policy if exists service_role_only on public.order_state_transition_events;
create policy service_role_only on public.order_state_transition_events
 for all to service_role using(true) with check(true);
revoke all on public.order_state_transition_events from public,anon,authenticated;
grant select,insert on public.order_state_transition_events to service_role;

create or replace function public.pos_transition_order_state_atomic(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_order_id uuid,p_domain text,p_next_status text,
 p_expected_version integer,p_idempotency_key text,p_payment_evidence_type text default null,
 p_handover_acknowledgement text default null,p_reason text default null
) returns jsonb language plpgsql security invoker set search_path=''
as $fn$
declare
 v_order public.orders%rowtype;
 v_payment public.payment_records%rowtype;
 v_current_status text;
 v_fingerprint text;
 v_existing public.order_state_transition_events%rowtype;
 v_event_id uuid:=gen_random_uuid();
 v_version integer;
 v_refund_total bigint;
 v_history_type text;
 v_reason text:=left(coalesce(p_reason,''),500);
 v_result jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then
  raise exception using errcode='42501',message='ORDER_STATE_SERVICE_ROLE_REQUIRED';
 end if;
 if p_domain not in ('order','payment','fulfillment') or p_expected_version is null or p_expected_version<1
   or p_idempotency_key is null or length(trim(p_idempotency_key))<8 or length(p_idempotency_key)>120 then
  raise exception using errcode='22023',message='ORDER_STATE_INPUT_INVALID';
 end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then
  raise exception using errcode='42501',message='ORDER_STATE_BRANCH_SCOPE_DENIED';
 end if;
 v_fingerprint:=encode(extensions.digest(jsonb_build_object('order_id',p_order_id,'branch_id',p_branch_id,
  'domain',p_domain,'next_status',p_next_status,'expected_version',p_expected_version,
  'payment_evidence_type',p_payment_evidence_type,'handover_acknowledgement',p_handover_acknowledgement,
  'reason',v_reason)::text,'sha256'),'hex');
 select * into v_existing from public.order_state_transition_events
 where tenant_id=p_tenant_id and actor_user_id=p_actor_user_id and idempotency_key=p_idempotency_key
 for update;
 if found then
  if v_existing.payload_fingerprint<>v_fingerprint then
   raise exception using errcode='23505',message='ORDER_STATE_IDEMPOTENCY_PAYLOAD_MISMATCH';
  end if;
  return v_existing.result||jsonb_build_object('idempotent_replay',true);
 end if;
 select o.* into v_order from public.orders o
 join public.branches b on b.id=o.branch_id and b.tenant_id=p_tenant_id
 where o.id=p_order_id and o.branch_id=p_branch_id
 for update of o;
 if not found then raise exception using errcode='P0002',message='ORDER_STATE_ORDER_NOT_FOUND';end if;
 if v_order.state_version<>p_expected_version then
  raise exception using errcode='40001',message='ORDER_STATE_STALE_VERSION';
 end if;
 v_version:=v_order.state_version+1;
 v_history_type:=case p_domain when 'order' then 'operational' else p_domain end;

 if p_domain='order' then
  v_current_status:=v_order.operational_status;
  if not (
   (v_current_status='received' and p_next_status in ('confirmed','cancelled')) or
   (v_current_status='confirmed' and p_next_status in ('preparing','cancelled')) or
   (v_current_status='preparing' and p_next_status in ('ready_for_pickup','waiting_for_courier','in_delivery','cancelled')) or
   (v_current_status='ready_for_pickup' and p_next_status in ('completed','cancelled')) or
   (v_current_status='waiting_for_courier' and p_next_status in ('in_delivery','delivery_issue','cancelled')) or
   (v_current_status='in_delivery' and p_next_status in ('completed','delivery_issue')) or
   (v_current_status='delivery_issue' and p_next_status in ('in_delivery','cancelled'))
  ) then raise exception using errcode='55000',message='ORDER_STATE_TRANSITION_INVALID';end if;
  if p_next_status in ('preparing','ready_for_pickup','waiting_for_courier','in_delivery','completed')
    and v_order.payment_status<>'paid' then
   raise exception using errcode='55000',message='ORDER_PAYMENT_NOT_SETTLED';
  end if;
  if p_next_status in ('cancelled','delivery_issue') and length(btrim(v_reason))<4 then
   raise exception using errcode='22023',message='ORDER_STATE_REASON_REQUIRED';
  end if;
  if v_order.payment_status='paid' and p_next_status<>v_current_status and not exists(
   select 1 from public.notification_log n where n.order_id=p_order_id
    and n.notification_type='payment_verified_whatsapp' and n.status='sent'
  ) then raise exception using errcode='55000',message='ORDER_PAYMENT_NOTIFICATION_NOT_SENT';end if;
  update public.orders set operational_status=p_next_status,state_version=v_version,updated_at=now()
  where id=p_order_id and state_version=p_expected_version;

 elsif p_domain='payment' then
  v_current_status:=v_order.payment_status;
  if not (
   (v_current_status='unpaid' and p_next_status in ('pending_verification','paid','rejected')) or
   (v_current_status='pending_verification' and p_next_status in ('paid','rejected')) or
   (v_current_status='paid' and p_next_status in ('partially_refunded','refunded')) or
   (v_current_status='partially_refunded' and p_next_status='refunded')
  ) then raise exception using errcode='55000',message='ORDER_PAYMENT_TRANSITION_INVALID';end if;
  if p_next_status in ('pending_verification','paid','rejected') then
   select * into v_payment from public.payment_records where order_id=p_order_id
   order by created_at desc,id desc limit 1 for update;
   if not found then raise exception using errcode='55000',message='ORDER_PAYMENT_RECORD_REQUIRED';end if;
   if p_next_status='pending_verification' then
    if v_payment.status<>'pending_verification' then raise exception using errcode='55000',message='ORDER_PAYMENT_PROOF_PENDING_REQUIRED';end if;
    update public.orders set payment_status='pending_verification',state_version=v_version,updated_at=now()
     where id=p_order_id and state_version=p_expected_version;
   elsif p_next_status='paid' then
    if v_payment.status<>'pending_verification' then raise exception using errcode='55000',message='ORDER_PAYMENT_VERIFICATION_REQUIRED';end if;
    if p_payment_evidence_type='cash_tender' then
     if v_payment.method<>'cash' then raise exception using errcode='42501',message='ORDER_CASH_TENDER_EVIDENCE_MISMATCH';end if;
    elsif p_payment_evidence_type='verified_provider_event' then
     if v_payment.method='cash' or nullif(v_payment.proof_storage_path,'') is null then
      raise exception using errcode='42501',message='ORDER_PROVIDER_PROOF_REQUIRED';
     end if;
    else raise exception using errcode='42501',message='ORDER_PAYMENT_PROOF_REQUIRED';end if;
    update public.payment_records set status='paid',verified_by=p_actor_user_id,verified_at=now()
     where id=v_payment.id and status='pending_verification';
    update public.orders set payment_status='paid',state_version=v_version,updated_at=now()
     where id=p_order_id and state_version=p_expected_version;
    update public.order_reservations set status='consumed'
     where order_id=p_order_id and status in ('held_for_verification','active');
   else
    if v_payment.status<>'pending_verification' then raise exception using errcode='55000',message='ORDER_PAYMENT_VERIFICATION_REQUIRED';end if;
    update public.payment_records set status='rejected',verified_by=p_actor_user_id,verified_at=now(),
     admin_note=nullif(v_reason,'') where id=v_payment.id and status='pending_verification';
    update public.orders set payment_status='rejected',state_version=v_version,updated_at=now()
     where id=p_order_id and state_version=p_expected_version;
    update public.order_reservations set status='released',released_at=now()
     where order_id=p_order_id and status in ('held_for_verification','active');
   end if;
  else
   select coalesce(sum(r.amount_idr),0)::bigint into v_refund_total from public.refund_records r
   where r.order_id=p_order_id and r.status='processed';
   if p_next_status='partially_refunded' and (v_refund_total<=0 or v_refund_total>=v_order.product_subtotal_idr) then
    raise exception using errcode='23514',message='ORDER_PARTIAL_REFUND_TOTAL_INVALID';
   elsif p_next_status='refunded' and v_refund_total<v_order.product_subtotal_idr then
    raise exception using errcode='23514',message='ORDER_FULL_REFUND_TOTAL_REQUIRED';
   end if;
   update public.orders set payment_status=p_next_status,state_version=v_version,updated_at=now()
    where id=p_order_id and state_version=p_expected_version;
  end if;

 else
  v_current_status:=v_order.fulfillment_status;
  if not (
   (v_current_status='unassigned' and p_next_status in ('queued','cancelled')) or
   (v_current_status='queued' and p_next_status in ('accepted','cancelled')) or
   (v_current_status='accepted' and p_next_status in ('preparing','failed','cancelled')) or
   (v_current_status='preparing' and p_next_status in ('ready','failed','cancelled')) or
   (v_current_status='ready' and p_next_status in ('dispatched','fulfilled','cancelled')) or
   (v_current_status='dispatched' and p_next_status in ('fulfilled','failed')) or
   (v_current_status='failed' and p_next_status in ('queued','cancelled'))
  ) then raise exception using errcode='55000',message='ORDER_FULFILLMENT_TRANSITION_INVALID';end if;
  if p_next_status in ('dispatched','fulfilled') and v_order.payment_status not in ('paid','partially_refunded') then
   raise exception using errcode='55000',message='ORDER_PAYMENT_NOT_SETTLED';
  end if;
  if p_next_status='dispatched' and length(btrim(coalesce(p_handover_acknowledgement,'')))<4 then
   raise exception using errcode='22023',message='ORDER_HANDOVER_ACK_REQUIRED';
  end if;
  update public.orders set fulfillment_status=p_next_status,fulfillment_notes=coalesce(nullif(v_reason,''),fulfillment_notes),
   fulfilled_at=case when p_next_status='fulfilled' then now() else fulfilled_at end,
   state_version=v_version,updated_at=now()
  where id=p_order_id and state_version=p_expected_version;
 end if;

 insert into public.order_status_history(order_id,status_type,old_status,new_status,changed_by,note)
 values(p_order_id,v_history_type,v_current_status,p_next_status,p_actor_user_id,
  coalesce(nullif(v_reason,''),nullif(p_handover_acknowledgement,''),'Atomic state transition'));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'order.state.'||p_domain||'.'||p_next_status,'order',p_order_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'previous_status',v_current_status,
   'next_status',p_next_status,'expected_version',p_expected_version,'version',v_version,
   'payment_evidence_type',p_payment_evidence_type,'handover_acknowledgement',p_handover_acknowledgement));
 v_result:=jsonb_build_object('orderId',p_order_id,'tenantId',p_tenant_id,'branchId',p_branch_id,
  'domain',p_domain,'status',p_next_status,'version',v_version,'transitionEventId',v_event_id);
 insert into public.order_state_transition_events(id,tenant_id,branch_id,order_id,actor_user_id,domain,previous_status,next_status,
  expected_version,version,idempotency_key,payload_fingerprint,reason,evidence,result)
 values(v_event_id,p_tenant_id,p_branch_id,p_order_id,p_actor_user_id,p_domain,v_current_status,p_next_status,
  p_expected_version,v_version,p_idempotency_key,v_fingerprint,nullif(v_reason,''),
  jsonb_build_object('payment_evidence_type',p_payment_evidence_type,'handover_acknowledgement',p_handover_acknowledgement),v_result);
 return v_result||jsonb_build_object('idempotent_replay',false);
end;
$fn$;

revoke all on function public.pos_transition_order_state_atomic(uuid,uuid,uuid,uuid,text,text,integer,text,text,text,text)
 from public,anon,authenticated;
grant execute on function public.pos_transition_order_state_atomic(uuid,uuid,uuid,uuid,text,text,integer,text,text,text,text)
 to service_role;

commit;
