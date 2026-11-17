-- Atomic privileged operations for tenant bootstrap, warehouse creation and PO transitions.
-- SECURITY INVOKER: the caller must be service_role; no client role can execute these RPCs.
create or replace function public.platform_bootstrap_tenant_owner(
  p_actor_user_id uuid,
  p_target_user_id uuid,
  p_tenant_id uuid,
  p_branch_id uuid
) returns jsonb
language plpgsql
security invoker
set search_path = public, auth, pg_temp
as $$
declare
  v_membership public.tenant_memberships%rowtype;
begin
  if p_tenant_id <> '00000000-0000-4000-8000-000000000002'::uuid
     or p_branch_id <> '90000000-0000-4000-8000-000000000004'::uuid
     or p_actor_user_id is null or p_target_user_id is null
     or p_actor_user_id = p_target_user_id then
    raise exception 'invalid_staging_bootstrap_scope' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.tenants t
    where t.id = p_tenant_id and t.slug = 'dlice-qa-isolation-b' and t.status = 'active'
  ) or not exists (
    select 1 from public.branches b
    where b.id = p_branch_id and b.tenant_id = p_tenant_id and b.status = 'active'
  ) then
    raise exception 'staging_tenant_or_branch_not_active' using errcode = '23514';
  end if;

  if not exists (
    select 1 from public.admin_profiles ap
    join auth.users u on u.id = ap.user_id
    where ap.user_id = p_target_user_id
      and ap.role = 'sales_admin' and ap.is_active = true
      and u.email_confirmed_at is not null
      and coalesce((u.raw_app_meta_data->>'platform_owner')::boolean, false) = false
  ) then
    raise exception 'target_staff_identity_not_eligible' using errcode = '23514';
  end if;

  if exists (select 1 from public.tenant_memberships tm where tm.user_id = p_target_user_id) then
    raise exception 'target_already_has_tenant_membership' using errcode = '23505';
  end if;

  insert into public.tenant_memberships(tenant_id,user_id,role,permissions,status)
  values (p_tenant_id,p_target_user_id,'tenant_owner','["branches","inventory","procurement"]'::jsonb,'active')
  returning * into v_membership;

  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values (
    p_actor_user_id,'platform_bootstrap_tenant_owner','tenant_membership',v_membership.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,
      'target_user_id',p_target_user_id,'assigned_role','tenant_owner',
      'permissions_scope','tenant_memberships','bootstrap_scope','staging_tenant_b_only')
  );

  return jsonb_build_object('membership',to_jsonb(v_membership),'audit_recorded',true);
end;
$$;

create or replace function public.erp_create_warehouse_with_audit(
  p_actor_user_id uuid,
  p_branch_id uuid,
  p_code text,
  p_name text,
  p_warehouse_type text,
  p_is_default boolean
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_warehouse public.warehouses%rowtype;
begin
  select b.tenant_id into v_tenant_id
  from public.branches b
  where b.id = p_branch_id and b.status = 'active';
  if v_tenant_id is null then raise exception 'active_branch_not_found' using errcode = '23503'; end if;

  if not exists (
    select 1 from public.tenant_memberships tm
    where tm.tenant_id = v_tenant_id and tm.user_id = p_actor_user_id
      and tm.status = 'active' and tm.role in ('tenant_owner','tenant_admin')
  ) then
    raise exception 'tenant_owner_or_admin_required' using errcode = '42501';
  end if;

  insert into public.warehouses(tenant_id,branch_id,code,name,warehouse_type,is_default)
  values(v_tenant_id,p_branch_id,p_code,p_name,p_warehouse_type,coalesce(p_is_default,false))
  returning * into v_warehouse;

  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'erp_warehouse_created','warehouse',v_warehouse.id::text,
    jsonb_build_object('tenant_id',v_tenant_id,'branch_id',p_branch_id,'code',p_code,
      'warehouse_type',p_warehouse_type,'is_default',v_warehouse.is_default));

  return jsonb_build_object('warehouse',to_jsonb(v_warehouse),'audit_recorded',true);
end;
$$;

create or replace function public.erp_transition_purchase_order_with_audit(
  p_actor_user_id uuid,
  p_purchase_order_id uuid,
  p_next_status text,
  p_platform_owner boolean default false
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_old public.purchase_orders%rowtype;
  v_new public.purchase_orders%rowtype;
  v_tenant_id uuid;
  v_valid boolean := false;
begin
  select po.* into v_old from public.purchase_orders po
  where po.id = p_purchase_order_id for update;
  if not found then raise exception 'purchase_order_not_found' using errcode = 'P0002'; end if;

  select b.tenant_id into v_tenant_id from public.branches b
  where b.id = v_old.branch_id and b.status = 'active';
  if v_tenant_id is null then raise exception 'purchase_order_branch_not_active' using errcode = '23503'; end if;

  if not exists (
    select 1 from public.tenant_memberships tm
    where tm.tenant_id = v_tenant_id and tm.user_id = p_actor_user_id and tm.status = 'active'
  ) and not coalesce(p_platform_owner,false) then
    raise exception 'active_tenant_membership_required' using errcode = '42501';
  end if;

  if p_next_status = 'approved' then
    if not coalesce(p_platform_owner,false) and not exists (
      select 1 from public.tenant_memberships tm
      where tm.tenant_id = v_tenant_id and tm.user_id = p_actor_user_id
        and tm.status = 'active' and tm.role in ('tenant_owner','tenant_admin')
    ) then raise exception 'tenant_owner_or_admin_required_for_approval' using errcode = '42501'; end if;
    if v_old.requested_by = p_actor_user_id then raise exception 'maker_checker_violation' using errcode = '42501'; end if;
  end if;

  v_valid := (v_old.status = 'draft' and p_next_status in ('submitted','cancelled'))
    or (v_old.status = 'submitted' and p_next_status in ('approved','cancelled'))
    or (v_old.status = 'approved' and p_next_status in ('ordered','cancelled'));
  if not v_valid then raise exception 'invalid_purchase_order_transition' using errcode = '23514'; end if;

  update public.purchase_orders
  set status = p_next_status,
      approved_by = case when p_next_status = 'approved' then p_actor_user_id else approved_by end,
      updated_at = now()
  where id = p_purchase_order_id and status = v_old.status
  returning * into v_new;
  if not found then raise exception 'purchase_order_status_race' using errcode = '40001'; end if;

  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'erp_purchase_order_' || p_next_status,'purchase_order',p_purchase_order_id::text,
    jsonb_build_object('previous_status',v_old.status,'next_status',p_next_status,'tenant_id',v_tenant_id));

  return jsonb_build_object('purchase_order',to_jsonb(v_new),'audit_recorded',true);
end;
$$;

revoke all on function public.platform_bootstrap_tenant_owner(uuid,uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function public.erp_create_warehouse_with_audit(uuid,uuid,text,text,text,boolean) from public, anon, authenticated;
revoke all on function public.erp_transition_purchase_order_with_audit(uuid,uuid,text,boolean) from public, anon, authenticated;
grant execute on function public.platform_bootstrap_tenant_owner(uuid,uuid,uuid,uuid) to service_role;
grant execute on function public.erp_create_warehouse_with_audit(uuid,uuid,text,text,text,boolean) to service_role;
grant execute on function public.erp_transition_purchase_order_with_audit(uuid,uuid,text,boolean) to service_role;


create or replace function public.erp_create_purchase_order_with_audit(
  p_actor_user_id uuid,
  p_branch_id uuid,
  p_po_number text,
  p_subtotal_idr bigint,
  p_notes text,
  p_items jsonb,
  p_platform_owner boolean default false
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_po public.purchase_orders%rowtype;
  v_item jsonb;
  v_inventory_item_id uuid;
  v_item_name text;
  v_quantity numeric;
  v_unit_cost bigint;
  v_line_total bigint;
  v_sum bigint := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1
     or jsonb_array_length(p_items) > 100 then
    raise exception 'invalid_purchase_order_items' using errcode = '22023';
  end if;
  if p_po_number is null or length(trim(p_po_number)) < 6 or p_subtotal_idr < 0 then
    raise exception 'invalid_purchase_order_header' using errcode = '22023';
  end if;

  select b.tenant_id into v_tenant_id
  from public.branches b where b.id = p_branch_id and b.status = 'active';
  if v_tenant_id is null then raise exception 'active_branch_not_found' using errcode = '23503'; end if;

  if not coalesce(p_platform_owner,false) and not exists (
    select 1 from public.tenant_memberships tm
    where tm.tenant_id = v_tenant_id and tm.user_id = p_actor_user_id
      and tm.status = 'active'
      and (tm.role in ('tenant_owner','tenant_admin') or tm.permissions ? 'procurement')
  ) then
    raise exception 'tenant_procurement_permission_required' using errcode = '42501';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_inventory_item_id := (v_item->>'inventory_item_id')::uuid;
    v_quantity := (v_item->>'quantity')::numeric;
    v_unit_cost := (v_item->>'unit_cost_idr')::bigint;
    if v_quantity is null or v_quantity <= 0 or v_quantity > 100000
       or v_unit_cost is null or v_unit_cost < 0 then
      raise exception 'invalid_purchase_order_line' using errcode = '22023';
    end if;
    select ii.name into v_item_name from public.inventory_items ii
    where ii.id = v_inventory_item_id and ii.is_active = true;
    if v_item_name is null then raise exception 'active_inventory_item_not_found' using errcode = '23503'; end if;
    v_line_total := round(v_quantity * v_unit_cost)::bigint;
    v_sum := v_sum + v_line_total;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'inventory_item_id',v_inventory_item_id,'item_name_snapshot',v_item_name,
      'quantity',v_quantity,'unit_cost_idr',v_unit_cost,'line_total_idr',v_line_total
    ));
  end loop;

  if v_sum <> p_subtotal_idr then raise exception 'purchase_order_subtotal_mismatch' using errcode = '22023'; end if;

  insert into public.purchase_orders(po_number,branch_id,status,subtotal_idr,requested_by,notes)
  values(p_po_number,p_branch_id,'draft',p_subtotal_idr,p_actor_user_id,nullif(trim(p_notes),''))
  returning * into v_po;

  -- Persist each validated line against the new header inside the same transaction.
  for v_item in select value from jsonb_array_elements(v_items)
  loop
    insert into public.purchase_order_items(
      purchase_order_id,inventory_item_id,item_name_snapshot,quantity,unit_cost_idr,line_total_idr
    ) values (
      v_po.id,(v_item->>'inventory_item_id')::uuid,v_item->>'item_name_snapshot',
      (v_item->>'quantity')::numeric,(v_item->>'unit_cost_idr')::bigint,
      (v_item->>'line_total_idr')::bigint
    );
  end loop;
  -- Rebuild the line array from persisted rows, scoped to this PO.
  select coalesce(jsonb_agg(to_jsonb(poi) - 'purchase_order_id' order by poi.id),'[]'::jsonb)
  into v_items from public.purchase_order_items poi where poi.purchase_order_id = v_po.id;

  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'erp_purchase_order_created','purchase_order',v_po.id::text,
    jsonb_build_object('po_number',v_po.po_number,'subtotal_idr',v_po.subtotal_idr,'tenant_id',v_tenant_id,'line_count',jsonb_array_length(p_items)));

  return jsonb_build_object('purchase_order',to_jsonb(v_po),'items',v_items,'audit_recorded',true);
end;
$$;

revoke all on function public.erp_create_purchase_order_with_audit(uuid,uuid,text,bigint,text,jsonb,boolean) from public, anon, authenticated;
grant execute on function public.erp_create_purchase_order_with_audit(uuid,uuid,text,bigint,text,jsonb,boolean) to service_role;
