begin;

select plan(7);

select ok(
  (select count(*) = 5
   from pg_catalog.pg_class c
   join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'r'
     and c.relname = any(array[
       'hr_payroll_payment_finance_mappings',
       'hr_payroll_payment_finance_clearings',
       'hr_payroll_bank_statement_lines',
       'hr_payroll_payment_bank_reconciliations',
       'hr_payroll_payment_reversal_exceptions'
     ])),
  'all five payroll Finance clearing evidence tables exist'
);

select ok(
  (select count(*) = 5
   from pg_catalog.pg_class c
   join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = any(array[
       'hr_payroll_payment_finance_mappings',
       'hr_payroll_payment_finance_clearings',
       'hr_payroll_bank_statement_lines',
       'hr_payroll_payment_bank_reconciliations',
       'hr_payroll_payment_reversal_exceptions'
     ])
     and c.relrowsecurity),
  'RLS is enabled on every payroll Finance clearing evidence table'
);

select ok(
  (select bool_and(
      not has_table_privilege(r.rolname, format('public.%I', t.table_name), 'SELECT')
    )
   from (values ('anon'), ('authenticated')) r(rolname)
   cross join (values
     ('hr_payroll_payment_finance_mappings'),
     ('hr_payroll_payment_finance_clearings'),
     ('hr_payroll_bank_statement_lines'),
     ('hr_payroll_payment_bank_reconciliations'),
     ('hr_payroll_payment_reversal_exceptions')
   ) t(table_name)),
  'anonymous and authenticated clients have no direct table reads'
);

select ok(
  has_table_privilege('service_role', 'public.hr_payroll_payment_finance_mappings', 'SELECT')
  and has_table_privilege('service_role', 'public.hr_payroll_payment_finance_clearings', 'INSERT')
  and not has_table_privilege('service_role', 'public.hr_payroll_bank_statement_lines', 'UPDATE')
  and not has_table_privilege('service_role', 'public.hr_payroll_bank_statement_lines', 'DELETE')
  and not has_table_privilege('service_role', 'public.hr_payroll_payment_bank_reconciliations', 'UPDATE')
  and not has_table_privilege('service_role', 'public.hr_payroll_payment_bank_reconciliations', 'DELETE')
  and not has_table_privilege('service_role', 'public.hr_payroll_payment_reversal_exceptions', 'UPDATE')
  and not has_table_privilege('service_role', 'public.hr_payroll_payment_reversal_exceptions', 'DELETE'),
  'service role can operate clearing but cannot rewrite append-only bank and reversal evidence'
);

select ok(
  (select count(*) = 6
   from pg_catalog.pg_proc p
   join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = any(array[
       'hr_approve_payroll_payment_finance_mapping',
       'hr_post_payroll_payment_finance_clearing',
       'hr_import_payroll_bank_statement_line',
       'hr_match_payroll_payment_bank_statement',
       'hr_reconcile_payroll_payment_bank_batch',
       'hr_mark_payroll_payment_reversal_exception'
     ])),
  'all six Finance RPC entry points exist'
);

select ok(
  (select bool_and(not has_function_privilege('authenticated', p.oid, 'EXECUTE'))
   from pg_catalog.pg_proc p
   join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = any(array[
       'hr_approve_payroll_payment_finance_mapping',
       'hr_post_payroll_payment_finance_clearing',
       'hr_import_payroll_bank_statement_line',
       'hr_match_payroll_payment_bank_statement',
       'hr_reconcile_payroll_payment_bank_batch',
       'hr_mark_payroll_payment_reversal_exception'
     ])),
  'authenticated clients cannot execute privileged Finance RPCs'
);

select ok(
  (select bool_and(has_function_privilege('service_role', p.oid, 'EXECUTE'))
   from pg_catalog.pg_proc p
   join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = any(array[
       'hr_approve_payroll_payment_finance_mapping',
       'hr_post_payroll_payment_finance_clearing',
       'hr_import_payroll_bank_statement_line',
       'hr_match_payroll_payment_bank_statement',
       'hr_reconcile_payroll_payment_bank_batch',
       'hr_mark_payroll_payment_reversal_exception'
     ])),
  'service role can execute the six scoped Finance RPCs'
);

select * from finish();
rollback;
