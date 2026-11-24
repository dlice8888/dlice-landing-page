begin;

create or replace function public.dlice_update_admin_permissions_audited(
  p_actor_user_id uuid,
  p_target_user_id uuid,
  p_permissions jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_previous_permissions jsonb;
  v_next_permissions jsonb;
  v_target_role text;
begin
  if (auth.jwt() ->> 'role') IS DISTINCT FROM 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;

  if p_actor_user_id is null or p_target_user_id is null
    or not exists (select 1 from auth.users where id = p_actor_user_id) then
    raise exception 'valid_actor_and_target_required' using errcode = '22023';
  end if;

  if jsonb_typeof(p_permissions) is distinct from 'array'
    or jsonb_array_length(p_permissions) > 13
    or exists (
      select 1
      from jsonb_array_elements(p_permissions) as item(value)
      where jsonb_typeof(item.value) is distinct from 'string'
        or item.value #>> '{}' not in (
          'orders', 'catalog', 'finance', 'reports', 'settings', 'staff',
          'branches', 'inventory', 'procurement', 'pos', 'audit', 'hr', 'production'
        )
    ) then
    raise exception 'invalid_permissions' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(permission order by permission), '[]'::jsonb)
  into v_next_permissions
  from (
    select distinct value as permission
    from jsonb_array_elements_text(p_permissions) as permissions(value)
  ) normalized;

  select role, permissions
  into v_target_role, v_previous_permissions
  from public.admin_profiles
  where user_id = p_target_user_id
  for update;

  if not found then
    raise exception 'staff_profile_not_found' using errcode = 'P0002';
  end if;

  if v_target_role = 'owner' then
    raise exception 'owner_permissions_are_not_editable' using errcode = '55000';
  end if;

  if coalesce(v_previous_permissions, '[]'::jsonb) = v_next_permissions then
    return jsonb_build_object('ok', true, 'changed', false, 'permissions', v_next_permissions);
  end if;

  update public.admin_profiles
  set permissions = v_next_permissions,
      updated_at = now()
  where user_id = p_target_user_id;

  insert into public.admin_audit_logs (
    actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_actor_user_id,
    'update_admin_permissions',
    'admin_profile',
    p_target_user_id::text,
    jsonb_build_object(
      'previous_permissions', coalesce(v_previous_permissions, '[]'::jsonb),
      'new_permissions', v_next_permissions
    )
  );

  return jsonb_build_object('ok', true, 'changed', true, 'permissions', v_next_permissions);
end;
$function$;

revoke all on function public.dlice_update_admin_permissions_audited(uuid, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.dlice_update_admin_permissions_audited(uuid, uuid, jsonb)
  to service_role;

commit;
