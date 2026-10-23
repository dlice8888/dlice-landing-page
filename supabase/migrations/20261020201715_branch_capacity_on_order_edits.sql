-- Applied to staging as migration 20261020201715.
CREATE OR REPLACE FUNCTION public.update_order_with_reservations(p_order_id uuid, p_tracking_token_hash text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_order public.orders%rowtype; v_item jsonb; v_product public.products%rowtype; v_capacity public.product_capacity%rowtype; v_branch_capacity public.branch_product_capacity%rowtype;
  v_qty integer; v_subtotal bigint := 0; v_reserved bigint := 0;
begin
  if p_order_id is null or p_tracking_token_hash is null or length(p_tracking_token_hash) <> 64 or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 20 then raise exception 'invalid_update_request' using errcode='22023'; end if;
  select * into v_order from public.orders where id=p_order_id and tracking_token_hash=p_tracking_token_hash for update;
  if not found then raise exception 'order_not_found' using errcode='P0002'; end if;
  if v_order.branch_id is null then raise exception 'order_branch_missing' using errcode='55000'; end if;
  if v_order.payment_status <> 'unpaid' then raise exception 'order_already_paid_or_payment_started' using errcode='55000'; end if;
  if exists(select 1 from public.payment_records p where p.order_id=p_order_id and p.proof_storage_path is not null) then raise exception 'proof_already_uploaded_contact_admin' using errcode='55000'; end if;
  if exists(select 1 from public.order_reservations r where r.order_id=p_order_id and (r.status <> 'active' or r.expires_at <= now())) then raise exception 'reservation_expired_contact_admin' using errcode='55000'; end if;
  for v_item in select value from jsonb_array_elements(p_items) order by value->>'slug' loop
    v_qty:=coalesce((v_item->>'quantity')::integer,0);
    if v_qty<1 or v_qty>100 then raise exception 'invalid_quantity' using errcode='22023'; end if;
    select * into v_product from public.products where slug=(v_item->>'slug') and is_active=true;
    if not found or v_product.unit_price_idr is null then raise exception 'product_unavailable_or_price_missing' using errcode='22023'; end if;
    select * into v_capacity from public.product_capacity where product_id=v_product.id and service_date=v_order.requested_date for update;
    if not found then raise exception 'capacity_not_configured' using errcode='22023'; end if;
    select coalesce(sum(r.quantity),0) into v_reserved
    from public.order_reservations r
    where r.product_id=v_product.id and r.service_date=v_order.requested_date and r.order_id<>p_order_id
      and (r.status='held_for_verification' or (r.status='active' and r.expires_at>now()));
    if v_capacity.capacity-v_reserved<v_qty then raise exception 'capacity_exceeded' using errcode='22023'; end if;
    select * into v_branch_capacity from public.branch_product_capacity where branch_id=v_order.branch_id and product_id=v_product.id and service_date=v_order.requested_date for update;
    if not found then raise exception 'branch_capacity_not_configured' using errcode='22023'; end if;
    select coalesce(sum(r.quantity),0) into v_reserved from public.order_reservations r
      where r.branch_id=v_order.branch_id and r.product_id=v_product.id and r.service_date=v_order.requested_date and r.order_id<>p_order_id
      and (r.status='held_for_verification' or (r.status='active' and r.expires_at>now()));
    if v_branch_capacity.capacity-v_reserved<v_qty then raise exception 'branch_capacity_exceeded' using errcode='22023'; end if;
    v_subtotal:=v_subtotal+(v_product.unit_price_idr::bigint*v_qty);
  end loop;
  delete from public.order_items where order_id=p_order_id;
  delete from public.order_reservations where order_id=p_order_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    select * into v_product from public.products where slug=(v_item->>'slug') and is_active=true;
    v_qty:=(v_item->>'quantity')::integer;
    insert into public.order_items(order_id,product_id,product_name_snapshot,quantity,unit_price_idr) values(p_order_id,v_product.id,v_product.name,v_qty,v_product.unit_price_idr);
    insert into public.order_reservations(order_id,product_id,service_date,quantity,status,expires_at,branch_id) values(p_order_id,v_product.id,v_order.requested_date,v_qty,'active',now()+interval '15 minutes',v_order.branch_id);
  end loop;
  update public.orders set product_subtotal_idr=v_subtotal::integer,receipt_version=receipt_version+1,receipt_confirmed_version=null,receipt_confirmed_at=null,receipt_snapshot=null,final_whatsapp_requested_at=null,updated_at=now() where id=p_order_id;
  insert into public.order_status_history(order_id,status_type,old_status,new_status,note) values(p_order_id,'reservation','receipt_version_'||v_order.receipt_version,'receipt_version_'||(v_order.receipt_version+1),'Order items changed; prior receipt approval invalidated');
  return jsonb_build_object('order_id',p_order_id,'subtotal_idr',v_subtotal,'receipt_version',v_order.receipt_version+1,'reservation_expires_at',now()+interval '15 minutes');
end;
$function$
;
revoke all on function public.update_order_with_reservations(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.update_order_with_reservations(uuid,text,jsonb) to service_role;
