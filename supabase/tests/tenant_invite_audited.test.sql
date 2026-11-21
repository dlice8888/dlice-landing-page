BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(11);

INSERT INTO auth.users
(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('d6000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','qa.invite.owner.20261121@accounts.dlice.internal','',
 now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
('d6000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','qa.invite.member.20261121@accounts.dlice.internal','',
 now(),'{}'::jsonb,'{}'::jsonb,now(),now());

INSERT INTO public.tenants(id,slug,legal_name,status)
VALUES('d6000000-0000-4000-8000-000000000003','qa-invite-audited-20261121','QA Invite Audited','trial')
ON CONFLICT(id) DO NOTHING;

INSERT INTO public.tenant_memberships(tenant_id,user_id,role,permissions,status)
VALUES
('d6000000-0000-4000-8000-000000000003','d6000000-0000-4000-8000-000000000001','tenant_owner','["*"]'::jsonb,'active'),
('d6000000-0000-4000-8000-000000000003','d6000000-0000-4000-8000-000000000002','cashier','["pos"]'::jsonb,'active')
ON CONFLICT(tenant_id,user_id) DO UPDATE SET role=excluded.role,permissions=excluded.permissions,status='active';

CREATE TEMP TABLE invite_test_args ON COMMIT DROP AS
SELECT date_trunc('minute',now()) + interval '7 days' AS expires_at;

SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

SELECT is(
 (public.dlice_create_tenant_invite_atomic(
  'd6000000-0000-4000-8000-000000000001',
  'd6000000-0000-4000-8000-000000000003',
  'Invitee@Example.Test','cashier',repeat('a',64),
  (SELECT expires_at FROM invite_test_args)
 )->>'ok'),
 'true',
 'active tenant owner can issue an invitation'
);

SELECT is(
 (SELECT status FROM public.tenant_invites WHERE token_hash=repeat('a',64)),
 'pending',
 'new invitation starts pending'
);

SELECT is(
 (SELECT email FROM public.tenant_invites WHERE token_hash=repeat('a',64)),
 'invitee@example.test',
 'invitation email is normalized to lowercase'
);

SELECT ok(
 EXISTS(
  SELECT 1 FROM public.admin_audit_logs
  WHERE action='tenant_member_invited'
    AND entity_id=(SELECT id::text FROM public.tenant_invites WHERE token_hash=repeat('a',64))
 ),
 'invitation and audit record are committed together'
);

SELECT is(
 (public.dlice_create_tenant_invite_atomic(
  'd6000000-0000-4000-8000-000000000001',
  'd6000000-0000-4000-8000-000000000003',
  'invitee@example.test','cashier',repeat('a',64),
  (SELECT expires_at FROM invite_test_args)
 )->>'replayed'),
 'true',
 'same invitation request is idempotent'
);

SELECT throws_ok(
 $$SELECT public.dlice_create_tenant_invite_atomic(
  'd6000000-0000-4000-8000-000000000001',
  'd6000000-0000-4000-8000-000000000003',
  'different@example.test','cashier',repeat('a',64),
  (SELECT expires_at FROM invite_test_args)
 )$$,
 '23505','tenant_invite_token_conflict',
 'same token cannot be rebound to a different invitation payload'
);

SELECT throws_ok(
 $$SELECT public.dlice_create_tenant_invite_atomic(
  'd6000000-0000-4000-8000-000000000002',
  'd6000000-0000-4000-8000-000000000003',
  'other@example.test','cashier',repeat('b',64),
  (SELECT expires_at FROM invite_test_args)
 )$$,
 '42501','tenant_invite_permission_denied',
 'ordinary tenant member cannot issue invitations'
);

SELECT throws_ok(
 $$SELECT public.dlice_create_tenant_invite_atomic(
  'd6000000-0000-4000-8000-000000000001',
  'd6000000-0000-4000-8000-000000000003',
  'not-an-email','cashier',repeat('c',64),
  (SELECT expires_at FROM invite_test_args)
 )$$,
 '22023','invalid_tenant_invite',
 'malformed email is rejected'
);

SELECT throws_ok(
 $$SELECT public.dlice_create_tenant_invite_atomic(
  'd6000000-0000-4000-8000-000000000001',
  'd6000000-0000-4000-8000-000000000003',
  'valid@example.test','root',repeat('d',64),
  (SELECT expires_at FROM invite_test_args)
 )$$,
 '22023','invalid_tenant_invite_details',
 'unsupported tenant role is rejected'
);

SELECT throws_ok(
 $$SELECT public.dlice_create_tenant_invite_atomic(
  'd6000000-0000-4000-8000-000000000001',
  'd6000000-0000-4000-8000-000000000003',
  'valid@example.test','viewer',repeat('e',64),
  now() + interval '8 days'
 )$$,
 '22023','invalid_tenant_invite_details',
 'invitation expiry cannot exceed seven days'
);

SELECT ok(
 NOT has_function_privilege('authenticated','public.dlice_create_tenant_invite_atomic(uuid,uuid,text,text,text,timestamptz)','EXECUTE')
 AND has_function_privilege('service_role','public.dlice_create_tenant_invite_atomic(uuid,uuid,text,text,text,timestamptz)','EXECUTE'),
 'invitation RPC is service-role only'
);

SELECT * FROM finish();
ROLLBACK;
