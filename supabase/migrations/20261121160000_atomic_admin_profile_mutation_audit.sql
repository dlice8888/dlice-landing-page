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

CREATE OR REPLACE FUNCTION public.dlice_create_tenant_invite_audited(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_email text,
  p_role text,
  p_token_hash text,
  p_expires_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_actor_role text;
  v_tenant_status text;
  v_invite public.tenant_invites%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL THEN
    RAISE EXCEPTION 'invalid_tenant_invite_details' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=p_actor_user_id) THEN
    RAISE EXCEPTION 'invalid_tenant_invite_details' USING ERRCODE = '22023';
  END IF;
  IF p_email IS NULL OR length(p_email)<3 OR length(p_email)>254 THEN
    RAISE EXCEPTION 'invalid_tenant_invite_details' USING ERRCODE = '22023';
  END IF;
  IF NOT (p_email ~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$') THEN
    RAISE EXCEPTION 'invalid_tenant_invite_details' USING ERRCODE = '22023';
  END IF;
  IF p_role IS NULL THEN
    RAISE EXCEPTION 'invalid_tenant_invite_details' USING ERRCODE = '22023';
  END IF;
  IF NOT (p_role = ANY (ARRAY['tenant_admin','branch_manager','cashier','inventory','production','finance','viewer','tenant_member']::text[])) THEN
    RAISE EXCEPTION 'invalid_tenant_invite_details' USING ERRCODE = '22023';
  END IF;
  IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_tenant_invite_details' USING ERRCODE = '22023';
  END IF;
  IF p_expires_at IS NULL OR p_expires_at <= now() OR p_expires_at > now() + interval '7 days' THEN
    RAISE EXCEPTION 'invalid_tenant_invite_details' USING ERRCODE = '22023';
  END IF;

  SELECT status INTO v_tenant_status
  FROM public.tenants
  WHERE id=p_tenant_id
  FOR SHARE;
  IF NOT FOUND OR v_tenant_status NOT IN ('active','trial') THEN
    RAISE EXCEPTION 'tenant_not_active_for_invites' USING ERRCODE = '55000';
  END IF;

  SELECT role INTO v_actor_role
  FROM public.tenant_memberships
  WHERE tenant_id=p_tenant_id AND user_id=p_actor_user_id AND status='active'
  FOR UPDATE;
  IF NOT FOUND OR v_actor_role NOT IN ('tenant_owner','tenant_admin') THEN
    RAISE EXCEPTION 'tenant_owner_or_admin_required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_invite
  FROM public.tenant_invites
  WHERE token_hash=p_token_hash
  FOR UPDATE;
  IF FOUND THEN
    IF v_invite.invited_by=p_actor_user_id
       AND v_invite.tenant_id=p_tenant_id
       AND v_invite.email=lower(p_email)
       AND v_invite.role=p_role
       AND v_invite.expires_at=p_expires_at
    THEN
      RETURN jsonb_build_object('ok',true,'replayed',true,'invite',jsonb_build_object(
        'id',v_invite.id,'tenant_id',v_invite.tenant_id,'email',v_invite.email,
        'role',v_invite.role,'status',v_invite.status,'expires_at',v_invite.expires_at));
    END IF;
    RAISE EXCEPTION 'tenant_invite_token_conflict' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.tenant_invites
    (tenant_id,email,role,token_hash,invited_by,expires_at,status)
  VALUES
    (p_tenant_id,lower(p_email),p_role,p_token_hash,p_actor_user_id,p_expires_at,'pending')
  RETURNING * INTO v_invite;

  INSERT INTO public.admin_audit_logs
    (actor_user_id,action,entity_type,entity_id,metadata)
  VALUES
    (p_actor_user_id,'tenant_member_invited','tenant_invite',v_invite.id::text,
     jsonb_build_object('tenant_id',p_tenant_id,'email',lower(p_email),'role',p_role,'expires_at',p_expires_at));

  RETURN jsonb_build_object('ok',true,'replayed',false,'invite',jsonb_build_object(
    'id',v_invite.id,'tenant_id',v_invite.tenant_id,'email',v_invite.email,
    'role',v_invite.role,'status',v_invite.status,'expires_at',v_invite.expires_at));
END;
$function$;

CREATE OR REPLACE FUNCTION public.dlice_accept_tenant_invite_atomic(
  p_actor_user_id uuid,
  p_token_hash text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_actor_email text;
  v_invite public.tenant_invites%ROWTYPE;
  v_existing_role text;
  v_existing_status text;
  v_tenant_status text;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;
  IF p_actor_user_id IS NULL OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_tenant_invite_token' USING ERRCODE = '22023';
  END IF;
  SELECT lower(email) INTO v_actor_email FROM auth.users WHERE id=p_actor_user_id;
  IF NOT FOUND OR v_actor_email IS NULL THEN
    RAISE EXCEPTION 'auth_user_email_required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_invite
  FROM public.tenant_invites
  WHERE token_hash=p_token_hash
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant_invite_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_invite.status='accepted' AND v_invite.accepted_by=p_actor_user_id THEN
    IF EXISTS (
      SELECT 1 FROM public.tenant_memberships
      WHERE tenant_id=v_invite.tenant_id AND user_id=p_actor_user_id
        AND status='active' AND role=v_invite.role
    ) THEN
      RETURN jsonb_build_object('ok',true,'replayed',true,'invite',jsonb_build_object(
        'id',v_invite.id,'tenant_id',v_invite.tenant_id,'status',v_invite.status,'role',v_invite.role));
    END IF;
    RAISE EXCEPTION 'accepted_invite_membership_mismatch' USING ERRCODE = '55000';
  END IF;

  IF v_invite.status <> 'pending' OR v_invite.expires_at <= now() THEN
    RAISE EXCEPTION 'tenant_invite_expired_or_inactive' USING ERRCODE = '55000';
  END IF;
  IF v_invite.email <> v_actor_email THEN
    RAISE EXCEPTION 'tenant_invite_email_mismatch' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_tenant_status
  FROM public.tenants WHERE id=v_invite.tenant_id FOR SHARE;
  IF NOT FOUND OR v_tenant_status NOT IN ('active','trial') THEN
    RAISE EXCEPTION 'tenant_not_active_for_invites' USING ERRCODE = '55000';
  END IF;

  SELECT role,status INTO v_existing_role,v_existing_status
  FROM public.tenant_memberships
  WHERE tenant_id=v_invite.tenant_id AND user_id=p_actor_user_id
  FOR UPDATE;
  IF FOUND AND v_existing_status='active' THEN
    RAISE EXCEPTION 'tenant_membership_already_active' USING ERRCODE = '23505';
  END IF;
  IF FOUND AND v_existing_role IN ('tenant_owner','tenant_admin') THEN
    RAISE EXCEPTION 'tenant_admin_membership_cannot_be_replaced_by_invite' USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.tenant_memberships
    (tenant_id,user_id,role,permissions,status,created_at,updated_at)
  VALUES
    (v_invite.tenant_id,p_actor_user_id,v_invite.role,'[]'::jsonb,'active',now(),now())
  ON CONFLICT (tenant_id,user_id) DO UPDATE
    SET role=EXCLUDED.role,permissions='[]'::jsonb,status='active',updated_at=now();

  UPDATE public.tenant_invites
  SET status='accepted',accepted_by=p_actor_user_id,accepted_at=now()
  WHERE id=v_invite.id AND status='pending';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant_invite_already_processed' USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.admin_audit_logs
    (actor_user_id,action,entity_type,entity_id,metadata)
  VALUES
    (p_actor_user_id,'tenant_invite_accepted','tenant_invite',v_invite.id::text,
     jsonb_build_object('tenant_id',v_invite.tenant_id,'role',v_invite.role));

  RETURN jsonb_build_object('ok',true,'replayed',false,'invite',jsonb_build_object(
    'id',v_invite.id,'tenant_id',v_invite.tenant_id,'status','accepted','role',v_invite.role));
END;
$function$;

REVOKE ALL ON FUNCTION public.dlice_create_tenant_invite_audited(uuid,uuid,text,text,text,timestamptz)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.dlice_accept_tenant_invite_atomic(uuid,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_create_tenant_invite_audited(uuid,uuid,text,text,text,timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.dlice_accept_tenant_invite_atomic(uuid,text)
  TO service_role;

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

COMMIT;
