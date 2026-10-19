-- Make payment verification, order payment status, history, audit, and reservation changes atomic.
create or replace function public.admin_apply_payment_verification(
  p_order_id uuid,
  p_payment_id uuid,
  p_actor_user_id uuid,
  p_result text,
  p_note text
)
returns boolean
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_old_status text;
  v_proof_path text;
  v_payment_status text;
begin
  if p_result not in ('paid','rejected') then
    raise exception 'Invalid payment result';
  end if;

  select payment_status into v_old_status
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_old_status in ('paid','refunded') then
    return false;
  end if;

  select status, proof_storage_path into v_payment_status, v_proof_path
  from public.payment_records
  where id = p_payment_id and order_id = p_order_id
  for update;

  if not found or v_payment_status <> 'pending_verification' then
    return false;
  end if;
  if p_result = 'paid' and (v_proof_path is null or length(v_proof_path) = 0) then
    return false;
  end if;

  update public.payment_records
  set status = p_result,
      verified_by = p_actor_user_id,
      verified_at = now(),
      admin_note = nullif(left(coalesce(p_note,''),500),'')
  where id = p_payment_id;

  update public.orders set payment_status = p_result where id = p_order_id;

  insert into public.order_status_history
    (order_id, status_type, old_status, new_status, changed_by, note)
  values
    (p_order_id, 'payment', v_old_status, p_result, p_actor_user_id, nullif(left(coalesce(p_note,''),500),''));

  insert into public.admin_audit_logs
    (actor_user_id, action, entity_type, entity_id, metadata)
  values
    (p_actor_user_id, 'verify_payment', 'order', p_order_id::text,
     jsonb_build_object('result',p_result,'payment_id',p_payment_id,'note',left(coalesce(p_note,''),500)));

  if p_result = 'paid' then
    update public.order_reservations
    set status = 'consumed'
    where order_id = p_order_id and status in ('held_for_verification','active');
  else
    update public.order_reservations
    set status = 'released', released_at = now()
    where order_id = p_order_id and status in ('held_for_verification','active');
  end if;

  return true;
end;
$$;

revoke all on function public.admin_apply_payment_verification(uuid,uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.admin_apply_payment_verification(uuid,uuid,uuid,text,text) to service_role;
