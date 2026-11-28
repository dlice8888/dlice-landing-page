-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Supplemental RPCs for D03-F03 and D03-F04.
-- Depends on ORDER_MANAGEMENT_WORKFLOWS_DRAFT.sql and POS_SHIFT_CASH_DRAFT.sql.
begin;

alter table public.order_branch_routing_decisions
 add column if not exists service_date date,
 add column if not exists slot_time time,
 add column if not exists capacity_slot_id uuid references public.branch_capacity_slots(id) on delete restrict;

create or replace function public.quote_order_availability(
 p_tenant_id uuid,p_branch_id uuid,p_service_date date,p_requested_time time,p_items jsonb
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_branch public.branches%rowtype;v_hours public.branch_operating_hours%rowtype;v_exception public.branch_operating_exceptions%rowtype;
 v_open time;v_close time;v_cutoff integer;v_capacity integer;v_reserved integer:=0;v_slot timestamptz;v_item jsonb;v_product public.products%rowtype;
 v_available integer;v_items jsonb:='[]'::jsonb;v_ok boolean:=true;v_reason text:='available';
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='ORDER_SERVICE_ROLE_REQUIRED';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'order_items_required';end if;
 select * into v_branch from public.branches where id=p_branch_id and tenant_id=p_tenant_id and status='active';
 if not found then raise exception using errcode='42501',message='ORDER_BRANCH_SCOPE_DENIED';end if;
 select * into v_exception from public.branch_operating_exceptions where tenant_id=p_tenant_id and branch_id=p_branch_id and service_date=p_service_date;
 if found then
  if v_exception.is_closed then v_ok:=false;v_reason:='branch_closed_exception';
  else v_open:=v_exception.opens_at;v_close:=v_exception.closes_at;v_cutoff:=0;v_capacity:=coalesce(v_exception.capacity_override,0);end if;
 else
  select * into v_hours from public.branch_operating_hours where tenant_id=p_tenant_id and branch_id=p_branch_id
   and weekday=extract(dow from p_service_date)::smallint and is_active=true;
  if not found then v_ok:=false;v_reason:='operating_hours_not_configured';
  else v_open:=v_hours.opens_at;v_close:=v_hours.closes_at;v_cutoff:=v_hours.cutoff_minutes;v_capacity:=v_hours.max_orders_per_slot;end if;
 end if;
 if v_ok and (p_requested_time<v_open or p_requested_time>=v_close) then v_ok:=false;v_reason:='outside_operating_hours';end if;
 v_slot:=(p_service_date::text||' '||p_requested_time::text)::timestamp at time zone v_branch.timezone;
 if v_ok and v_slot<now()+make_interval(mins=>coalesce(v_cutoff,0)) then v_ok:=false;v_reason:='order_cutoff_passed';end if;
 select reserved_count into v_reserved from public.branch_capacity_slots where tenant_id=p_tenant_id and branch_id=p_branch_id
  and service_date=p_service_date and slot_time=p_requested_time;
 if found then v_capacity:=least(coalesce(v_capacity,0),(select capacity from public.branch_capacity_slots where tenant_id=p_tenant_id and branch_id=p_branch_id and service_date=p_service_date and slot_time=p_requested_time));
 else v_reserved:=0;end if;
 if v_ok and v_reserved>=coalesce(v_capacity,0) then v_ok:=false;v_reason:='branch_capacity_full';end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  select * into v_product from public.products where id=(v_item->>'productId')::uuid and is_active=true;
  if not found then v_ok:=false;v_available:=0;
  elsif not v_product.stock_tracking_enabled then v_available:=greatest(1,(v_item->>'quantity')::integer);
  else
   select greatest(capacity-reserved_quantity,0) into v_available from public.branch_product_capacity
    where branch_id=p_branch_id and product_id=v_product.id and service_date=p_service_date;
   if not found then v_available:=0;end if;
  end if;
  if v_available<(v_item->>'quantity')::integer then v_ok:=false;v_reason:='product_capacity_insufficient';end if;
  v_items:=v_items||jsonb_build_array(jsonb_build_object('productId',v_item->>'productId',
   'requestedQuantity',(v_item->>'quantity')::integer,'availableQuantity',coalesce(v_available,0)));
 end loop;
 return jsonb_build_object('tenantId',p_tenant_id,'branchId',p_branch_id,'accepted',v_ok,'timezone',v_branch.timezone,
  'serviceDate',p_service_date,'requestedTime',p_requested_time,'reason',v_reason,'items',v_items,
  'capacity',coalesce(v_capacity,0),'reservedCount',coalesce(v_reserved,0),'alternatives','[]'::jsonb);
end $$;
revoke all on function public.quote_order_availability(uuid,uuid,date,time,jsonb) from public,anon,authenticated;
grant execute on function public.quote_order_availability(uuid,uuid,date,time,jsonb) to service_role;

create or replace function public.reserve_order_branch(
 p_tenant_id uuid,p_order_id uuid,p_postal_code text,p_service_date date,p_idempotency_key text,p_items jsonb
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_order public.orders%rowtype;v_area record;v_branch public.branches%rowtype;v_hours public.branch_operating_hours%rowtype;
 v_exception public.branch_operating_exceptions%rowtype;v_slot public.branch_capacity_slots%rowtype;v_item jsonb;v_product public.products%rowtype;
 v_ok boolean;v_total integer:=0;v_reservation_id uuid;v_decision public.order_branch_routing_decisions%rowtype;v_time time;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='ORDER_SERVICE_ROLE_REQUIRED';end if;
 if length(coalesce(p_postal_code,''))<4 or p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'invalid_order_route_request';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_order_id::text||':'||p_idempotency_key,0));
 select * into v_decision from public.order_branch_routing_decisions where tenant_id=p_tenant_id and order_id=p_order_id;
 if found then
  if v_decision.idempotency_key<>p_idempotency_key then raise exception 'order_already_routed_with_different_key';end if;
  return jsonb_build_object('tenantId',p_tenant_id,'orderId',p_order_id,'branchId',v_decision.branch_id,
   'reservationId',v_decision.reservation_id,'reservedCapacity',v_decision.capacity_reserved,'reason',v_decision.reason,'overCapacity',false,'replayed',true);
 end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found then raise exception 'order_not_found';end if;
 v_time:=coalesce(nullif(v_order.requested_time,'')::time,time '12:00');
 for v_area in
  select a.branch_id,a.priority from public.branch_service_areas a join public.branches b on b.id=a.branch_id
  where a.tenant_id=p_tenant_id and a.is_active=true and p_postal_code=any(a.postal_codes) and b.status='active'
  order by a.priority asc,a.branch_id
 loop
  select * into v_branch from public.branches where id=v_area.branch_id and tenant_id=p_tenant_id;
  select * into v_exception from public.branch_operating_exceptions where tenant_id=p_tenant_id and branch_id=v_area.branch_id and service_date=p_service_date;
  if found and v_exception.is_closed then continue;end if;
  if found then
   if v_time<v_exception.opens_at or v_time>=v_exception.closes_at then continue;end if;
  else
   select * into v_hours from public.branch_operating_hours where tenant_id=p_tenant_id and branch_id=v_area.branch_id
    and weekday=extract(dow from p_service_date)::smallint and is_active=true;
   if not found or v_time<v_hours.opens_at or v_time>=v_hours.closes_at then continue;end if;
  end if;
  insert into public.branch_capacity_slots(tenant_id,branch_id,service_date,slot_time,capacity,reserved_count)
  values(p_tenant_id,v_area.branch_id,p_service_date,v_time,coalesce(v_exception.capacity_override,v_hours.max_orders_per_slot,50),0)
  on conflict(tenant_id,branch_id,service_date,slot_time) do nothing;
  select * into v_slot from public.branch_capacity_slots where tenant_id=p_tenant_id and branch_id=v_area.branch_id
   and service_date=p_service_date and slot_time=v_time for update;
  if not found or v_slot.reserved_count>=v_slot.capacity then continue;end if;
  v_ok:=true;v_total:=0;
  for v_item in select value from jsonb_array_elements(p_items) loop
   select * into v_product from public.products where id=(v_item->>'productId')::uuid and is_active=true;
   if not found then v_ok:=false;exit;end if;
   if v_product.stock_tracking_enabled then
    perform 1 from public.branch_product_capacity where branch_id=v_area.branch_id and product_id=v_product.id
     and service_date=p_service_date and capacity-reserved_quantity>=(v_item->>'quantity')::integer for update;
    if not found then v_ok:=false;exit;end if;
   end if;
   v_total:=v_total+(v_item->>'quantity')::integer;
  end loop;
  if not v_ok then continue;end if;
  update public.branch_capacity_slots set reserved_count=reserved_count+1,updated_at=now() where id=v_slot.id;
  for v_item in select value from jsonb_array_elements(p_items) loop
   select * into v_product from public.products where id=(v_item->>'productId')::uuid;
   if v_product.stock_tracking_enabled then
    update public.branch_product_capacity set reserved_quantity=reserved_quantity+(v_item->>'quantity')::integer,updated_at=now()
     where branch_id=v_area.branch_id and product_id=v_product.id and service_date=p_service_date
      and reserved_quantity+(v_item->>'quantity')::integer<=capacity;
    if not found then raise exception 'branch_product_capacity_race';end if;
   end if;
   insert into public.order_reservations(order_id,product_id,service_date,quantity,status,expires_at,branch_id)
   values(p_order_id,v_product.id,p_service_date,(v_item->>'quantity')::integer,'active',now()+interval '30 minutes',v_area.branch_id);
  end loop;
  update public.orders set branch_id=v_area.branch_id,branch_selection_source='staff_assignment',version=version+1,updated_at=now()
   where id=p_order_id;
  insert into public.order_branch_routing_decisions(tenant_id,order_id,branch_id,postal_code,reservation_id,reason,capacity_reserved,idempotency_key,service_date,slot_time,capacity_slot_id)
  values(p_tenant_id,p_order_id,v_area.branch_id,p_postal_code,null,'postal_code_match_capacity_reserved',v_total,p_idempotency_key,p_service_date,v_time,v_slot.id)
  returning * into v_decision;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(null,'order_branch_routed','order',p_order_id::text,jsonb_build_object('tenant_id',p_tenant_id,'branch_id',v_area.branch_id,'postal_code',p_postal_code,'reserved_capacity',v_total));
  return jsonb_build_object('tenantId',p_tenant_id,'orderId',p_order_id,'branchId',v_area.branch_id,
   'reservationId',v_decision.id,'reservedCapacity',v_total,'reason',v_decision.reason,'overCapacity',false,'replayed',false);
 end loop;
 raise exception using errcode='P0001',message='NO_ELIGIBLE_BRANCH_CAPACITY';
end $$;
revoke all on function public.reserve_order_branch(uuid,uuid,text,date,text,jsonb) from public,anon,authenticated;
grant execute on function public.reserve_order_branch(uuid,uuid,text,date,text,jsonb) to service_role;

create or replace function public.release_order_branch_capacity(
 p_tenant_id uuid,p_order_id uuid,p_reservation_id uuid,p_reason text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_decision public.order_branch_routing_decisions%rowtype;v_res public.order_reservations%rowtype;v_count integer:=0;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='ORDER_SERVICE_ROLE_REQUIRED';end if;
 select * into v_decision from public.order_branch_routing_decisions where tenant_id=p_tenant_id and order_id=p_order_id and id=p_reservation_id for update;
 if not found then return jsonb_build_object('tenantId',p_tenant_id,'reservationId',p_reservation_id,'released',false,'reason','not_found');end if;
 for v_res in select * from public.order_reservations where order_id=p_order_id and branch_id=v_decision.branch_id and status in ('active','held_for_verification') for update loop
  update public.branch_product_capacity set reserved_quantity=greatest(0,reserved_quantity-v_res.quantity),updated_at=now()
   where branch_id=v_res.branch_id and product_id=v_res.product_id and service_date=v_res.service_date;
  update public.order_reservations set status='released',released_at=now(),updated_at=now() where id=v_res.id;
  v_count:=v_count+1;
 end loop;
 if v_decision.capacity_slot_id is not null then
  update public.branch_capacity_slots set reserved_count=greatest(0,reserved_count-1),updated_at=now() where id=v_decision.capacity_slot_id;
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(null,'order_branch_capacity_released','order',p_order_id::text,jsonb_build_object('tenant_id',p_tenant_id,'reason',p_reason,'reservation_count',v_count));
 return jsonb_build_object('tenantId',p_tenant_id,'reservationId',p_reservation_id,'released',true,'reservationCount',v_count);
end $$;
revoke all on function public.release_order_branch_capacity(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.release_order_branch_capacity(uuid,uuid,uuid,text) to service_role;

rollback;