BEGIN;
SELECT plan(12);

SELECT ok(NOT has_function_privilege('anon', 'public.erp_guard_journal_period()', 'EXECUTE'),
  'anon cannot execute journal-period trigger function');
SELECT ok(NOT has_function_privilege('authenticated', 'public.erp_guard_journal_period()', 'EXECUTE'),
  'authenticated cannot execute journal-period trigger function');
SELECT ok(NOT has_function_privilege('anon', 'public.erp_guard_refund_amount()', 'EXECUTE'),
  'anon cannot execute refund-guard trigger function');
SELECT ok(NOT has_function_privilege('authenticated', 'public.erp_guard_refund_amount()', 'EXECUTE'),
  'authenticated cannot execute refund-guard trigger function');
SELECT ok(NOT has_function_privilege('anon', 'public.set_updated_at()', 'EXECUTE'),
  'anon cannot execute updated-at trigger function');
SELECT ok(NOT has_function_privilege('authenticated', 'public.set_updated_at()', 'EXECUTE'),
  'authenticated cannot execute updated-at trigger function');

SELECT ok(NOT EXISTS (
  SELECT 1
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
), 'anon cannot execute any public-schema RPC');

SELECT ok(NOT EXISTS (
  SELECT 1
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
), 'authenticated cannot execute any public-schema RPC');

-- Emit the exact callable functions missing the service-role grant when the
-- aggregate assertion fails; this keeps ACL failures actionable without weakening it.
SELECT diag('Callable public functions missing service_role EXECUTE: ' || coalesce((
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text)
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prorettype <> 'trigger'::regtype
    -- The legacy no-actor overload is deliberately disabled; only the audited overload is callable.
    AND p.oid <> to_regprocedure('public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz)')
    AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
), '(none)'));

-- Trigger-returning functions are invoked by PostgreSQL through their trigger
-- bindings, not directly by service_role/PostgREST. Keep their EXECUTE ACL
-- revoked; require service_role EXECUTE only for callable public RPCs.
SELECT ok(NOT EXISTS (
  SELECT 1
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prorettype <> 'trigger'::regtype
    -- The legacy no-actor overload is intentionally disabled and tested below.
    AND p.oid <> to_regprocedure('public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz)')
    AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
), 'service_role retains EXECUTE on all callable public-schema RPCs');

SELECT ok(
  NOT has_function_privilege('service_role', 'public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz)', 'EXECUTE'),
  'legacy SaaS usage RPC without actor/audit context is disabled for every API role'
);

SELECT ok(
  NOT has_function_privilege('service_role', 'public.prevent_pos_sale_receipt_mutation()', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.prevent_pos_sale_receipt_mutation()', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'public.prevent_pos_sale_receipt_mutation()', 'EXECUTE'),
  'immutable receipt trigger function is not directly executable by API roles');

SELECT ok(NOT EXISTS (
  SELECT 1
  FROM pg_default_acl d
  JOIN pg_namespace n ON n.oid = d.defaclnamespace
  CROSS JOIN LATERAL aclexplode(d.defaclacl) a
  WHERE n.nspname = 'public'
    AND d.defaclobjtype = 'f'
    AND d.defaclrole = 'postgres'::regrole
    AND a.grantee IN (0, 'anon'::regrole, 'authenticated'::regrole)
    AND a.privilege_type = 'EXECUTE'
), 'postgres default privileges do not grant public RPC EXECUTE to client roles');

SELECT * FROM finish();
ROLLBACK;
