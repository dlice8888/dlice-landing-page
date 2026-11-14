BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(27);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT throws_ok(
  $$SELECT public.dlice_manage_branch_checklist('start', null)$$,
  '42501',
  'service_role_required',
  'rejects non-service callers'
);

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.dlice_manage_branch_checklist(text,uuid,uuid,date,text,jsonb,uuid,text,text,text,integer)',
    'execute'
  ),
  'does not grant RPC execution to anon'
);

SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.dlice_manage_branch_checklist(text,uuid,uuid,date,text,jsonb,uuid,text,text,text,integer)',
    'execute'
  ),
  'does not grant RPC execution to authenticated users'
);

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES (
  'b0000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'branch-checklist-audit-test@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
) ON CONFLICT (id) DO NOTHING;

SELECT set_config('request.jwt.claim.role', 'service_role', true);

CREATE OR REPLACE FUNCTION public.test_reject_branch_checklist_audit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('test.fail_branch_checklist_audit', true) = NEW.action THEN
    RAISE EXCEPTION 'forced audit failure';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER test_reject_branch_checklist_audit
BEFORE INSERT ON public.admin_audit_logs
FOR EACH ROW EXECUTE FUNCTION public.test_reject_branch_checklist_audit();

SELECT is(
  public.dlice_manage_branch_checklist(
    p_action => 'start',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_branch_id => (SELECT id FROM public.branches WHERE code = 'DLC-HQ'),
    p_business_date => DATE '2099-12-31',
    p_checklist_type => 'opening',
    p_items => '[
      {"key":"critical","label":"Critical check","critical":true,"status":"pending"},
      {"key":"optional","label":"Optional check","critical":false,"status":"pending"}
    ]'::jsonb
  )->>'existing',
  'false',
  'creates a new checklist run'
);

SELECT set_config('test.fail_branch_checklist_audit', 'branch_checklist_item_updated', true);

SELECT throws_ok(
  $$SELECT public.dlice_manage_branch_checklist(
    p_action => 'update_item',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_run_id => (SELECT id FROM public.branch_operation_checklist_runs
                 WHERE business_date = DATE '2099-12-31' AND checklist_type = 'opening'),
    p_item_key => 'critical',
    p_item_status => 'passed',
    p_expected_version => 1
  )$$,
  'P0001',
  'forced audit failure',
  'returns an error when item-update audit insertion fails'
);

SELECT is(
  (SELECT items->0->>'status' || ':' || version::text
   FROM public.branch_operation_checklist_runs
   WHERE business_date = DATE '2099-12-31' AND checklist_type = 'opening'),
  'pending:1',
  'rolls back the item update and version when its audit insert fails'
);

SELECT set_config('test.fail_branch_checklist_audit', '', true);

SELECT is(
  (SELECT actor_user_id::text FROM public.admin_audit_logs
   WHERE action = 'branch_checklist_started'
     AND entity_id = (SELECT id::text FROM public.branch_operation_checklist_runs
                      WHERE business_date = DATE '2099-12-31'
                        AND checklist_type = 'opening')),
  'b0000000-0000-4000-8000-000000000001',
  'records the actor for checklist creation'
);

SELECT is(
  public.dlice_manage_branch_checklist(
    p_action => 'start',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_branch_id => (SELECT id FROM public.branches WHERE code = 'DLC-HQ'),
    p_business_date => DATE '2099-12-31',
    p_checklist_type => 'opening',
    p_items => '[
      {"key":"critical","label":"Critical check","critical":true,"status":"pending"},
      {"key":"optional","label":"Optional check","critical":false,"status":"pending"}
    ]'::jsonb
  )->>'existing',
  'true',
  'returns the existing run for an idempotent start'
);

SELECT is(
  (SELECT count(*)::integer FROM public.admin_audit_logs
   WHERE action = 'branch_checklist_started'
     AND entity_id = (SELECT id::text FROM public.branch_operation_checklist_runs
                      WHERE business_date = DATE '2099-12-31'
                        AND checklist_type = 'opening')),
  1,
  'does not duplicate start audit events on retry'
);

SELECT is(
  public.dlice_manage_branch_checklist(
    p_action => 'update_item',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_run_id => (SELECT id FROM public.branch_operation_checklist_runs
                 WHERE business_date = DATE '2099-12-31' AND checklist_type = 'opening'),
    p_item_key => 'critical',
    p_item_status => 'passed',
    p_expected_version => 1
  )->>'version',
  '2',
  'updates a checklist item with optimistic versioning'
);

SELECT is(
  (SELECT count(*)::integer FROM public.admin_audit_logs
   WHERE action = 'branch_checklist_item_updated'
     AND metadata->>'item_key' = 'critical'),
  1,
  'writes the item update audit event atomically'
);

SELECT is(
  public.dlice_manage_branch_checklist(
    p_action => 'update_item',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_run_id => (SELECT id FROM public.branch_operation_checklist_runs
                 WHERE business_date = DATE '2099-12-31' AND checklist_type = 'opening'),
    p_item_key => 'optional',
    p_item_status => 'passed',
    p_expected_version => 2
  )->>'version',
  '3',
  'accepts the next item update at the current version'
);

SELECT set_config('test.fail_branch_checklist_audit', 'branch_checklist_completed', true);

SELECT throws_ok(
  $$SELECT public.dlice_manage_branch_checklist(
    p_action => 'complete',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_run_id => (SELECT id FROM public.branch_operation_checklist_runs
                 WHERE business_date = DATE '2099-12-31' AND checklist_type = 'opening'),
    p_expected_version => 3
  )$$,
  'P0001',
  'forced audit failure',
  'returns an error when completion audit insertion fails'
);

SELECT is(
  (SELECT status || ':' || version::text
   FROM public.branch_operation_checklist_runs
   WHERE business_date = DATE '2099-12-31' AND checklist_type = 'opening'),
  'in_progress:3',
  'rolls back completion when its audit insert fails'
);

SELECT set_config('test.fail_branch_checklist_audit', '', true);

SELECT is(
  public.dlice_manage_branch_checklist(
    p_action => 'complete',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_run_id => (SELECT id FROM public.branch_operation_checklist_runs
                 WHERE business_date = DATE '2099-12-31' AND checklist_type = 'opening'),
    p_expected_version => 3
  )->>'status',
  'completed',
  'completes a checklist after every item passes'
);

SELECT is(
  (SELECT count(*)::integer FROM public.admin_audit_logs
   WHERE action = 'branch_checklist_completed'
     AND entity_id = (SELECT id::text FROM public.branch_operation_checklist_runs
                      WHERE business_date = DATE '2099-12-31'
                        AND checklist_type = 'opening')),
  1,
  'records completion in the same transaction'
);

SELECT is(
  public.dlice_manage_branch_checklist(
    p_action => 'complete',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_run_id => (SELECT id FROM public.branch_operation_checklist_runs
                 WHERE business_date = DATE '2099-12-31' AND checklist_type = 'opening'),
    p_expected_version => 3
  )->>'status',
  'completed',
  'treats a repeated completion as idempotent'
);

SELECT is(
  public.dlice_manage_branch_checklist(
    p_action => 'start',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_branch_id => (SELECT id FROM public.branches WHERE code = 'DLC-HQ'),
    p_business_date => DATE '2099-12-30',
    p_checklist_type => 'closing',
    p_items => '[
      {"key":"critical","label":"Critical check","critical":true,"status":"pending"},
      {"key":"optional","label":"Optional check","critical":false,"status":"pending"}
    ]'::jsonb
  )->>'existing',
  'false',
  'creates a second run for a different date and type'
);

SELECT is(
  public.dlice_manage_branch_checklist(
    p_action => 'update_item',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_run_id => (SELECT id FROM public.branch_operation_checklist_runs
                 WHERE business_date = DATE '2099-12-30' AND checklist_type = 'closing'),
    p_item_key => 'critical',
    p_item_status => 'failed',
    p_notes => 'Temperature out of range',
    p_expected_version => 1
  )->>'version',
  '2',
  'stores a failed critical item with the required note'
);

SELECT is(
  public.dlice_manage_branch_checklist(
    p_action => 'update_item',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_run_id => (SELECT id FROM public.branch_operation_checklist_runs
                 WHERE business_date = DATE '2099-12-30' AND checklist_type = 'closing'),
    p_item_key => 'optional',
    p_item_status => 'passed',
    p_expected_version => 2
  )->>'version',
  '3',
  'allows non-critical checklist items to pass'
);

SELECT set_config('test.fail_branch_checklist_audit', 'branch_checklist_blocked', true);

SELECT throws_ok(
  $$SELECT public.dlice_manage_branch_checklist(
    p_action => 'complete',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_run_id => (SELECT id FROM public.branch_operation_checklist_runs
                 WHERE business_date = DATE '2099-12-30' AND checklist_type = 'closing'),
    p_expected_version => 3
  )$$,
  'P0001',
  'forced audit failure',
  'returns an error when blocked-state audit insertion fails'
);

SELECT is(
  (SELECT status || ':' || version::text
   FROM public.branch_operation_checklist_runs
   WHERE business_date = DATE '2099-12-30' AND checklist_type = 'closing'),
  'in_progress:3',
  'rolls back blocked status when its audit insert fails'
);

SELECT set_config('test.fail_branch_checklist_audit', '', true);

SELECT is(
  public.dlice_manage_branch_checklist(
    p_action => 'complete',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_run_id => (SELECT id FROM public.branch_operation_checklist_runs
                 WHERE business_date = DATE '2099-12-30' AND checklist_type = 'closing'),
    p_expected_version => 3
  )->>'blocked',
  'true',
  'blocks completion while a critical item has failed'
);

SELECT is(
  (SELECT status FROM public.branch_operation_checklist_runs
   WHERE business_date = DATE '2099-12-30' AND checklist_type = 'closing'),
  'blocked',
  'persists blocked checklist state'
);

SELECT set_config('test.fail_branch_checklist_audit', 'branch_checklist_started', true);

SELECT throws_ok(
  $$SELECT public.dlice_manage_branch_checklist(
    p_action => 'start',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_branch_id => (SELECT id FROM public.branches WHERE code = 'DLC-HQ'),
    p_business_date => DATE '2099-12-29',
    p_checklist_type => 'opening',
    p_items => '[{"key":"critical","label":"Critical check","critical":true,"status":"pending"}]'::jsonb
  )$$,
  'P0001',
  'forced audit failure',
  'returns a database error if audit insertion fails'
);

SELECT is(
  (SELECT count(*)::integer FROM public.branch_operation_checklist_runs
   WHERE business_date = DATE '2099-12-29' AND checklist_type = 'opening'),
  0,
  'rolls back checklist creation when audit insertion fails'
);

SELECT throws_ok(
  $$SELECT public.dlice_manage_branch_checklist(
    p_action => 'update_item',
    p_actor_user_id => 'b0000000-0000-4000-8000-000000000001',
    p_run_id => (SELECT id FROM public.branch_operation_checklist_runs
                 WHERE business_date = DATE '2099-12-31' AND checklist_type = 'opening'),
    p_item_key => 'critical',
    p_item_status => 'failed',
    p_notes => 'attempt after completion',
    p_expected_version => 3
  )$$,
  '55000',
  'checklist_completed',
  'does not allow updates after completion'
);

SELECT * FROM finish();
ROLLBACK;
