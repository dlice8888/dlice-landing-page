BEGIN;

CREATE OR REPLACE FUNCTION public.dlice_create_admin_profile_audited(
  p_actor_user_id uuid,
  p_target_user_id uuid,
  p_username text,
  p_display_name text,
  p_permissions jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_next_permissions jsonb;
  v_existing public.admin_profiles%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;
  IF p_actor_user_id IS NULL OR p_target_user_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id=p_actor_user_id)
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id=p_target_user_id)
     OR p_username IS NULL OR length(p_username) < 3 OR length(p_username) > 32
     OR p_username !~ '^[a-z0-9._-]+$'
     OR p_display_name IS NULL OR length(trim(p_display_name)) < 1 OR length(p_display_name) > 120
  THEN
    RAISE EXCEPTION 'invalid_admin_profile_details' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_permissions) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_permissions) > 13
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(p_permissions) AS item(value)
       WHERE jsonb_typeof(item.value) IS DISTINCT FROM 'string'
         OR item.value #>> '{}' NOT IN (
           'orders','catalog','finance','reports','settings','staff','branches',
           'inventory','procurement','pos','audit','hr','production'
         )
     )
  THEN
    RAISE EXCEPTION 'invalid_permissions' USING ERRCODE = '22023';
  END IF;
  SELECT coalesce(jsonb_agg(permission ORDER BY permission),'[]'::jsonb)
    INTO v_next_permissions
  FROM (
    SELECT DISTINCT value AS permission
    FROM jsonb_array_elements_text(p_permissions) AS permissions(value)
  ) normalized;

  SELECT * INTO v_existing
  FROM public.admin_profiles
  WHERE user_id=p_target_user_id
  FOR UPDATE;

  IF FOUND THEN
    IF v_existing.username=p_username
       AND v_existing.role='sales_admin'
       AND v_existing.display_name=p_display_name
       AND v_existing.is_active IS TRUE
       AND coalesce(v_existing.permissions,'[]'::jsonb)=v_next_permissions
    THEN
      RETURN jsonb_build_object('ok',true,'changed',false,'user_id',p_target_user_id);
    END IF;
    RAISE EXCEPTION 'admin_profile_conflict' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.admin_profiles
    (user_id,username,role,display_name,is_active,permissions,created_at,updated_at)
  VALUES
    (p_target_user_id,p_username,'sales_admin',p_display_name,true,v_next_permissions,now(),now());

  INSERT INTO public.admin_audit_logs
    (actor_user_id,action,entity_type,entity_id,metadata)
  VALUES
    (p_actor_user_id,'create_admin_account','admin_profile',p_target_user_id::text,
     jsonb_build_object('before',NULL,'after',jsonb_build_object(
       'username',p_username,'role','sales_admin','display_name',p_display_name,
       'is_active',true,'permissions',v_next_permissions)));

  RETURN jsonb_build_object('ok',true,'changed',true,'user_id',p_target_user_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.dlice_update_admin_profile_role_audited(
  p_actor_user_id uuid,
  p_target_user_id uuid,
  p_next_role text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_previous_role text;
  v_assignment_count integer := 0;
  v_valid_assignment_count integer := 0;
  v_has_owner_membership boolean := false;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;
  IF p_actor_user_id IS NULL OR p_target_user_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id=p_actor_user_id)
     OR p_next_role IS NULL OR p_next_role NOT IN ('sales_admin','branch_worker')
  THEN
    RAISE EXCEPTION 'invalid_admin_role_change' USING ERRCODE = '22023';
  END IF;

  SELECT role INTO v_previous_role
  FROM public.admin_profiles
  WHERE user_id=p_target_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_profile_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_previous_role='owner' THEN
    RAISE EXCEPTION 'owner_role_is_not_editable' USING ERRCODE = '55000';
  END IF;
  IF v_previous_role=p_next_role THEN
    RETURN jsonb_build_object('ok',true,'changed',false,'profile_role',p_next_role);
  END IF;

  IF p_next_role='branch_worker' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.tenant_memberships
      WHERE user_id=p_target_user_id AND status='active'
        AND role IN ('tenant_owner','tenant_admin')
    ) INTO v_has_owner_membership;
    IF v_has_owner_membership THEN
      RAISE EXCEPTION 'tenant_admin_cannot_be_branch_worker' USING ERRCODE = '23514';
    END IF;

    SELECT count(*),
           count(*) FILTER (WHERE EXISTS (
             SELECT 1 FROM public.tenant_memberships tm
             WHERE tm.user_id=p_target_user_id
               AND tm.tenant_id=b.tenant_id
               AND tm.status='active'
           ))
      INTO v_assignment_count,v_valid_assignment_count
    FROM public.branch_assignments ba
    JOIN public.branches b ON b.id=ba.branch_id
    WHERE ba.user_id=p_target_user_id
      AND ba.employment_status='active'
      AND ba.starts_on <= current_date
      AND (ba.ends_on IS NULL OR ba.ends_on >= current_date);

    IF v_assignment_count=0 THEN
      RAISE EXCEPTION 'branch_assignment_required' USING ERRCODE = '23514';
    END IF;
    IF v_valid_assignment_count <> v_assignment_count THEN
      RAISE EXCEPTION 'cross_tenant_branch_assignment' USING ERRCODE = '23514';
    END IF;
  END IF;

  UPDATE public.admin_profiles
  SET role=p_next_role,updated_at=now()
  WHERE user_id=p_target_user_id;

  INSERT INTO public.admin_audit_logs
    (actor_user_id,action,entity_type,entity_id,metadata)
  VALUES
    (p_actor_user_id,'set_staff_profile_role','admin_profile',p_target_user_id::text,
     jsonb_build_object('previous_role',v_previous_role,'new_role',p_next_role));

  RETURN jsonb_build_object('ok',true,'changed',true,'profile_role',p_next_role);
END;
$function$;

CREATE OR REPLACE FUNCTION public.dlice_set_admin_profile_active_audited(
  p_actor_user_id uuid,
  p_target_user_id uuid,
  p_is_active boolean
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_previous_active boolean;
  v_target_role text;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;
  IF p_actor_user_id IS NULL OR p_target_user_id IS NULL OR p_is_active IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id=p_actor_user_id)
  THEN
    RAISE EXCEPTION 'invalid_admin_active_change' USING ERRCODE = '22023';
  END IF;

  SELECT role,is_active INTO v_target_role,v_previous_active
  FROM public.admin_profiles
  WHERE user_id=p_target_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_profile_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_target_role='owner' THEN
    RAISE EXCEPTION 'owner_active_state_is_not_editable' USING ERRCODE = '55000';
  END IF;
  IF v_previous_active=p_is_active THEN
    RETURN jsonb_build_object('ok',true,'changed',false,'is_active',p_is_active);
  END IF;

  UPDATE public.admin_profiles
  SET is_active=p_is_active,updated_at=now()
  WHERE user_id=p_target_user_id;

  INSERT INTO public.admin_audit_logs
    (actor_user_id,action,entity_type,entity_id,metadata)
  VALUES
    (p_actor_user_id,'set_admin_active_status','admin_profile',p_target_user_id::text,
     jsonb_build_object('previous_is_active',v_previous_active,'new_is_active',p_is_active));

  RETURN jsonb_build_object('ok',true,'changed',true,'is_active',p_is_active);
END;
$function$;

CREATE OR REPLACE FUNCTION public.dlice_begin_admin_password_reset_audit(
  p_actor_user_id uuid,
  p_target_user_id uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_target_role text;
  v_audit_id uuid;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;
  IF p_actor_user_id IS NULL OR p_target_user_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id=p_actor_user_id)
  THEN
    RAISE EXCEPTION 'valid_actor_and_target_required' USING ERRCODE = '22023';
  END IF;

  SELECT role INTO v_target_role
  FROM public.admin_profiles
  WHERE user_id=p_target_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'staff_profile_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_target_role='owner' THEN
    RAISE EXCEPTION 'owner_password_is_not_editable' USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.admin_audit_logs
    (actor_user_id,action,entity_type,entity_id,metadata)
  VALUES
    (p_actor_user_id,'admin_password_reset_started','admin_profile',p_target_user_id::text,
     jsonb_build_object('status','pending','password_reset',true))
  RETURNING id INTO v_audit_id;

  RETURN v_audit_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dlice_finish_admin_password_reset_audit(
  p_actor_user_id uuid,
  p_audit_log_id uuid,
  p_succeeded boolean,
  p_error_code text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_event public.admin_audit_logs%ROWTYPE;
  v_next_status text;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;
  IF p_actor_user_id IS NULL OR p_audit_log_id IS NULL OR p_succeeded IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id=p_actor_user_id)
  THEN
    RAISE EXCEPTION 'invalid_password_reset_audit_details' USING ERRCODE = '22023';
  END IF;
  IF p_error_code IS NOT NULL AND (
    length(p_error_code)>80 OR p_error_code ~ '[^A-Za-z0-9_.-]'
  ) THEN
    RAISE EXCEPTION 'invalid_password_reset_error_code' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_event
  FROM public.admin_audit_logs
  WHERE id=p_audit_log_id
    AND actor_user_id=p_actor_user_id
    AND entity_type='admin_profile'
    AND action IN ('admin_password_reset_started','reset_admin_password','reset_admin_password_failed')
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'password_reset_audit_event_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_next_status := CASE WHEN p_succeeded THEN 'succeeded' ELSE 'failed' END;
  IF v_event.metadata->>'status' IS DISTINCT FROM 'pending' THEN
    IF v_event.metadata->>'status'=v_next_status THEN
      RETURN jsonb_build_object('ok',true,'changed',false,'status',v_next_status,'audit_id',v_event.id);
    END IF;
    RAISE EXCEPTION 'password_reset_audit_already_finalized' USING ERRCODE = '55000';
  END IF;

  UPDATE public.admin_audit_logs
  SET action=CASE WHEN p_succeeded THEN 'reset_admin_password' ELSE 'reset_admin_password_failed' END,
      metadata=metadata || jsonb_build_object(
        'status',v_next_status,
        'password_reset',p_succeeded,
        'error_code',CASE WHEN p_succeeded THEN NULL ELSE coalesce(p_error_code,'auth_admin_update_failed') END
      )
  WHERE id=p_audit_log_id;

  RETURN jsonb_build_object('ok',true,'changed',true,'status',v_next_status,'audit_id',p_audit_log_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.dlice_create_admin_profile_audited(uuid,uuid,text,text,jsonb)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.dlice_update_admin_profile_role_audited(uuid,uuid,text)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.dlice_set_admin_profile_active_audited(uuid,uuid,boolean)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_create_admin_profile_audited(uuid,uuid,text,text,jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.dlice_update_admin_profile_role_audited(uuid,uuid,text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.dlice_set_admin_profile_active_audited(uuid,uuid,boolean)
  TO service_role;

REVOKE ALL ON FUNCTION public.dlice_begin_admin_password_reset_audit(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.dlice_finish_admin_password_reset_audit(uuid,uuid,boolean,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_begin_admin_password_reset_audit(uuid,uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.dlice_finish_admin_password_reset_audit(uuid,uuid,boolean,text)
  TO service_role;


COMMIT;
