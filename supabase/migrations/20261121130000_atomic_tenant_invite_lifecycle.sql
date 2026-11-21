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
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invite public.tenant_invites%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;

  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL
    OR p_email IS NULL OR length(trim(p_email)) NOT BETWEEN 3 AND 254
    OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    OR p_role IS NULL OR p_role NOT IN ('tenant_admin','branch_manager','cashier','inventory','production','finance','viewer','tenant_member')
    OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$'
    OR p_expires_at IS NULL OR p_expires_at <= now()
    OR p_expires_at > now() + interval '30 days'
  THEN
    RAISE EXCEPTION 'invalid_tenant_invite' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'tenant_invite:' || p_tenant_id::text || ':' || lower(trim(p_email)), 0
  ));

  WITH expired AS (
    UPDATE public.tenant_invites
    SET status = 'expired'
    WHERE tenant_id = p_tenant_id
      AND lower(email) = lower(trim(p_email))
      AND status = 'pending'
      AND expires_at <= now()
    RETURNING id, tenant_id, email
  )
  INSERT INTO public.admin_audit_logs (
    actor_user_id,action,entity_type,entity_id,metadata
  )
  SELECT
    p_actor_user_id,'tenant_invite_expired','tenant_invite',expired.id,
    jsonb_build_object('tenant_id',expired.tenant_id,'email',expired.email)
  FROM expired;

  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships
    WHERE tenant_id = p_tenant_id
      AND user_id = p_actor_user_id
      AND status = 'active'
      AND role IN ('tenant_owner','tenant_admin')
  ) THEN
    RAISE EXCEPTION 'tenant_invite_permission_denied' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.tenant_invites
    WHERE tenant_id = p_tenant_id
      AND lower(email) = lower(trim(p_email))
      AND status = 'pending'
      AND expires_at > now()
  ) THEN
    RAISE EXCEPTION 'pending_tenant_invite_exists' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.tenant_invites (
    tenant_id,email,role,token_hash,invited_by,expires_at,status
  ) VALUES (
    p_tenant_id,lower(trim(p_email)),p_role,p_token_hash,p_actor_user_id,p_expires_at,'pending'
  ) RETURNING * INTO v_invite;

  INSERT INTO public.admin_audit_logs (
    actor_user_id,action,entity_type,entity_id,metadata
  ) VALUES (
    p_actor_user_id,'tenant_member_invited','tenant_invite',v_invite.id,
    jsonb_build_object(
      'tenant_id',p_tenant_id,
      'email',v_invite.email,
      'role',v_invite.role,
      'expires_at',v_invite.expires_at
    )
  );

  RETURN jsonb_build_object(
    'ok',true,
    'invite',jsonb_build_object(
      'id',v_invite.id,
      'tenant_id',v_invite.tenant_id,
      'email',v_invite.email,
      'role',v_invite.role,
      'status',v_invite.status,
      'expires_at',v_invite.expires_at
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.dlice_accept_tenant_invite_atomic(
  p_actor_user_id uuid,
  p_email text,
  p_token_hash text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invite public.tenant_invites%ROWTYPE;
  v_existing public.tenant_memberships%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;

  IF p_actor_user_id IS NULL OR p_email IS NULL
    OR length(trim(p_email)) NOT BETWEEN 3 AND 254
    OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION 'invalid_tenant_invite_acceptance' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_invite
  FROM public.tenant_invites
  WHERE token_hash = p_token_hash
  FOR UPDATE;

  IF NOT FOUND OR v_invite.status <> 'pending' THEN
    RAISE EXCEPTION 'tenant_invite_not_pending' USING ERRCODE = 'P0002';
  END IF;

  IF lower(v_invite.email) <> lower(trim(p_email)) THEN
    RAISE EXCEPTION 'tenant_invite_email_mismatch' USING ERRCODE = '42501';
  END IF;

  IF v_invite.expires_at <= now() THEN
    UPDATE public.tenant_invites SET status = 'expired' WHERE id = v_invite.id;
    INSERT INTO public.admin_audit_logs (
      actor_user_id,action,entity_type,entity_id,metadata
    ) VALUES (
      p_actor_user_id,'tenant_invite_expired','tenant_invite',v_invite.id,
      jsonb_build_object('tenant_id',v_invite.tenant_id,'email',v_invite.email)
    );
    RETURN jsonb_build_object('ok',false,'status','expired');
  END IF;

  SELECT * INTO v_existing
  FROM public.tenant_memberships
  WHERE tenant_id = v_invite.tenant_id AND user_id = p_actor_user_id
  FOR UPDATE;

  IF FOUND THEN
    RAISE EXCEPTION 'tenant_membership_already_exists' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.tenant_memberships (
    tenant_id,user_id,role,permissions,status
  ) VALUES (
    v_invite.tenant_id,p_actor_user_id,v_invite.role,'[]'::jsonb,'active'
  );

  UPDATE public.tenant_invites
  SET status = 'accepted',accepted_by = p_actor_user_id,accepted_at = now()
  WHERE id = v_invite.id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant_invite_state_changed' USING ERRCODE = '40001';
  END IF;

  INSERT INTO public.admin_audit_logs (
    actor_user_id,action,entity_type,entity_id,metadata
  ) VALUES (
    p_actor_user_id,'tenant_invite_accepted','tenant_invite',v_invite.id,
    jsonb_build_object('tenant_id',v_invite.tenant_id,'email',v_invite.email,'role',v_invite.role)
  );

  RETURN jsonb_build_object(
    'ok',true,
    'invite',jsonb_build_object('id',v_invite.id,'tenant_id',v_invite.tenant_id,'status','accepted')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dlice_create_tenant_invite_atomic(uuid,uuid,text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_create_tenant_invite_atomic(uuid,uuid,text,text,text,timestamptz) TO service_role;
REVOKE ALL ON FUNCTION public.dlice_accept_tenant_invite_atomic(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_accept_tenant_invite_atomic(uuid,text,text) TO service_role;

    OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION 'invalid_tenant_invite_acceptance' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_invite
  FROM public.tenant_invites
  WHERE token_hash = p_token_hash
  FOR UPDATE;

  IF NOT FOUND OR v_invite.status <> 'pending' THEN
    RAISE EXCEPTION 'tenant_invite_not_pending' USING ERRCODE = 'P0002';
  END IF;

  IF lower(v_invite.email) <> lower(trim(p_email)) THEN
    RAISE EXCEPTION 'tenant_invite_email_mismatch' USING ERRCODE = '42501';
  END IF;

  IF v_invite.expires_at <= now() THEN
    UPDATE public.tenant_invites SET status = 'expired' WHERE id = v_invite.id;
    INSERT INTO public.admin_audit_logs (
      actor_user_id,action,entity_type,entity_id,metadata
    ) VALUES (
      p_actor_user_id,'tenant_invite_expired','tenant_invite',v_invite.id,
      jsonb_build_object('tenant_id',v_invite.tenant_id,'email',v_invite.email)
    );
    RETURN jsonb_build_object('ok',false,'status','expired');
  END IF;

  SELECT * INTO v_existing
  FROM public.tenant_memberships
  WHERE tenant_id = v_invite.tenant_id AND user_id = p_actor_user_id
  FOR UPDATE;

  IF FOUND THEN
    RAISE EXCEPTION 'tenant_membership_already_exists' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.tenant_memberships (
    tenant_id,user_id,role,permissions,status
  ) VALUES (
    v_invite.tenant_id,p_actor_user_id,v_invite.role,'[]'::jsonb,'active'
  );

  UPDATE public.tenant_invites
  SET status = 'accepted',accepted_by = p_actor_user_id,accepted_at = now()
  WHERE id = v_invite.id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant_invite_state_changed' USING ERRCODE = '40001';
  END IF;

  INSERT INTO public.admin_audit_logs (
    actor_user_id,action,entity_type,entity_id,metadata
  ) VALUES (
    p_actor_user_id,'tenant_invite_accepted','tenant_invite',v_invite.id,
    jsonb_build_object('tenant_id',v_invite.tenant_id,'email',v_invite.email,'role',v_invite.role)
  );

  RETURN jsonb_build_object(
    'ok',true,
    'invite',jsonb_build_object('id',v_invite.id,'tenant_id',v_invite.tenant_id,'status','accepted')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dlice_create_tenant_invite_atomic(uuid,uuid,text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_create_tenant_invite_atomic(uuid,uuid,text,text,text,timestamptz) TO service_role;
REVOKE ALL ON FUNCTION public.dlice_accept_tenant_invite_atomic(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_accept_tenant_invite_atomic(uuid,text,text) TO service_role;
