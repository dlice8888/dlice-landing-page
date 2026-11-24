CREATE OR REPLACE FUNCTION public.dlice_create_tenant_invite_atomic(
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
AS $$
DECLARE
  v_invite public.tenant_invites%ROWTYPE;
  v_tenant_status text;
  v_actor_role text;
BEGIN
  IF (auth.jwt() ->> 'role') IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL OR p_email IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_actor_user_id)
  THEN
    RAISE EXCEPTION 'invalid_tenant_invite' USING ERRCODE = '22023';
  END IF;
  IF length(trim(p_email)) NOT BETWEEN 3 AND 254
     OR trim(p_email) !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$'
  THEN
    RAISE EXCEPTION 'invalid_tenant_invite' USING ERRCODE = '22023';
  END IF;
  IF p_role IS NULL OR p_role NOT IN
     ('tenant_admin','branch_manager','cashier','inventory','production','finance','viewer','tenant_member')
  THEN
    RAISE EXCEPTION 'invalid_tenant_invite' USING ERRCODE = '22023';
  END IF;
  IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_tenant_invite' USING ERRCODE = '22023';
  END IF;
  IF p_expires_at IS NULL OR p_expires_at <= now()
     OR p_expires_at > now() + interval '7 days'
  THEN
    RAISE EXCEPTION 'invalid_tenant_invite' USING ERRCODE = '22023';
  END IF;

  SELECT status INTO v_tenant_status
  FROM public.tenants
  WHERE id = p_tenant_id
  FOR SHARE;
  IF NOT FOUND OR v_tenant_status NOT IN ('active','trial') THEN
    RAISE EXCEPTION 'tenant_not_active_for_invites' USING ERRCODE = '55000';
  END IF;

  SELECT role INTO v_actor_role
  FROM public.tenant_memberships
  WHERE tenant_id = p_tenant_id AND user_id = p_actor_user_id AND status = 'active'
  FOR UPDATE;
  IF NOT FOUND OR v_actor_role NOT IN ('tenant_owner','tenant_admin') THEN
    RAISE EXCEPTION 'tenant_invite_permission_denied' USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('tenant_invite_token:' || p_token_hash, 0));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'tenant_invite:' || p_tenant_id::text || ':' || lower(trim(p_email)), 0
  ));

  SELECT * INTO v_invite
  FROM public.tenant_invites
  WHERE token_hash = p_token_hash
  FOR UPDATE;
  IF FOUND THEN
    IF v_invite.invited_by = p_actor_user_id
       AND v_invite.tenant_id = p_tenant_id
       AND v_invite.email = lower(trim(p_email))
       AND v_invite.role = p_role
       AND v_invite.expires_at = p_expires_at
    THEN
      RETURN jsonb_build_object('ok',true,'replayed',true,'invite',jsonb_build_object(
        'id',v_invite.id,'tenant_id',v_invite.tenant_id,'email',v_invite.email,
        'role',v_invite.role,'status',v_invite.status,'expires_at',v_invite.expires_at
      ));
    END IF;
    RAISE EXCEPTION 'tenant_invite_token_conflict' USING ERRCODE = '23505';
  END IF;

  WITH expired AS (
    UPDATE public.tenant_invites
    SET status = 'expired'
    WHERE tenant_id = p_tenant_id
      AND email = lower(trim(p_email))
      AND status = 'pending'
      AND expires_at <= now()
    RETURNING id,tenant_id,email
  )
  INSERT INTO public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  SELECT p_actor_user_id,'tenant_invite_expired','tenant_invite',expired.id::text,
    jsonb_build_object('tenant_id',expired.tenant_id,'email',expired.email)
  FROM expired;

  IF EXISTS (
    SELECT 1 FROM public.tenant_invites
    WHERE tenant_id = p_tenant_id
      AND email = lower(trim(p_email))
      AND status = 'pending'
      AND expires_at > now()
  ) THEN
    RAISE EXCEPTION 'pending_tenant_invite_exists' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.tenant_invites
    (tenant_id,email,role,token_hash,invited_by,expires_at,status)
  VALUES
    (p_tenant_id,lower(trim(p_email)),p_role,p_token_hash,p_actor_user_id,p_expires_at,'pending')
  RETURNING * INTO v_invite;

  INSERT INTO public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  VALUES (p_actor_user_id,'tenant_member_invited','tenant_invite',v_invite.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'email',v_invite.email,'role',p_role,'expires_at',p_expires_at));

  RETURN jsonb_build_object('ok',true,'replayed',false,'invite',jsonb_build_object(
    'id',v_invite.id,'tenant_id',v_invite.tenant_id,'email',v_invite.email,
    'role',v_invite.role,'status',v_invite.status,'expires_at',v_invite.expires_at
  ));
END;
$$;

CREATE OR REPLACE FUNCTION public.dlice_accept_tenant_invite_atomic(
  p_actor_user_id uuid,
  p_email text,
  p_token_hash text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_actor_email text;
  v_invite public.tenant_invites%ROWTYPE;
  v_existing_role text;
  v_existing_status text;
  v_tenant_status text;
BEGIN
  IF (auth.jwt() ->> 'role') IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;
  IF p_actor_user_id IS NULL OR p_email IS NULL
     OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION 'invalid_tenant_invite_acceptance' USING ERRCODE = '22023';
  END IF;

  SELECT lower(email) INTO v_actor_email
  FROM auth.users WHERE id = p_actor_user_id;
  IF NOT FOUND OR v_actor_email IS NULL THEN
    RAISE EXCEPTION 'auth_user_email_required' USING ERRCODE = '42501';
  END IF;
  IF v_actor_email <> lower(trim(p_email)) THEN
    RAISE EXCEPTION 'tenant_invite_email_mismatch' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_invite
  FROM public.tenant_invites
  WHERE token_hash = p_token_hash
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant_invite_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_invite.status = 'accepted' AND v_invite.accepted_by = p_actor_user_id THEN
    IF EXISTS (
      SELECT 1 FROM public.tenant_memberships
      WHERE tenant_id = v_invite.tenant_id AND user_id = p_actor_user_id
        AND status = 'active' AND role = v_invite.role
    ) THEN
      RETURN jsonb_build_object('ok',true,'replayed',true,'invite',jsonb_build_object(
        'id',v_invite.id,'tenant_id',v_invite.tenant_id,'status',v_invite.status,'role',v_invite.role
      ));
    END IF;
    RAISE EXCEPTION 'accepted_invite_membership_mismatch' USING ERRCODE = '55000';
  END IF;

  IF v_invite.status <> 'pending' THEN
    RAISE EXCEPTION 'tenant_invite_not_pending' USING ERRCODE = 'P0002';
  END IF;
  IF v_invite.expires_at <= now() THEN
    UPDATE public.tenant_invites SET status = 'expired' WHERE id = v_invite.id;
    INSERT INTO public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
    VALUES (p_actor_user_id,'tenant_invite_expired','tenant_invite',v_invite.id::text,
      jsonb_build_object('tenant_id',v_invite.tenant_id,'email',v_invite.email));
    RETURN jsonb_build_object('ok',false,'status','expired');
  END IF;
  IF v_invite.email <> v_actor_email THEN
    RAISE EXCEPTION 'tenant_invite_email_mismatch' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_tenant_status
  FROM public.tenants WHERE id = v_invite.tenant_id FOR SHARE;
  IF NOT FOUND OR v_tenant_status NOT IN ('active','trial') THEN
    RAISE EXCEPTION 'tenant_not_active_for_invites' USING ERRCODE = '55000';
  END IF;

  SELECT role,status INTO v_existing_role,v_existing_status
  FROM public.tenant_memberships
  WHERE tenant_id = v_invite.tenant_id AND user_id = p_actor_user_id
  FOR UPDATE;
  IF FOUND AND v_existing_status = 'active' THEN
    RAISE EXCEPTION 'tenant_membership_already_active' USING ERRCODE = '23505';
  END IF;
  IF FOUND AND v_existing_role IN ('tenant_owner','tenant_admin') THEN
    RAISE EXCEPTION 'tenant_admin_membership_cannot_be_replaced_by_invite' USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.tenant_memberships
    (tenant_id,user_id,role,permissions,status,created_at,updated_at)
  VALUES (v_invite.tenant_id,p_actor_user_id,v_invite.role,'[]'::jsonb,'active',now(),now())
  ON CONFLICT (tenant_id,user_id) DO UPDATE
    SET role = EXCLUDED.role,permissions = '[]'::jsonb,status = 'active',updated_at = now();

  UPDATE public.tenant_invites
  SET status = 'accepted',accepted_by = p_actor_user_id,accepted_at = now()
  WHERE id = v_invite.id AND status = 'pending';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant_invite_state_changed' USING ERRCODE = '40001';
  END IF;

  INSERT INTO public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  VALUES (p_actor_user_id,'tenant_invite_accepted','tenant_invite',v_invite.id::text,
    jsonb_build_object('tenant_id',v_invite.tenant_id,'email',v_invite.email,'role',v_invite.role));

  RETURN jsonb_build_object('ok',true,'replayed',false,'invite',jsonb_build_object(
    'id',v_invite.id,'tenant_id',v_invite.tenant_id,'status','accepted','role',v_invite.role
  ));
END;
$$;

REVOKE ALL ON FUNCTION public.dlice_create_tenant_invite_atomic(uuid,uuid,text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_create_tenant_invite_atomic(uuid,uuid,text,text,text,timestamptz) TO service_role;
REVOKE ALL ON FUNCTION public.dlice_accept_tenant_invite_atomic(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_accept_tenant_invite_atomic(uuid,text,text) TO service_role;
