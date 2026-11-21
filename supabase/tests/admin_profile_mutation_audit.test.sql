BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(18);

INSERT INTO auth.users
(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('d5000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','qa.audit.owner.20261121@accounts.dlice.internal','',now(),'{"platform_owner":true}'::jsonb,'{}'::jsonb,now(),now()),
('d5000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','qa.audit.staff1.20261121@accounts.dlice.internal','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
('d5000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','qa.audit.staff2.20261121@accounts.dlice.internal','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
('d5000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','qa.audit.newstaff.20261121@accounts.dlice.internal','',now(),'{}'::jsonb,'{}'::jsonb,now(),now());

INSERT INTO public.admin_profiles(user_id,username,role,display_name,is_active,permissions)
VALUES
('d5000000-0000-4000-8000-000000000001','qa.audit.owner','owner','QA Owner',true,'["*"]'::jsonb),
('d5000000-0000-4000-8000-000000000002','qa.audit.staff1','sales_admin','QA Staff 1',true,'["orders"]'::jsonb),
('d5000000-0000-4000-8000-000000000003','qa.audit.staff2','branch_worker','QA Staff 2',true,'["orders"]'::jsonb);

SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

SELECT is(
 public.dlice_create_admin_profile_audited(
  'd5000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000004',
  'qa.audit.newstaff','QA New Staff','["staff","orders","orders"]'::jsonb
)->>'changed',
 'true',
 'new staff profile is created and audited atomically'
);
SELECT is(
 (SELECT role FROM public.admin_profiles WHERE user_id='d5000000-0000-4000-8000-000000000004'),
 'sales_admin',
 'new staff profile has the expected least-privilege role'
);
SELECT is(
 (SELECT permissions FROM public.admin_profiles WHERE user_id='d5000000-0000-4000-8000-000000000004'),
 '["orders","staff"]'::jsonb,
 'new staff permissions are normalized and deduplicated'
);
SELECT ok(
 EXISTS(SELECT 1 FROM public.admin_audit_logs WHERE action='create_admin_account' AND entity_id='d5000000-0000-4000-8000-000000000004'),
 'new staff creation writes audit in the same transaction'
);
SELECT is(
 public.dlice_create_admin_profile_audited(
  'd5000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000004',
  'qa.audit.newstaff','QA New Staff','["orders","staff"]'::jsonb
)->>'changed',
 'false',
 'retrying the same staff creation is idempotent'
);
SELECT is(
 (SELECT count(*)::integer FROM public.admin_audit_logs WHERE action='create_admin_account' AND entity_id='d5000000-0000-4000-8000-000000000004'),
 1,
 'idempotent create retry does not duplicate audit rows'
);
SELECT throws_ok(
 $$SELECT public.dlice_create_admin_profile_audited('d5000000-0000-4000-8000-000000000001','d5000000-0000-4000-8000-000000000004','qa.audit.changed','Different','["orders"]'::jsonb)$$,
 '23505','admin_profile_conflict',
 'same Auth user cannot be silently rebound to a different profile'
);
SELECT throws_ok(
 $$SELECT public.dlice_create_admin_profile_audited('d5000000-0000-4000-8000-000000000001','d5000000-0000-4000-8000-000000000004','qa.audit.newstaff','QA New Staff','["root"]'::jsonb)$$,
 '22023','invalid_permissions',
 'unknown permission cannot be assigned during staff creation'
);

SELECT is(
 public.dlice_update_admin_profile_role_audited(
  'd5000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000003',
  'sales_admin'
 )->>'changed',
 'true',
 'staff role change succeeds atomically'
);
SELECT ok(
 EXISTS(SELECT 1 FROM public.admin_audit_logs WHERE action='set_staff_profile_role' AND entity_id='d5000000-0000-4000-8000-000000000003' AND metadata->>'previous_role'='branch_worker' AND metadata->>'new_role'='sales_admin'),
 'staff role change writes before/after audit'
);
SELECT throws_ok(
 $$SELECT public.dlice_update_admin_profile_role_audited('d5000000-0000-4000-8000-000000000001','d5000000-0000-4000-8000-000000000002','branch_worker')$$,
 '23514','branch_assignment_required',
 'branch worker role requires an active branch assignment'
);
SELECT throws_ok(
 $$SELECT public.dlice_update_admin_profile_role_audited('d5000000-0000-4000-8000-000000000001','d5000000-0000-4000-8000-000000000001','sales_admin')$$,
 '55000','owner_role_is_not_editable',
 'owner profile role cannot be changed'
);
SELECT throws_ok(
 $$SELECT public.dlice_update_admin_profile_role_audited('d5000000-0000-4000-8000-000000000001','d5000000-0000-4000-8000-000000000002','root')$$,
 '22023','invalid_admin_role_change',
 'unknown admin profile role is rejected'
);

SELECT is(
 public.dlice_set_admin_profile_active_audited(
  'd5000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000002',
  false
 )->>'changed',
 'true',
 'staff active status changes atomically'
);
SELECT ok(
 EXISTS(SELECT 1 FROM public.admin_audit_logs WHERE action='set_admin_active_status' AND entity_id='d5000000-0000-4000-8000-000000000002' AND metadata->>'previous_is_active'='true' AND metadata->>'new_is_active'='false'),
 'staff active status change writes before/after audit'
);
SELECT throws_ok(
 $$SELECT public.dlice_set_admin_profile_active_audited('d5000000-0000-4000-8000-000000000001','d5000000-0000-4000-8000-000000000001',false)$$,
 '55000','owner_active_state_is_not_editable',
 'owner active state cannot be changed through staff action'
);
SELECT ok(
 NOT has_function_privilege('authenticated','public.dlice_set_admin_profile_active_audited(uuid,uuid,boolean)','EXECUTE'),
 'authenticated cannot execute staff active status RPC'
);

SELECT * FROM finish();
ROLLBACK;
