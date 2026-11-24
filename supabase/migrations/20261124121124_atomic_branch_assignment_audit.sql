BEGIN;

CREATE OR REPLACE FUNCTION public.dlice_save_branch_assignment_audited(
  p_actor_user_id uuid,
  p_branch_id uuid,
  p_user_id uuid,
  p_job_position_id uuid,
  p_employment_status text,
  p_starts_on date,
  p_ends_on date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_tenant_id uuid;
  v_branch_status text;
  v_tenant_status text;
  v_actor_role text;
  v_target_role text;
  v_membership_status text;
  v_position_active boolean;
  v_existing public.branch_assignments%ROWTYPE;
  v_assignment public.branch_assignments%ROWTYPE;
  v_changed boolean := false;
BEGIN
  IF (auth.jwt() ->> 'role') IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;
  IF p_actor_user_id IS NULL OR p_branch_id IS NULL OR p_user_id IS NULL
     OR p_job_position_id IS NULL OR p_employment_status IS NULL OR p_starts_on IS NULL
     OR p_employment_status NOT IN ('active','on_leave','inactive')
     OR (p_ends_on IS NOT NULL AND p_ends_on < p_starts_on)
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_actor_user_id)
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id)
  THEN
    RAISE EXCEPTION 'invalid_branch_assignment_details' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.admin_profiles ap
    JOIN auth.users u ON u.id = ap.user_id
    WHERE ap.user_id = p_actor_user_id
      AND ap.role = 'owner'
      AND coalesce(u.raw_app_meta_data->>'platform_owner','false') = 'true'
  ) THEN
    RAISE EXCEPTION 'platform_owner_required' USING ERRCODE = '42501';
  END IF;

  SELECT tenant_id,status INTO v_tenant_id,v_branch_status
  FROM public.branches
  WHERE id = p_branch_id
  FOR SHARE;
  IF NOT FOUND OR v_branch_status NOT IN ('planned','active') THEN
    RAISE EXCEPTION 'branch_not_assignable' USING ERRCODE = 'P0002';
  END IF;
  SELECT status INTO v_tenant_status
  FROM public.tenants
  WHERE id = v_tenant_id
  FOR SHARE;
  IF NOT FOUND OR v_tenant_status NOT IN ('active','trial') THEN
    RAISE EXCEPTION 'tenant_not_active_for_assignments' USING ERRCODE = '55000';
  END IF;

  SELECT role INTO v_target_role
  FROM public.admin_profiles
  WHERE user_id = p_user_id
  FOR SHARE;
  IF NOT FOUND OR v_target_role = 'owner' THEN
    RAISE EXCEPTION 'staff_profile_not_assignable' USING ERRCODE = 'P0002';
  END IF;

  SELECT is_active INTO v_position_active
  FROM public.job_positions
  WHERE id = p_job_position_id
  FOR SHARE;
  IF NOT FOUND OR v_position_active IS NOT TRUE THEN
    RAISE EXCEPTION 'job_position_not_active' USING ERRCODE = '22023';
  END IF;

  SELECT status INTO v_membership_status
  FROM public.tenant_memberships
  WHERE tenant_id = v_tenant_id AND user_id = p_user_id
  FOR SHARE;
  IF p_employment_status IN ('active','on_leave')
     AND (NOT FOUND OR v_membership_status <> 'active') THEN
    RAISE EXCEPTION 'active_tenant_membership_required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_existing
  FROM public.branch_assignments
  WHERE branch_id = p_branch_id
    AND user_id = p_user_id
    AND job_position_id = p_job_position_id
  FOR UPDATE;

  IF p_employment_status = 'inactive' AND NOT FOUND AND v_membership_status IS NULL THEN
    RAISE EXCEPTION 'tenant_membership_required' USING ERRCODE = '42501';
  END IF;

  IF FOUND THEN
    IF v_existing.employment_status = p_employment_status
       AND v_existing.starts_on = p_starts_on
       AND v_existing.ends_on IS NOT DISTINCT FROM p_ends_on
    THEN
      RETURN jsonb_build_object('ok',true,'changed',false,'assignment',to_jsonb(v_existing));
    END IF;

    UPDATE public.branch_assignments
    SET employment_status = p_employment_status,
        starts_on = p_starts_on,
        ends_on = p_ends_on,
        assigned_by = p_actor_user_id,
        updated_at = now()
    WHERE id = v_existing.id
    RETURNING * INTO v_assignment;
  ELSE
    INSERT INTO public.branch_assignments
      (branch_id,user_id,job_position_id,employment_status,starts_on,ends_on,assigned_by,created_at,updated_at)
    VALUES
      (p_branch_id,p_user_id,p_job_position_id,p_employment_status,p_starts_on,p_ends_on,p_actor_user_id,now(),now())
    RETURNING * INTO v_assignment;
  END IF;

  INSERT INTO public.admin_audit_logs
    (actor_user_id,action,entity_type,entity_id,metadata)
  VALUES
    (p_actor_user_id,'erp_assign_job_position','branch_assignment',v_assignment.id::text,
     jsonb_build_object(
       'tenant_id',v_tenant_id,
       'branch_id',p_branch_id,
       'user_id',p_user_id,
       'job_position_id',p_job_position_id,
       'previous',CASE WHEN v_existing.id IS NULL THEN NULL ELSE jsonb_build_object(
         'employment_status',v_existing.employment_status,
         'starts_on',v_existing.starts_on,
         'ends_on',v_existing.ends_on
       ) END,
       'next',jsonb_build_object(
         'employment_status',p_employment_status,
         'starts_on',p_starts_on,
         'ends_on',p_ends_on
       )
     ));

  v_changed := true;
  RETURN jsonb_build_object('ok',true,'changed',v_changed,'assignment',to_jsonb(v_assignment));
END;
$function$;

REVOKE ALL ON FUNCTION public.dlice_save_branch_assignment_audited(uuid,uuid,uuid,uuid,text,date,date)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_save_branch_assignment_audited(uuid,uuid,uuid,uuid,text,date,date)
  TO service_role;

COMMIT;
