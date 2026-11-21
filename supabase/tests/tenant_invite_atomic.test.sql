BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(15);

INSERT INTO auth.users
(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('d4000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','qa.owner.20261121@accounts.dlice.internal','',
 now(),'{"platform_owner":true}'::jsonb,'{}'::jsonb,now(),now()),
('d4000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','invitee@example.test','',
 now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
('d4000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','outsider@example.test','',
 now(),'{}'::jsonb,'{}'::jsonb,now(),now());

SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT public.dlice_bootstrap_initial_owner(
 'd4000000-0000-4000-8000-000000000001','qa.owner.20261121'
);

SELECT is(
 (public.dlice_create_tenant_invite_atomic(
  'd4000000-0000-4000-8000-000000000001',
  (SELECT id FROM public.tenants WHERE slug='dlice-default'),
  'invitee@example.test','cashier',
  repeat('a',64),now()+interval '7 days'
 )->>'ok'),
 'true',
 'tenant owner can create a valid invite'
);
SELECT is(
 (SELECT status FROM public.tenant_invites WHERE token_hash=repeat('a',64)),
 'pending',
 'invite starts pending'
);
SELECT ok(
 EXISTS(SELECT 1 FROM public.admin_audit_logs WHERE action='tenant_member_invited' AND entity_id=(SELECT id::text FROM public.tenant_invites WHERE token_hash=repeat('a',64))),
 'invite and audit are committed together'
);
SELECT throws_ok(
 $$SELECT public.dlice_create_tenant_invite_atomic(
  'd4000000-0000-4000-8000-000000000003',
  (SELECT id FROM public.tenants WHERE slug='dlice-default'),
  'other@example.test','cashier',repeat('b',64),now()+interval '7 days'
 )$$,
 '42501','tenant_invite_permission_denied',
 'non-member cannot issue tenant invite'
);
SELECT throws_ok(
 $$SELECT public.dlice_accept_tenant_invite_atomic(
  'd4000000-0000-4000-8000-000000000002','wrong@example.test',repeat('a',64)
 )$$,
 '42501','tenant_invite_email_mismatch',
 'invite cannot be accepted by a different email'
);
SELECT is(
 (public.dlice_accept_tenant_invite_atomic(
  'd4000000-0000-4000-8000-000000000002','invitee@example.test',repeat('a',64)
 )->'invite'->>'status'),
 'accepted',
 'invite acceptance succeeds for matching email'
);
SELECT is(
 (SELECT status FROM public.tenant_memberships
  WHERE tenant_id=(SELECT id FROM public.tenants WHERE slug='dlice-default')
    AND user_id='d4000000-0000-4000-8000-000000000002'),
 'active',
 'acceptance creates an active tenant membership'
);
SELECT is(
 (SELECT role FROM public.tenant_memberships
  WHERE tenant_id=(SELECT id FROM public.tenants WHERE slug='dlice-default')
    AND user_id='d4000000-0000-4000-8000-000000000002'),
 'cashier',
 'membership receives the invited role'
);
SELECT is(
 (SELECT status FROM public.tenant_invites WHERE token_hash=repeat('a',64)),
 'accepted',
 'invite is consumed exactly once'
);
SELECT ok(
 EXISTS(SELECT 1 FROM public.admin_audit_logs WHERE action='tenant_invite_accepted' AND entity_id=(SELECT id::text FROM public.tenant_invites WHERE token_hash=repeat('a',64))),
 'membership activation and acceptance audit are committed together'
);
SELECT throws_ok(
 $$SELECT public.dlice_accept_tenant_invite_atomic(
  'd4000000-0000-4000-8000-000000000002','invitee@example.test',repeat('a',64)
 )$$,
 'P0002','tenant_invite_not_pending',
 'accepted invite cannot be replayed'
);
SELECT is(
 (public.dlice_create_tenant_invite_atomic(
  'd4000000-0000-4000-8000-000000000001',
  (SELECT id FROM public.tenants WHERE slug='dlice-default'),
  'expired@example.test','viewer',
  repeat('c',64),now()+interval '7 days'
 )->>'ok'),
 'true',
 'second invite can be issued for expiry test'
);
UPDATE public.tenant_invites SET expires_at=now()-interval '1 second' WHERE token_hash=repeat('c',64);
SELECT is(
 (public.dlice_accept_tenant_invite_atomic(
  'd4000000-0000-4000-8000-000000000003','expired@example.test',repeat('c',64)
 )->>'status'),
 'expired',
 'expired invite is marked expired and not accepted'
);
SELECT is(
 (SELECT status FROM public.tenant_invites WHERE token_hash=repeat('c',64)),
 'expired',
 'expired invite state is persisted'
);
SELECT ok(
 NOT has_function_privilege('authenticated','public.dlice_accept_tenant_invite_atomic(uuid,text,text)','EXECUTE')
 AND has_function_privilege('service_role','public.dlice_accept_tenant_invite_atomic(uuid,text,text)','EXECUTE'),
 'invite acceptance RPC is service-role only'
);

SELECT * FROM finish();
ROLLBACK;
