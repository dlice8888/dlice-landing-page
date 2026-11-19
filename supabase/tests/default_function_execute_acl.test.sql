BEGIN;
SELECT plan(10);

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
  FROM pg_default_acl d
  JOIN pg_namespace n ON n.oid = d.defaclnamespace
  CROSS JOIN LATERAL aclexplode(d.defaclacl) a
  WHERE n.nspname = 'public'
    AND d.defaclobjtype = 'f'
    AND d.defaclrole = 'postgres'::regrole
    AND a.grantee IN (0, 'anon'::regrole, 'authenticated'::regrole)
    AND a.privilege_type = 'EXECUTE'
), 'postgres default privileges do not grant public RPC EXECUTE to client roles');

CREATE FUNCTION public.dlice_default_acl_test_probe() RETURNS integer
LANGUAGE sql AS 'SELECT 1';
SELECT ok(NOT has_function_privilege('anon', 'public.dlice_default_acl_test_probe()', 'EXECUTE'),
  'new functions do not inherit anon EXECUTE');
SELECT ok(NOT has_function_privilege('authenticated', 'public.dlice_default_acl_test_probe()', 'EXECUTE'),
  'new functions do not inherit authenticated EXECUTE');
SELECT ok(has_function_privilege('service_role', 'public.dlice_default_acl_test_probe()', 'EXECUTE'),
  'new functions retain service_role EXECUTE');
DROP FUNCTION public.dlice_default_acl_test_probe();

SELECT * FROM finish();
ROLLBACK;
