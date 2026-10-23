-- Expand stock transfer workflow to match the operational approval and reconciliation gates.
alter table public.stock_transfers drop constraint if exists stock_transfers_status_check;
alter table public.stock_transfers add constraint stock_transfers_status_check check (status = any (array['draft','approved','picked','shipped','received','reconciled','cancelled']::text[]));
CREATE OR REPLACE FUNCTION public.erp_transition_stock_transfer(p_transfer_id uuid, p_actor_user_id uuid, p_transition text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_transfer public.stock_transfers%rowtype;
  v_item record;
  v_balance numeric;
  v_count integer := 0;
begin
  if p_transition is null or p_transition not in ('approve','pick','ship','receive','reconcile','cancel') then
    raise exception 'invalid_transfer_transition';
  end if;

  select * into v_transfer from public.stock_transfers where id=p_transfer_id for update;
  if not found then raise exception 'stock_transfer_not_found'; end if;

  if (p_transition='approve' and v_transfer.status='approved')
    or (p_transition='pick' and v_transfer.status='picked')
    or (p_transition='ship' and v_transfer.status='shipped')
    or (p_transition='receive' and v_transfer.status='received')
    or (p_transition='reconcile' and v_transfer.status='reconciled')
    or (p_transition='cancel' and v_transfer.status='cancelled') then
    return jsonb_build_object('id',p_transfer_id,'status',v_transfer.status,'replayed',true);
  end if;

  if p_transition='approve' then
    if v_transfer.status <> 'draft' then raise exception 'stock_transfer_not_draft'; end if;
    update public.stock_transfers set status='approved',updated_at=now() where id=p_transfer_id;
    return jsonb_build_object('id',p_transfer_id,'status','approved');
  elsif p_transition='pick' then
    if v_transfer.status <> 'approved' then raise exception 'stock_transfer_not_approved'; end if;
    update public.stock_transfers set status='picked',updated_at=now() where id=p_transfer_id;
    return jsonb_build_object('id',p_transfer_id,'status','picked');
  elsif p_transition='ship' then
    if v_transfer.status <> 'picked' then raise exception 'stock_transfer_not_picked'; end if;
    for v_item in select inventory_item_id,quantity from public.stock_transfer_items where transfer_id=p_transfer_id order by inventory_item_id loop
      insert into public.branch_inventory(branch_id,inventory_item_id,on_hand)
      values(v_transfer.source_branch_id,v_item.inventory_item_id,0)
      on conflict(branch_id,inventory_item_id) do nothing;
      select on_hand into v_balance from public.branch_inventory
      where branch_id=v_transfer.source_branch_id and inventory_item_id=v_item.inventory_item_id for update;
      if v_balance < v_item.quantity then raise exception 'insufficient_stock_for_transfer'; end if;
      update public.branch_inventory set on_hand=on_hand-v_item.quantity,updated_at=now()
      where branch_id=v_transfer.source_branch_id and inventory_item_id=v_item.inventory_item_id;
      insert into public.stock_movements(branch_id,inventory_item_id,movement_type,quantity,reference_type,reference_id,notes,created_by)
      values(v_transfer.source_branch_id,v_item.inventory_item_id,'transfer_out',v_item.quantity,'stock_transfer',p_transfer_id,'Transfer '||v_transfer.transfer_number,p_actor_user_id);
      v_count := v_count+1;
    end loop;
    if v_count=0 then raise exception 'empty_stock_transfer'; end if;
    update public.stock_transfers set status='shipped',shipped_by=p_actor_user_id,shipped_at=now(),updated_at=now() where id=p_transfer_id;
    return jsonb_build_object('id',p_transfer_id,'status','shipped');
  elsif p_transition='receive' then
    if v_transfer.status <> 'shipped' then raise exception 'stock_transfer_not_shipped'; end if;
    for v_item in select inventory_item_id,quantity from public.stock_transfer_items where transfer_id=p_transfer_id order by inventory_item_id loop
      insert into public.branch_inventory(branch_id,inventory_item_id,on_hand)
      values(v_transfer.destination_branch_id,v_item.inventory_item_id,0)
      on conflict(branch_id,inventory_item_id) do nothing;
      perform 1 from public.branch_inventory
      where branch_id=v_transfer.destination_branch_id and inventory_item_id=v_item.inventory_item_id for update;
      update public.branch_inventory set on_hand=on_hand+v_item.quantity,updated_at=now()
      where branch_id=v_transfer.destination_branch_id and inventory_item_id=v_item.inventory_item_id;
      insert into public.stock_movements(branch_id,inventory_item_id,movement_type,quantity,reference_type,reference_id,notes,created_by)
      values(v_transfer.destination_branch_id,v_item.inventory_item_id,'transfer_in',v_item.quantity,'stock_transfer',p_transfer_id,'Transfer '||v_transfer.transfer_number,p_actor_user_id);
    end loop;
    update public.stock_transfers set status='received',received_by=p_actor_user_id,received_at=now(),updated_at=now() where id=p_transfer_id;
    return jsonb_build_object('id',p_transfer_id,'status','received');
  elsif p_transition='reconcile' then
    if v_transfer.status <> 'received' then raise exception 'stock_transfer_not_received'; end if;
    if exists (
      select 1 from public.stock_transfer_items i
      where i.transfer_id=p_transfer_id
        and (not exists(select 1 from public.stock_movements m where m.reference_type='stock_transfer' and m.reference_id=p_transfer_id and m.branch_id=v_transfer.source_branch_id and m.inventory_item_id=i.inventory_item_id and m.movement_type='transfer_out')
          or not exists(select 1 from public.stock_movements m where m.reference_type='stock_transfer' and m.reference_id=p_transfer_id and m.branch_id=v_transfer.destination_branch_id and m.inventory_item_id=i.inventory_item_id and m.movement_type='transfer_in'))
    ) then raise exception 'stock_transfer_ledger_incomplete'; end if;
    update public.stock_transfers set status='reconciled',updated_at=now() where id=p_transfer_id;
    return jsonb_build_object('id',p_transfer_id,'status','reconciled');
  else
    if v_transfer.status not in ('draft','approved','picked') then raise exception 'only_unshipped_transfer_can_be_cancelled'; end if;
    update public.stock_transfers set status='cancelled',updated_at=now() where id=p_transfer_id;
    return jsonb_build_object('id',p_transfer_id,'status','cancelled');
  end if;
end;
$function$

revoke all on function public.erp_transition_stock_transfer(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.erp_transition_stock_transfer(uuid,uuid,text) to service_role;
