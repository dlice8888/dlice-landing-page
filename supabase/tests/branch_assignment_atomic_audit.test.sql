BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(19);

INSERT INTO auth.users
(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('e7000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','qa.assignment.owner@example.invalid','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
('e7000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','qa.assignment.staff@example.invalid','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
('e7000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','qa.assignment.nonowner@example.invalid','',now(),'{}'::jsonb,'{}'::jsonb,now(),now())
ON CONFLICT(id) DO NOTHING;

INSERT INTO public.admin_profiles(user_id,username,role,display_name,is_active,permissions)
VALUES
('e7000000-0000-4000-8000-000000000001','qa_assignment_owner','owner','QA Assignment Owner',true,'["*"]'::jsonb),
('e7000000-0000-4000-8000-000000000002','qa_assignment_staff','sales_admin','QA Assignment Staff',true,'["staff"]'::jsonb),
('e7000000-0000-4000-8000-000000000003','qa_assignment_nonowner','sales_admin','QA Assignment Non Owner',true,'["staff"]'::jsonb)
ON CONFLICT(user_id) DO UPDATE SET role=excluded.role,is_active=excluded.is_active;

INSERT INTO public.tenants(id,slug,legal_name,status)
VALUES
('e7000000-0000-4000-8000-000000000010','qa-assignment-a','QA Assignment A','active'),
('e7000000-0000-4000-8000-000000000011','qa-assignment-b','QA Assignment B','active')
ON CONFLICT(id) DO NOTHING;

INSERT INTO public.branches(id,code,name,status,tenant_id)
VALUES
('e7000000-0000-4000-8000-000000000020','QA-ASG-A','QA Assignment Branch A','active','e7000000-0000-4000-8000-000000000010'),
('e7000000-0000-4000-8000-000000000021','QA-ASG-B','QA Assignment Branch B','active','e7000000-0000-4000-8000-000000000011'),
('e7000000-0000-4000-8000-000000000022','QA-ASG-S','QA Assignment Suspended Branch','suspended','e7000000-0000-4000-8000-000000000010')
ON CONFLICT(id) DO NOTHING;

INSERT INTO public.tenant_memberships(tenant_id,user_id,role,permissions,status)
VALUES('e7000000-0000-4000-8000-000000000010','e7000000-0000-4000-8000-000000000002','branch_manager','["staff"]'::jsonb,'active')
ON CONFLICT(tenant_id,user_id) DO UPDATE SET status='active',role='branch_manager';

INSERT INTO public.job_positions(id,code,title,department,job_description,is_active)
VALUES
('e7000000-0000-4000-8000-000000000030','qa_assignment_active','QA Assignment Active','operations','Test position',true),
('e7000000-0000-4000-8000-000000000031','qa_assignment_inactive','QA Assignment Inactive','operations','Test inactive position',false)
ON CONFLICT(id) DO NOTHING;

SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT throws_ok(
 $$SELECT public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000020',
  'e7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000030',
  'active',current_date,NULL
 )$$,
 '42501','service_role_required','rejects non-service callers'
);

SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT throws_ok(
 $$SELECT public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000003','e7000000-0000-4000-8000-000000000020',
  'e7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000030',
  'active',current_date,NULL
 )$$,
 '42501','platform_owner_required','rejects a non-owner actor'
);
SELECT throws_ok(
 $$SELECT public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000020',
  'e7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000030',
  'terminated',current_date,NULL
 )$$,
 '22023','invalid_branch_assignment_details','rejects unsupported employment status'
);
SELECT throws_ok(
 $$SELECT public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000020',
  'e7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000030',
  'active',current_date,current_date-1
 )$$,
 '22023','invalid_branch_assignment_details','rejects an end date before the start date'
);
SELECT throws_ok(
 $$SELECT public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000021',
  'e7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000030',
  'active',current_date,NULL
 )$$,
 '42501','active_tenant_membership_required','rejects assignment to another tenant without membership'
);
SELECT throws_ok(
 $$SELECT public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000020',
  'e7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000031',
  'active',current_date,NULL
 )$$,
 '22023','job_position_not_active','rejects an inactive job position'
);
SELECT throws_ok(
 $$SELECT public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000020',
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000030',
  'active',current_date,NULL
 )$$,
 'P0002','staff_profile_not_assignable','does not assign a platform Owner as branch staff'
);
SELECT throws_ok(
 $$SELECT public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000022',
  'e7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000030',
  'active',current_date,NULL
 )$$,
 'P0002','branch_not_assignable','rejects a suspended branch'
);

SELECT is(
 (public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000020',
  'e7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000030',
  'active',current_date,NULL
 )->>'changed'),
 'true','creates branch assignment and reports change'
);
SELECT is(
 (SELECT employment_status FROM public.branch_assignments
  WHERE branch_id='e7000000-0000-4000-8000-000000000020'
    AND user_id='e7000000-0000-4000-8000-000000000002'
    AND job_position_id='e7000000-0000-4000-8000-000000000030'),
 'active','persists the active assignment'
);
SELECT ok(
 EXISTS(SELECT 1 FROM public.admin_audit_logs
  WHERE action='erp_assign_job_position'
    AND entity_id=(SELECT id::text FROM public.branch_assignments
      WHERE branch_id='e7000000-0000-4000-8000-000000000020'
        AND user_id='e7000000-0000-4000-8000-000000000002'
        AND job_position_id='e7000000-0000-4000-8000-000000000030')),
 'writes the audit event with the assignment'
);
SELECT is(
 (public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000020',
  'e7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000030',
  'active',current_date,NULL
 )->>'changed'),
 'false','replaying the same assignment is idempotent'
);
SELECT is(
 (SELECT count(*)::integer FROM public.admin_audit_logs WHERE action='erp_assign_job_position'),
 1,'idempotent replay does not duplicate audit events'
);

CREATE OR REPLACE FUNCTION public.test_reject_branch_assignment_audit()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.action='erp_assign_job_position'
     AND current_setting('test.reject_branch_assignment_audit',true)='true' THEN
    RAISE EXCEPTION 'forced branch assignment audit failure';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER test_reject_branch_assignment_audit
BEFORE INSERT ON public.admin_audit_logs
FOR EACH ROW EXECUTE FUNCTION public.test_reject_branch_assignment_audit();
SELECT set_config('test.reject_branch_assignment_audit','true',true);
SELECT throws_ok(
 $$SELECT public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000020',
  'e7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000030',
  'on_leave',current_date,NULL
 )$$,
 'P0001','forced branch assignment audit failure',
 'rolls back assignment changes when the audit insert fails'
);
DROP TRIGGER test_reject_branch_assignment_audit ON public.admin_audit_logs;
SELECT set_config('test.reject_branch_assignment_audit','false',true);
SELECT is(
 (SELECT employment_status FROM public.branch_assignments
  WHERE branch_id='e7000000-0000-4000-8000-000000000020'
    AND user_id='e7000000-0000-4000-8000-000000000002'
    AND job_position_id='e7000000-0000-4000-8000-000000000030'),
 'active','preserves the original assignment after audit failure'
);

UPDATE public.tenant_memberships SET status='revoked'
WHERE tenant_id='e7000000-0000-4000-8000-000000000010'
  AND user_id='e7000000-0000-4000-8000-000000000002';
SELECT is(
 (public.dlice_save_branch_assignment_audited(
  'e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000020',
  'e7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000030',
  'inactive',current_date,NULL
 )->>'changed'),
 'true','allows an existing assignment to be disabled after membership revocation'
);
SELECT is(
 (SELECT employment_status FROM public.branch_assignments
  WHERE branch_id='e7000000-0000-4000-8000-000000000020'
    AND user_id='e7000000-0000-4000-8000-000000000002'
    AND job_position_id='e7000000-0000-4000-8000-000000000030'),
 'inactive','persists inactive status after membership revocation'
);
SELECT is(
 (SELECT count(*)::integer FROM public.admin_audit_logs WHERE action='erp_assign_job_position'),
 2,'records the deactivation audit event'
);

SELECT * FROM finish();
ROLLBACK;
