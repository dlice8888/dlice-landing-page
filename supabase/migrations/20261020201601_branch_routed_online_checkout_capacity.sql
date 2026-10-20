-- Applied to staging as migration 20261020201601.
CREATE OR REPLACE FUNCTION public.create_order_with_reservations(p_order jsonb, p_items jsonb, p_tracking_token_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 v_order_id uuid; v_item jsonb; v_product public.products%rowtype; v_capacity public.product_capacity%rowtype;
 v_branch public.branches%rowtype; v_branch_capacity public.branch_product_capacity%rowtype;
 v_qty integer; v_subtotal bigint:=0; v_now_local timestamp; v_requested_date date; v_reserved bigint;
begin
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>20 then raise exception 'invalid_items' using errcode='22023'; end if;
 if nullif(trim(p_order->>'customer_name'),'') is null or nullif(trim(p_order->>'customer_whatsapp'),'') is null or nullif(trim(p_order->>'requested_date'),'') is null or nullif(trim(p_order->>'requested_time'),'') is null or p_order->>'receiving_method' not in ('pickup','delivery') then raise exception 'invalid_order' using errcode='22023'; end if;
 v_requested_date:=(p_order->>'requested_date')::date; v_now_local:=now() at time zone 'Asia/Makassar';
 if v_requested_date<v_now_local::date then raise exception 'date_in_past' using errcode='22023'; end if;
 if v_requested_date=v_now_local::date and v_now_local::time>=time '18:00' then raise exception 'same_day_cutoff_passed' using errcode='22023'; end if;
 if p_order->>'receiving_method'='delivery' and nullif(trim(p_order->>'delivery_address'),'') is null then raise exception 'delivery_address_required' using errcode='22023'; end if;
 if p_order->>'receiving_method'='pickup' and nullif(trim(p_order->>'delivery_address'),'') is not null then raise exception 'unexpected_delivery_address' using errcode='22023'; end if;
 if p_tracking_token_hash is null or length(p_tracking_token_hash)<>64 then raise exception 'invalid_tracking_token' using errcode='22023'; end if;
 if nullif(p_order->>'branch_id','') is null then raise exception 'branch_required' using errcode='22023'; end if;
 -- Lock the selected branch row so concurrent checkouts cannot exceed a branch-wide daily cap.
 select * into v_branch from public.branches where id=(p_order->>'branch_id')::uuid and status='active' and accepts_online_orders=true for update;
 if not found then raise exception 'branch_not_online' using errcode='22023'; end if;
 if p_order->>'receiving_method'='pickup' and not v_branch.pickup_enabled then raise exception 'branch_method_unavailable' using errcode='22023'; end if;
 if p_order->>'receiving_method'='delivery' and not v_branch.delivery_enabled then raise exception 'branch_method_unavailable' using errcode='22023'; end if;
 if v_branch.daily_order_capacity is not null and
   (select count(*) from public.orders o where o.branch_id=v_branch.id and o.requested_date=v_requested_date and o.fulfillment_status not in ('cancelled','failed'))>=v_branch.daily_order_capacity then
   raise exception 'branch_daily_capacity_exceeded' using errcode='22023';
 end if;
 -- Deterministic product order prevents lock-order deadlocks when cart contains multiple products.
 for v_item in select value from jsonb_array_elements(p_items) order by value->>'product_id' loop
  if coalesce((v_item->>'quantity')::integer,0)<1 or (v_item->>'quantity')::integer>100 then raise exception 'invalid_quantity' using errcode='22023'; end if;
  select * into v_product from public.products where id=(v_item->>'product_id')::uuid and is_active=true;
  if not found or v_product.unit_price_idr is null then raise exception 'product_unavailable_or_price_missing' using errcode='22023'; end if;
  select * into v_capacity from public.product_capacity where product_id=v_product.id and service_date=v_requested_date for update;
  if not found then raise exception 'capacity_not_configured' using errcode='22023'; end if;
  if v_capacity.capacity-coalesce((select sum(r.quantity) from public.order_reservations r where r.product_id=v_product.id and r.service_date=v_requested_date and (r.status='held_for_verification' or (r.status='active' and r.expires_at>now()))),0)<(v_item->>'quantity')::integer then raise exception 'capacity_exceeded' using errcode='22023'; end if;
  select * into v_branch_capacity from public.branch_product_capacity where branch_id=v_branch.id and product_id=v_product.id and service_date=v_requested_date for update;
  if not found then raise exception 'branch_capacity_not_configured' using errcode='22023'; end if;
  select coalesce(sum(r.quantity),0) into v_reserved from public.order_reservations r where r.branch_id=v_branch.id and r.product_id=v_product.id and r.service_date=v_requested_date and (r.status='held_for_verification' or (r.status='active' and r.expires_at>now()));
  if v_branch_capacity.capacity-v_reserved<(v_item->>'quantity')::integer then raise exception 'branch_capacity_exceeded' using errcode='22023'; end if;
  v_subtotal:=v_subtotal+v_product.unit_price_idr::bigint*(v_item->>'quantity')::integer;
 end loop;
 insert into public.orders(branch_id,branch_selection_source,fulfillment_status,tracking_token_hash,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr)
 values(v_branch.id,coalesce(nullif(p_order->>'branch_selection_source',''),'customer_choice'),'queued',p_tracking_token_hash,trim(p_order->>'customer_name'),trim(p_order->>'customer_whatsapp'),v_requested_date,trim(p_order->>'requested_time'),p_order->>'receiving_method',nullif(trim(p_order->>'delivery_address'),''),nullif(trim(p_order->>'customer_notes'),''),v_subtotal::integer)
 returning id into v_order_id;
 for v_item in select value from jsonb_array_elements(p_items) loop
  select * into v_product from public.products where id=(v_item->>'product_id')::uuid;
  v_qty:=(v_item->>'quantity')::integer;
  insert into public.order_items(order_id,product_id,product_name_snapshot,quantity,unit_price_idr) values(v_order_id,v_product.id,v_product.name,v_qty,v_product.unit_price_idr);
  insert into public.order_reservations(order_id,product_id,service_date,quantity,status,expires_at,branch_id) values(v_order_id,v_product.id,v_requested_date,v_qty,'active',now()+interval '15 minutes',v_branch.id);
 end loop;
 insert into public.order_status_history(order_id,status_type,new_status,note) values(v_order_id,'operational','received','Order created through public checkout; branch assigned');
 return jsonb_build_object('order_id',v_order_id,'branch_id',v_branch.id,'subtotal_idr',v_subtotal,'reservation_expires_at',now()+interval '15 minutes');
end; $function$
;
revoke all on function public.create_order_with_reservations(jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.create_order_with_reservations(jsonb,jsonb,text) to service_role;
