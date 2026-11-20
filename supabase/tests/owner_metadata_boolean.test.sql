begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

select ok('true'::jsonb = 'true'::jsonb, 'JSON boolean true compares as boolean true');
select ok(not ('"true"'::jsonb = 'true'::jsonb), 'JSON string "true" is not boolean true');

select ok(
  position('raw_app_meta_data->''platform_owner'' = ''true''::jsonb' in
    pg_get_functiondef('public.dlice_bootstrap_initial_owner(uuid,text)'::regprocedure)) > 0,
  'initial owner bootstrap requires boolean app_metadata true'
);
select ok(
  position('raw_app_meta_data->''platform_owner'' = ''true''::jsonb' in
    pg_get_functiondef('public.dlice_create_tenant_with_owner(uuid,text,text,text)'::regprocedure)) > 0,
  'tenant creation requires boolean app_metadata true'
);
select ok(
  position('auth.jwt()' in pg_get_functiondef('public.dlice_bootstrap_initial_owner(uuid,text)'::regprocedure)) > 0
  and position('auth.role()' in pg_get_functiondef('public.dlice_bootstrap_initial_owner(uuid,text)'::regprocedure)) = 0,
  'owner bootstrap checks service role through auth.jwt()'
);
select ok(
  position('auth.jwt()' in pg_get_functiondef('public.dlice_create_tenant_with_owner(uuid,text,text,text)'::regprocedure)) > 0
  and position('auth.role()' in pg_get_functiondef('public.dlice_create_tenant_with_owner(uuid,text,text,text)'::regprocedure)) = 0,
  'tenant creation checks service role through auth.jwt()'
);
select ok(
  position('auth.jwt()' in pg_get_functiondef('public.dlice_manage_branch_checklist(text,uuid,uuid,date,text,jsonb,uuid,text,text,text,integer)'::regprocedure)) > 0
  and position('auth.role()' in pg_get_functiondef('public.dlice_manage_branch_checklist(text,uuid,uuid,date,text,jsonb,uuid,text,text,text,integer)'::regprocedure)) = 0,
  'branch checklist checks service role through auth.jwt()'
);
select ok(
  not has_function_privilege('anon','public.dlice_bootstrap_initial_owner(uuid,text)','execute')
  and not has_function_privilege('authenticated','public.dlice_bootstrap_initial_owner(uuid,text)','execute')
  and has_function_privilege('service_role','public.dlice_bootstrap_initial_owner(uuid,text)','execute'),
  'owner bootstrap RPC remains service-role-only'
);
select * from finish();
rollback;
