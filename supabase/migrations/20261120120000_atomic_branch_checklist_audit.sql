ALTER TABLE public.branch_operation_checklist_runs
  ADD COLUMN IF NOT EXISTS updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.dlice_manage_branch_checklist(
  p_action text,
  p_actor_user_id uuid,
  p_branch_id uuid DEFAULT NULL,
  p_business_date date DEFAULT NULL,
  p_checklist_type text DEFAULT NULL,
  p_items jsonb DEFAULT NULL,
  p_run_id uuid DEFAULT NULL,
  p_item_key text DEFAULT NULL,
  p_item_status text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_expected_version integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_run public.branch_operation_checklist_runs%ROWTYPE;
  v_items jsonb;
  v_updated_items jsonb;
  v_item_found boolean := false;
  v_blocked boolean;
  v_now timestamptz := now();
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;

  IF p_actor_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.users WHERE id = p_actor_user_id
  ) THEN
    RAISE EXCEPTION 'valid_actor_required' USING ERRCODE = '22023';
  END IF;

  IF p_action = 'start' THEN
    IF p_branch_id IS NULL OR p_business_date IS NULL
      OR p_checklist_type IS NULL
      OR p_checklist_type NOT IN ('opening', 'closing')
      OR jsonb_typeof(p_items) IS DISTINCT FROM 'array'
    THEN
      RAISE EXCEPTION 'invalid_checklist_start' USING ERRCODE = '22023';
    END IF;

    IF jsonb_array_length(p_items) = 0 THEN
      RAISE EXCEPTION 'invalid_checklist_items' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.branches
      WHERE id = p_branch_id AND status = 'active'
    ) THEN
      RAISE EXCEPTION 'active_branch_required' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM jsonb_array_elements(p_items) AS item
      WHERE coalesce(item->>'key', '') = ''
        OR coalesce(item->>'label', '') = ''
        OR jsonb_typeof(item->'critical') IS DISTINCT FROM 'boolean'
    ) OR (
      SELECT count(*) <> count(DISTINCT item->>'key')
      FROM jsonb_array_elements(p_items) AS item
    ) THEN
      RAISE EXCEPTION 'invalid_checklist_items' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.branch_operation_checklist_runs (
      branch_id, business_date, checklist_type, template_version,
      items, status, started_by, updated_by
    ) VALUES (
      p_branch_id, p_business_date, p_checklist_type, 1,
      p_items, 'in_progress', p_actor_user_id, p_actor_user_id
    )
    ON CONFLICT (branch_id, business_date, checklist_type) DO NOTHING
    RETURNING * INTO v_run;

    IF NOT FOUND THEN
      SELECT * INTO v_run
      FROM public.branch_operation_checklist_runs
      WHERE branch_id = p_branch_id
        AND business_date = p_business_date
        AND checklist_type = p_checklist_type
      FOR UPDATE;
      RETURN jsonb_build_object('run', to_jsonb(v_run), 'existing', true);
    END IF;

    INSERT INTO public.admin_audit_logs (
      actor_user_id, action, entity_type, entity_id, metadata
    ) VALUES (
      p_actor_user_id,
      'branch_checklist_started',
      'branch_operation_checklist_run',
      v_run.id::text,
      jsonb_build_object(
        'branch_id', p_branch_id,
        'checklist_type', p_checklist_type,
        'business_date', p_business_date
      )
    );

    RETURN jsonb_build_object('run', to_jsonb(v_run), 'existing', false);
  END IF;

  IF p_action IS NULL OR p_action NOT IN ('update_item', 'complete') OR p_run_id IS NULL THEN
    RAISE EXCEPTION 'invalid_checklist_action' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_run
  FROM public.branch_operation_checklist_runs
  WHERE id = p_run_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'checklist_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_run.status = 'completed' THEN
    IF p_action = 'complete' THEN
      RETURN jsonb_build_object(
        'ok', true,
        'status', v_run.status,
        'completed_at', v_run.completed_at,
        'version', v_run.version
      );
    END IF;
    RAISE EXCEPTION 'checklist_completed' USING ERRCODE = '55000';
  END IF;

  IF p_expected_version IS NULL OR v_run.version <> p_expected_version THEN
    RAISE EXCEPTION 'checklist_version_conflict' USING ERRCODE = '40001';
  END IF;

  v_items := v_run.items;

  IF p_action = 'update_item' THEN
    IF p_item_key IS NULL OR p_item_status IS NULL
      OR p_item_status NOT IN ('passed', 'failed', 'skipped')
      OR (p_item_status = 'failed' AND length(trim(coalesce(p_notes, ''))) < 3)
    THEN
      RAISE EXCEPTION 'invalid_checklist_item_update' USING ERRCODE = '22023';
    END IF;

    SELECT coalesce(
      jsonb_agg(
        CASE
          WHEN item->>'key' = p_item_key THEN
            item || jsonb_build_object(
              'status', p_item_status,
              'notes', left(coalesce(p_notes, ''), 500),
              'checked_by', p_actor_user_id,
              'checked_at', v_now
            )
          ELSE item
        END
        ORDER BY ordinal
      ),
      '[]'::jsonb
    ), bool_or(item->>'key' = p_item_key)
    INTO v_updated_items, v_item_found
    FROM jsonb_array_elements(v_items) WITH ORDINALITY AS entries(item, ordinal);

    IF NOT coalesce(v_item_found, false) THEN
      RAISE EXCEPTION 'checklist_item_not_found' USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.branch_operation_checklist_runs
    SET items = v_updated_items,
        updated_by = p_actor_user_id,
        version = version + 1,
        updated_at = v_now
    WHERE id = p_run_id
    RETURNING * INTO v_run;

    INSERT INTO public.admin_audit_logs (
      actor_user_id, action, entity_type, entity_id, metadata
    ) VALUES (
      p_actor_user_id,
      'branch_checklist_item_updated',
      'branch_operation_checklist_run',
      v_run.id::text,
      jsonb_build_object(
        'branch_id', v_run.branch_id,
        'checklist_type', v_run.checklist_type,
        'business_date', v_run.business_date,
        'item_key', p_item_key,
        'item_status', p_item_status
      )
    );

    RETURN jsonb_build_object('ok', true, 'version', v_run.version);
  END IF;

  IF jsonb_array_length(v_items) = 0
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_items) AS item
      WHERE coalesce(item->>'status', 'pending') = 'pending'
    )
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_items) AS item
      WHERE item->>'status' = 'failed'
        AND length(trim(coalesce(item->>'notes', ''))) = 0
    )
  THEN
    RAISE EXCEPTION 'checklist_items_incomplete' USING ERRCODE = '22023';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_items) AS item
    WHERE item->'critical' = 'true'::jsonb
      AND item->>'status' <> 'passed'
  ) INTO v_blocked;

  IF v_blocked THEN
    UPDATE public.branch_operation_checklist_runs
    SET status = 'blocked',
        updated_by = p_actor_user_id,
        version = version + 1,
        updated_at = v_now
    WHERE id = p_run_id
    RETURNING * INTO v_run;

    INSERT INTO public.admin_audit_logs (
      actor_user_id, action, entity_type, entity_id, metadata
    ) VALUES (
      p_actor_user_id,
      'branch_checklist_blocked',
      'branch_operation_checklist_run',
      v_run.id::text,
      jsonb_build_object(
        'branch_id', v_run.branch_id,
        'checklist_type', v_run.checklist_type,
        'business_date', v_run.business_date,
        'failed_critical_items', (
          SELECT coalesce(jsonb_agg(item->>'key'), '[]'::jsonb)
          FROM jsonb_array_elements(v_items) AS item
          WHERE item->'critical' = 'true'::jsonb
            AND item->>'status' <> 'passed'
        )
      )
    );

    RETURN jsonb_build_object('blocked', true, 'version', v_run.version);
  END IF;

  UPDATE public.branch_operation_checklist_runs
  SET status = 'completed',
      completed_by = p_actor_user_id,
      completed_at = v_now,
      updated_by = p_actor_user_id,
      version = version + 1,
      updated_at = v_now
  WHERE id = p_run_id
  RETURNING * INTO v_run;

  INSERT INTO public.admin_audit_logs (
    actor_user_id, action, entity_type, entity_id, metadata
  ) VALUES (
    p_actor_user_id,
    'branch_checklist_completed',
    'branch_operation_checklist_run',
    v_run.id::text,
    jsonb_build_object(
      'branch_id', v_run.branch_id,
      'checklist_type', v_run.checklist_type,
      'business_date', v_run.business_date
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'status', v_run.status,
    'completed_at', v_run.completed_at,
    'version', v_run.version
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dlice_manage_branch_checklist(
  text, uuid, uuid, date, text, jsonb, uuid, text, text, text, integer
) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dlice_manage_branch_checklist(
  text, uuid, uuid, date, text, jsonb, uuid, text, text, text, integer
) TO service_role;
