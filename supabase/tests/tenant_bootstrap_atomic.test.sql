BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(23);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT throws_ok(
  $$SELECT public.dlice_bootstrap_initial_owner('b0000000-0000-4000-8000-000000000011', 'bootstrap-test')$$,
  '42501',
  'service_role_required',
  'rejects non-service owner bootstrap callers'
);
SELECT ok(
  NOT has_function_privilege('anon', 'public.dlice_bootstrap_initial_owner(uuid,text)', 'execute'),
  'does not grant owner bootstrap execution to anon'
);
SELECT ok(
  NOT has_function_privilege('authenticated', 'public.dlice_bootstrap_initial_owner(uuid,text)', 'execute'),
  'does not grant owner bootstrap execution to authenticated users'
);
SELECT throws_ok(
  $$SELECT public.dlice_create_tenant_with_owner('b0000000-0000-4000-8000-000000000011', 'bootstrap-test', 'Bootstrap Test')$$,
  '42501',
  'service_role_required',
  'rejects non-service tenant bootstrap callers'
);
SELECT ok(
  NOT has_function_privilege('anon', 'public.dlice_create_tenant_with_owner(uuid,text,text,text)', 'execute'),
  'does not grant tenant bootstrap execution to anon'
);
SELECT ok(
  NOT has_function_privilege('authenticated', 'public.dlice_create_tenant_with_owner(uuid,text,text,text)', 'execute'),
  'does not grant tenant bootstrap execution to authenticated users'
);

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('b0000000-0000-4000-8000-000000000011', 'authenticated', 'authenticated', 'bootstrap-test@accounts.dlice.internal', '', now(), '{"platform_owner":true}'::jsonb, '{}'::jsonb, now(), now()),
  ('b0000000-0000-4000-8000-000000000012', 'authenticated', 'authenticated', 'second-owner@accounts.dlice.internal', '', now(), '{"platform_owner":true}'::jsonb, '{}'::jsonb, now(), now()),
  ('b0000000-0000-4000-8000-000000000013', 'authenticated', 'authenticated', 'legacy-owner@accounts.dlice.internal', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now())
ON CONFLICT (id) DO NOTHING;

SELECT set_config('request.jwt.claim.role', 'service_role', true);

CREATE OR REPLACE FUNCTION public.test_reject_bootstrap_audit()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('test.fail_bootstrap_audit', true) = NEW.action THEN
    RAISE EXCEPTION 'forced bootstrap audit failure';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER test_reject_bootstrap_audit
BEFORE INSERT ON public.admin_audit_logs
FOR EACH ROW EXECUTE FUNCTION public.test_reject_bootstrap_audit();

SELECT set_config('test.fail_bootstrap_audit', 'bootstrap_owner', true);
SELECT throws_ok(
  $$SELECT public.dlice_bootstrap_initial_owner('b0000000-0000-4000-8000-000000000011', 'bootstrap-test')$$,
  'P0001',
  'forced bootstrap audit failure',
  'fails owner bootstrap when audit insertion fails'
);
SELECT is(
  (SELECT count(*)::integer FROM public.admin_profiles WHERE user_id = 'b0000000-0000-4000-8000-000000000011'),
  0,
  'rolls back owner profile when audit insertion fails'
);
SELECT is(
  (SELECT count(*)::integer FROM public.tenant_memberships WHERE user_id = 'b0000000-0000-4000-8000-000000000011'),
  0,
  'rolls back default tenant membership when audit insertion fails'
);
SELECT is(
  (SELECT count(*)::integer FROM public.admin_audit_logs
   WHERE actor_user_id = 'b0000000-0000-4000-8000-000000000011'
     AND action = 'bootstrap_owner'),
  0,
  'does not leave an audit event when owner bootstrap rolls back'
);

SELECT set_config('test.fail_bootstrap_audit', '', true);
SELECT is(
  public.dlice_bootstrap_initial_owner('b0000000-0000-4000-8000-000000000011', 'bootstrap-test')->>'ok',
  'true',
  'creates initial owner after a successful atomic bootstrap'
);
SELECT is(
  (SELECT role FROM public.admin_profiles WHERE user_id = 'b0000000-0000-4000-8000-000000000011'),
  'owner',
  'creates the platform owner profile'
);
SELECT is(
  (SELECT role || ':' || permissions::text || ':' || status
   FROM public.tenant_memberships
   WHERE user_id = 'b0000000-0000-4000-8000-000000000011'
     AND tenant_id = (SELECT id FROM public.tenants WHERE slug = 'dlice-default')),
  'tenant_owner:["*"]:active',
  'creates active tenant-scoped owner permissions'
);
SELECT is(
  (SELECT count(*)::integer FROM public.admin_audit_logs
   WHERE actor_user_id = 'b0000000-0000-4000-8000-000000000011'
     AND action = 'bootstrap_owner'),
  1,
  'records the owner bootstrap audit event'
);
SELECT throws_ok(
  $$SELECT public.dlice_bootstrap_initial_owner('b0000000-0000-4000-8000-000000000012', 'second-owner')$$,
  '23505',
  'owner_already_bootstrapped',
  'rejects a second initial owner bootstrap'
);

SELECT set_config('test.fail_bootstrap_audit', 'tenant_created', true);
SELECT throws_ok(
  $$SELECT public.dlice_create_tenant_with_owner(
    'b0000000-0000-4000-8000-000000000011', 'atomic-bootstrap-test', 'Atomic Bootstrap Test'
  )$$,
  'P0001',
  'forced bootstrap audit failure',
  'fails tenant creation when audit insertion fails'
);
SELECT is(
  (SELECT count(*)::integer FROM public.tenants WHERE slug = 'atomic-bootstrap-test'),
  0,
  'rolls back tenant creation when audit insertion fails'
);
SELECT is(
  (SELECT count(*)::integer FROM public.tenant_memberships
   WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'atomic-bootstrap-test')),
  0,
  'rolls back tenant membership when audit insertion fails'
);

SELECT set_config('test.fail_bootstrap_audit', '', true);
SELECT is(
  public.dlice_create_tenant_with_owner(
    'b0000000-0000-4000-8000-000000000011', 'atomic-bootstrap-test', 'Atomic Bootstrap Test'
  )->'tenant'->>'slug',
  'atomic-bootstrap-test',
  'creates tenant and owner membership successfully'
);
SELECT is(
  (SELECT role || ':' || permissions::text || ':' || status
   FROM public.tenant_memberships
   WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'atomic-bootstrap-test')
     AND user_id = 'b0000000-0000-4000-8000-000000000011'),
  'tenant_owner:["*"]:active',
  'scopes the new tenant owner permissions to its membership'
);
SELECT is(
  (SELECT count(*)::integer FROM public.admin_audit_logs
   WHERE actor_user_id = 'b0000000-0000-4000-8000-000000000011'
     AND action = 'tenant_created'
     AND entity_id = (SELECT id::text FROM public.tenants WHERE slug = 'atomic-bootstrap-test')),
  1,
  'records one audit event for the created tenant'
);
INSERT INTO public.admin_profiles (
  user_id, username, role, display_name, is_active, permissions
) VALUES (
  'b0000000-0000-4000-8000-000000000013', 'legacy-owner', 'owner',
  'Legacy owner without platform metadata', true, '["*"]'::jsonb
);
SELECT throws_ok(
  $$SELECT public.dlice_create_tenant_with_owner(
    'b0000000-0000-4000-8000-000000000013', 'unauthorized-bootstrap-test', 'Unauthorized Bootstrap Test'
  )$$,
  '42501',
  'active_platform_owner_required',
  'rejects tenant bootstrap without platform-owner Auth metadata'
);
SELECT is(
  (SELECT count(*)::integer FROM public.tenants WHERE slug = 'unauthorized-bootstrap-test'),
  0,
  'does not create a tenant for a non-owner actor'
);

DROP TRIGGER test_reject_bootstrap_audit ON public.admin_audit_logs;
DROP FUNCTION public.test_reject_bootstrap_audit();

SELECT * FROM finish();
ROLLBACK;
