begin;

create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('b1000000-0000-4000-8000-000000000001','authenticated','authenticated','permission-audit-actor@example.invalid','','now','{}'::jsonb,'{}'::jsonb,now(),now()),
  ('b1000000-0000-4000-8000-000000000002','authenticated','authenticated','permission-audit-target@example.invalid','','now','{}'::jsonb,'{}'::jsonb,now(),now()),
  ('b1000000-0000-4000-8000-000000000003','authenticated','authenticated','permission-audit-owner@example.invalid','','now','{}'::jsonb,'{}'::jsonb,now(),now())
on conflict (id) do nothing;

insert into public.admin_profiles (user_id, username, role, display_name, is_active, permissions)
values
  ('b1000000-0000-4000-8000-000000000002','permission_target','sales_admin','Permission Target',true,'["orders"]'::jsonb),
  ('b1000000-0000-4000-8000-000000000003','permission_owner','owner','Permission Owner',true,'["orders"]'::jsonb)
on conflict (user_id) do update set role = excluded.role, permissions = excluded.permissions;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok(
  $$select public.dlice_update_admin_permissions_audited(
    'b1000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000002',
    '["orders","inventory"]'::jsonb
  )$$,
  '42501',
  'service_role_required',
  'rejects non-service callers'
);

select ok(not has_function_privilege(
  'anon',
  'public.dlice_update_admin_permissions_audited(uuid,uuid,jsonb)',
  'execute'
), 'does not grant RPC execution to anon');
select ok(not has_function_privilege(
  'authenticated',
  'public.dlice_update_admin_permissions_audited(uuid,uuid,jsonb)',
  'execute'
), 'does not grant RPC execution to authenticated');

select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

create or replace function public.test_reject_permission_audit()
returns trigger language plpgsql as $$
begin
  if new.action = 'update_admin_permissions'
    and current_setting('test.fail_permission_audit', true) = 'true' then
    raise exception 'forced permission audit failure';
  end if;
  return new;
end;
$$;
create trigger test_reject_permission_audit
before insert on public.admin_audit_logs
for each row execute function public.test_reject_permission_audit();

select set_config('test.fail_permission_audit', 'true', true);
select throws_ok(
  $$select public.dlice_update_admin_permissions_audited(
    'b1000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000002',
    '["orders","inventory"]'::jsonb
  )$$,
  'P0001',
  'forced permission audit failure',
  'fails the permission mutation when its audit insert fails'
);
select is(
  (select permissions from public.admin_profiles where user_id = 'b1000000-0000-4000-8000-000000000002'),
  '["orders"]'::jsonb,
  'rolls back permission changes if audit insertion fails'
);

drop trigger test_reject_permission_audit on public.admin_audit_logs;
select set_config('test.fail_permission_audit', 'false', true);

select is(
  public.dlice_update_admin_permissions_audited(
    'b1000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000002',
    '["inventory","orders","inventory"]'::jsonb
  )->>'changed',
  'true',
  'updates permissions and reports a real change'
);
select is(
  (select permissions from public.admin_profiles where user_id = 'b1000000-0000-4000-8000-000000000002'),
  '["inventory","orders"]'::jsonb,
  'deduplicates and sorts the new permission set'
);
select is(
  (select metadata->'previous_permissions' from public.admin_audit_logs
   where action = 'update_admin_permissions'
     and entity_id = 'b1000000-0000-4000-8000-000000000002'),
  '["orders"]'::jsonb,
  'records the previous permission set'
);
select is(
  (select metadata->'new_permissions' from public.admin_audit_logs
   where action = 'update_admin_permissions'
     and entity_id = 'b1000000-0000-4000-8000-000000000002'),
  '["inventory","orders"]'::jsonb,
  'records the resulting permission set'
);
select throws_ok(
  $$select public.dlice_update_admin_permissions_audited(
    'b1000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000003',
    '["orders"]'::jsonb
  )$$,
  '55000',
  'owner_permissions_are_not_editable',
  'does not permit editing Owner permissions'
);
select throws_ok(
  $$select public.dlice_update_admin_permissions_audited(
    'b1000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000002',
    '["superuser"]'::jsonb
  )$$,
  '22023',
  'invalid_permissions',
  'rejects permissions outside the allowlist'
);

select * from finish();
rollback;
