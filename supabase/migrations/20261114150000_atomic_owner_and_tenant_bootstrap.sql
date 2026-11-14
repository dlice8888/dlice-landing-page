CREATE OR REPLACE FUNCTION public.dlice_bootstrap_initial_owner(
  p_user_id uuid,
  p_username text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL
    OR p_username IS NULL
    OR p_username !~ '^[A-Za-z0-9._-]{3,32}$'
    OR NOT EXISTS (
      SELECT 1
      FROM auth.users
      WHERE id = p_user_id
        AND lower(email) = lower(p_username) || '@accounts.dlice.internal'
        AND raw_app_meta_data->>'platform_owner' = 'true'
    )
  THEN
    RAISE EXCEPTION 'valid_owner_required' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('dlice_initial_owner_bootstrap', 0));

  IF EXISTS (SELECT 1 FROM public.admin_profiles WHERE role = 'owner') THEN
    RAISE EXCEPTION 'owner_already_bootstrapped' USING ERRCODE = '23505';
  END IF;

  SELECT id INTO v_tenant_id
  FROM public.tenants
  WHERE slug = 'dlice-default'
  FOR SHARE;

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'default_tenant_required' USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.admin_profiles (
    user_id, username, role, display_name, is_active, permissions
  ) VALUES (
    p_user_id, lower(p_username), 'owner', 'Owner D’Lice', true, '["*"]'::jsonb
  );

  INSERT INTO public.tenant_memberships (
    tenant_id, user_id, role, permissions, status
  ) VALUES (
    v_tenant_id, p_user_id, 'tenant_owner', '["*"]'::jsonb, 'active'
  );

  INSERT INTO public.admin_audit_logs (
    actor_user_id, action, entity_type, entity_id, metadata
  ) VALUES (
    p_user_id, 'bootstrap_owner', 'admin_profile', p_user_id::text,
    jsonb_build_object('username', lower(p_username), 'tenant_id', v_tenant_id)
  );

  RETURN jsonb_build_object('ok', true, 'user_id', p_user_id, 'tenant_id', v_tenant_id);
END;
$$;

REVOKE ALL ON FUNCTION public.dlice_bootstrap_initial_owner(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_bootstrap_initial_owner(uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.dlice_create_tenant_with_owner(
  p_actor_user_id uuid,
  p_slug text,
  p_legal_name text,
  p_plan_code text DEFAULT 'starter'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant public.tenants%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;

  IF p_actor_user_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.admin_profiles AS profile
    JOIN auth.users AS auth_user ON auth_user.id = profile.user_id
    WHERE profile.user_id = p_actor_user_id
      AND profile.role = 'owner'
      AND profile.is_active
      AND auth_user.raw_app_meta_data->>'platform_owner' = 'true'
  ) THEN
    RAISE EXCEPTION 'active_platform_owner_required' USING ERRCODE = '42501';
  END IF;

  IF p_slug IS NULL OR p_slug !~ '^[a-z0-9][a-z0-9-]{1,60}$'
    OR p_legal_name IS NULL OR length(trim(p_legal_name)) NOT BETWEEN 2 AND 180
    OR p_plan_code IS NULL OR length(trim(p_plan_code)) NOT BETWEEN 1 AND 40
  THEN
    RAISE EXCEPTION 'invalid_tenant_details' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.tenants (slug, legal_name, status, plan_code, settings)
  VALUES (p_slug, trim(p_legal_name), 'trial', trim(p_plan_code), '{}'::jsonb)
  RETURNING * INTO v_tenant;

  INSERT INTO public.tenant_memberships (
    tenant_id, user_id, role, permissions, status
  ) VALUES (
    v_tenant.id, p_actor_user_id, 'tenant_owner', '["*"]'::jsonb, 'active'
  );

  INSERT INTO public.admin_audit_logs (
    actor_user_id, action, entity_type, entity_id, metadata
  ) VALUES (
    p_actor_user_id, 'tenant_created', 'tenant', v_tenant.id::text,
    jsonb_build_object(
      'slug', v_tenant.slug,
      'legal_name', v_tenant.legal_name,
      'tenant_id', v_tenant.id
    )
  );

  RETURN jsonb_build_object('ok', true, 'tenant', to_jsonb(v_tenant));
END;
$$;

REVOKE ALL ON FUNCTION public.dlice_create_tenant_with_owner(uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_create_tenant_with_owner(uuid, text, text, text) TO service_role;
