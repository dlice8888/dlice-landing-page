-- Atomic operational status changes with matching history and audit log.
create or replace function public.admin_apply_operational_status_change(
 p_order_id uuid,p_actor_user_id uuid,p_next_status text,p_reason text
) returns boolean
language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_old_status text; v_payment_status text; v_notification_status text;
begin
 if p_next_status not in ('received','confirmed','preparing','ready_for_pickup','waiting_for_courier','in_delivery','completed','cancelled','delivery_issue') then
   raise exception 'Invalid operational status';
 end if;
 if p_next_status in ('cancelled','delivery_issue') and length(trim(coalesce(p_reason,''))) < 4 then
   return false;
 end if;
 select operational_status,payment_status into v_old_status,v_payment_status
 from public.orders where id=p_order_id for update;
 if not found then return false; end if;
 if p_next_status in ('preparing','ready_for_pickup','waiting_for_courier','in_delivery','completed')
    and v_payment_status <> 'paid' then return false; end if;
 if v_payment_status='paid' and p_next_status<>v_old_status then
   select status into v_notification_status
   from public.notification_log
   where order_id=p_order_id and notification_type='payment_verified_whatsapp'
   order by created_at desc limit 1;
   if v_notification_status is distinct from 'sent' then return false; end if;
 end if;
 update public.orders set operational_status=p_next_status where id=p_order_id;
 insert into public.order_status_history(order_id,status_type,old_status,new_status,changed_by,note)
 values(p_order_id,'operational',v_old_status,p_next_status,p_actor_user_id,nullif(left(trim(coalesce(p_reason,'')),500),''));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'update_order_status','order',p_order_id::text,
   jsonb_build_object('old_status',v_old_status,'new_status',p_next_status,'reason',left(trim(coalesce(p_reason,'')),500)));
 return true;
end; $$;
revoke all on function public.admin_apply_operational_status_change(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.admin_apply_operational_status_change(uuid,uuid,text,text) to service_role;
