-- Atomic checkout, private proof bucket, and idempotent notification log.
create or replace function public.create_order_with_reservations(p_order jsonb, p_items jsonb, p_tracking_token_hash text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_order_id uuid; v_item jsonb; v_product public.products%rowtype; v_capacity public.product_capacity%rowtype;
  v_qty integer; v_subtotal bigint := 0; v_now_local timestamp; v_requested_date date;
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 20 then raise exception 'invalid_items' using errcode='22023'; end if;
  if nullif(trim(p_order->>'customer_name'),'') is null or nullif(trim(p_order->>'customer_whatsapp'),'') is null or nullif(trim(p_order->>'requested_date'),'') is null or nullif(trim(p_order->>'requested_time'),'') is null or p_order->>'receiving_method' not in ('pickup','delivery') then raise exception 'invalid_order' using errcode='22023'; end if;
  v_requested_date := (p_order->>'requested_date')::date; v_now_local := now() at time zone 'Asia/Makassar';
  if v_requested_date < v_now_local::date then raise exception 'date_in_past' using errcode='22023'; end if;
  if v_requested_date = v_now_local::date and v_now_local::time >= time '18:00' then raise exception 'same_day_cutoff_passed' using errcode='22023'; end if;
  if p_order->>'receiving_method'='delivery' and nullif(trim(p_order->>'delivery_address'),'') is null then raise exception 'delivery_address_required' using errcode='22023'; end if;
  if p_order->>'receiving_method'='pickup' and nullif(trim(p_order->>'delivery_address'),'') is not null then raise exception 'unexpected_delivery_address' using errcode='22023'; end if;
  if p_tracking_token_hash is null or length(p_tracking_token_hash)<>64 then raise exception 'invalid_tracking_token' using errcode='22023'; end if;
  -- Lock capacity rows in deterministic order; locks serialize checkout for the same product/date.
  for v_item in select value from jsonb_array_elements(p_items) order by value->>'product_id' loop
    if coalesce((v_item->>'quantity')::integer,0)<1 or (v_item->>'quantity')::integer>100 then raise exception 'invalid_quantity' using errcode='22023'; end if;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and is_active=true;
    if not found or v_product.unit_price_idr is null then raise exception 'product_unavailable_or_price_missing' using errcode='22023'; end if;
    select * into v_capacity from public.product_capacity where product_id=v_product.id and service_date=v_requested_date for update;
    if not found then raise exception 'capacity_not_configured' using errcode='22023'; end if;
    if v_capacity.capacity-coalesce((select sum(r.quantity) from public.order_reservations r where r.product_id=v_product.id and r.service_date=v_requested_date and (r.status='held_for_verification' or (r.status='active' and r.expires_at>now())),0)<(v_item->>'quantity')::integer then raise exception 'capacity_exceeded' using errcode='22023'; end if;
    v_subtotal := v_subtotal + v_product.unit_price_idr::bigint*(v_item->>'quantity')::integer;
  end loop;
  insert into public.orders(tracking_token_hash,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr)
  values(p_tracking_token_hash,trim(p_order->>'customer_name'),trim(p_order->>'customer_whatsapp'),v_requested_date,trim(p_order->>'requested_time'),p_order->>'receiving_method',nullif(trim(p_order->>'delivery_address'),''),nullif(trim(p_order->>'customer_notes'),''),v_subtotal::integer) returning id into v_order_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid; v_qty:=(v_item->>'quantity')::integer;
    insert into public.order_items(order_id,product_id,product_name_snapshot,quantity,unit_price_idr) values(v_order_id,v_product.id,v_product.name,v_qty,v_product.unit_price_idr);
    insert into public.order_reservations(order_id,product_id,service_date,quantity,status,expires_at) values(v_order_id,v_product.id,v_requested_date,v_qty,'active',now()+interval '15 minutes');
  end loop;
  insert into public.order_status_history(order_id,status_type,new_status,note) values(v_order_id,'operational','received','Order created through public checkout');
  return jsonb_build_object('order_id',v_order_id,'subtotal_idr',v_subtotal,'reservation_expires_at',now()+interval '15 minutes');
end; $$;
revoke all on function public.create_order_with_reservations(jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.create_order_with_reservations(jsonb,jsonb,text) to service_role;
create table public.notification_log(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete restrict,notification_type text not null check(notification_type in ('payment_verified_whatsapp')),status text not null default 'queued' check(status in ('queued','sent','failed','manual_action_required')),idempotency_key text not null unique,recipient_whatsapp text not null,message_text text not null,provider_reference text,attempts integer not null default 0,last_error text,created_at timestamptz not null default now(),sent_at timestamptz);
alter table public.notification_log enable row level security;
revoke all on public.notification_log from anon,authenticated;
grant all on public.notification_log to service_role;
create index if not exists notification_log_order_id_idx on public.notification_log(order_id);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('dlice-payment-proofs','dlice-payment-proofs',false,5242880,array['image/jpeg','image/png','image/webp','application/pdf']) on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];
