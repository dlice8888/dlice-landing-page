begin;

create extension if not exists pgtap with schema extensions;

select plan(6);
select set_config('request.jwt.claim.role', 'authenticated', true);

select ok(
  not has_function_privilege(
    'anon',
    'public.dlice_get_command_center_summary(uuid[],date,date)',
    'execute'
  ),
  'does not grant RPC execution to anon'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.dlice_get_command_center_summary(uuid[],date,date)',
    'execute'
  ),
  'does not grant RPC execution to authenticated'
);

select set_config('request.jwt.claim.role', 'service_role', true);

select is(
  (public.dlice_get_command_center_summary(
    array[(select id from public.branches where code = 'DLC-HQ')],
    current_date,
    current_date
  )->'branch_summaries'->0->>'id'),
  (select id::text from public.branches where code = 'DLC-HQ'),
  'computes operational metrics for an existing branch'
);

update public.branches set timezone = 'Unsupported/Zone' where code = 'DLC-HQ';

select throws_ok(
  $$select public.dlice_get_command_center_summary(
    array[(select id from public.branches where code = 'DLC-HQ')],
    current_date,
    current_date
  )$$,
  '22023',
  'unsupported_branch_timezone',
  'rejects branches with unsupported timezone configuration'
);

select is(
  public.dlice_get_command_center_summary('{}'::uuid[], date '2026-01-01', date '2026-01-01')->'branch_summaries',
  '[]'::jsonb,
  'returns no branch data for an empty authorized branch scope'
);

select throws_ok(
  $$select public.dlice_get_command_center_summary('{}'::uuid[], date '2026-01-01', date '2026-04-04')$$,
  '22023',
  'invalid_reporting_period',
  'rejects periods longer than 93 calendar days'
);

select * from finish();
rollback;
