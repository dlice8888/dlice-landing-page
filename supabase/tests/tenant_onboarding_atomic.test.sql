BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

INSERT INTO auth.users
(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('d3000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','qa.owner.20261121@accounts.dlice.internal','',
 now(),'{"platform_owner":true}'::jsonb,'{}'::jsonb,now(),now()),
('d3000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','qa.member.20261121@accounts.dlice.internal','',
 now(),'{}'::jsonb,'{}'::jsonb,now(),now());

SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

SELECT is(
  public.dlice_bootstrap_initial_owner(
    'd3000000-0000-4000-8000-000000000001','qa.owner.20261121'
  )->>'ok',
  'true',
  'initial owner bootstrap succeeds only with the platform-owner Auth claim'
);
SELECT is(
  (SELECT role FROM public.admin_profiles WHERE user_id='d3000000-0000-4000-8000-000000000001'),
  'owner',
  'initial owner profile is created'
);
SELECT is(
  (SELECT role FROM public.tenant_memberships WHERE user_id='d3000000-0000-4000-8000-000000000001' AND tenant_id=(SELECT id FROM public.tenants WHERE slug='dlice-default')),
  'tenant_owner',
  'initial owner is atomically attached to the default tenant'
);
SELECT ok(
  EXISTS(SELECT 1 FROM public.admin_audit_logs WHERE action='bootstrap_owner' AND entity_id='d3000000-0000-4000-8000-000000000001'),
  'initial owner bootstrap writes audit record'
);
SELECT throws_ok(
  $$SELECT public.dlice_bootstrap_initial_owner('d3000000-0000-4000-8000-000000000001','qa.owner.20261121')$$,
  '23505','owner_already_bootstrapped',
  'second initial owner bootstrap is rejected'
);
SELECT ok(
  NOT has_function_privilege('anon','public.dlice_bootstrap_initial_owner(uuid,text)','EXECUTE'),
  'anon cannot execute initial owner bootstrap'
);
SELECT ok(
  NOT has_function_privilege('authenticated','public.dlice_bootstrap_initial_owner(uuid,text)','EXECUTE'),
  'authenticated cannot execute initial owner bootstrap'
);
SELECT ok(
  has_function_privilege('service_role','public.dlice_bootstrap_initial_owner(uuid,text)','EXECUTE'),
  'service_role can execute initial owner bootstrap'
);

SELECT is(
  public.dlice_create_tenant_with_owner(
    'd3000000-0000-4000-8000-000000000001',
    'qa-tenant-onboarding-20261121',
    'QA Tenant Onboarding',
    'starter'
  )->>'ok',
  'true',
  'platform owner creates a tenant and owner membership atomically'
);
SELECT is(
  (SELECT status FROM public.tenants WHERE slug='qa-tenant-onboarding-20261121'),
  'trial',
  'new tenant starts in trial state'
);
SELECT is(
  (SELECT role FROM public.tenant_memberships
   WHERE tenant_id=(SELECT id FROM public.tenants WHERE slug='qa-tenant-onboarding-20261121')
     AND user_id='d3000000-0000-4000-8000-000000000001'),
  'tenant_owner',
  'creator receives tenant_owner membership'
);
SELECT ok(
  EXISTS(SELECT 1 FROM public.admin_audit_logs
   WHERE action='tenant_created'
     AND entity_id=(SELECT id::text FROM public.tenants WHERE slug='qa-tenant-onboarding-20261121')),
  'tenant creation writes an audit record'
);
SELECT throws_ok(
  $$SELECT public.dlice_create_tenant_with_owner('d3000000-0000-4000-8000-000000000001','qa-tenant-onboarding-20261121','Duplicate tenant','starter')$$,
  '23505',
  'duplicate key value violates unique constraint "tenants_slug_key"',
  'duplicate tenant slug is rejected'
);
SELECT is(
  (SELECT count(*)::integer FROM public.tenants WHERE slug='qa-tenant-onboarding-20261121'),
  1,
  'duplicate tenant creation leaves exactly one tenant row'
);
SELECT throws_ok(
  $$SELECT public.dlice_create_tenant_with_owner('d3000000-0000-4000-8000-000000000001','INVALID SLUG','Invalid tenant','starter')$$,
  '22023','invalid_tenant_details',
  'invalid tenant slug is rejected'
);
SELECT throws_ok(
  $$SELECT public.dlice_create_tenant_with_owner('d3000000-0000-4000-8000-000000000002','qa-unauthorized-tenant-20261121','Unauthorized tenant','starter')$$,
  '42501','active_platform_owner_required',
  'non-owner identity cannot create a tenant'
);
SELECT ok(
  NOT has_function_privilege('authenticated','public.dlice_create_tenant_with_owner(uuid,text,text,text)','EXECUTE'),
  'authenticated cannot execute tenant creation RPC'
);

SELECT * FROM finish();
ROLLBACK;
