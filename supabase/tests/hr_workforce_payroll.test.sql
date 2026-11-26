-- Disposable pgTAP contracts for HR workforce, payroll and Finance posting.
begin;
select plan(57);

select ok(to_regclass('public.hr_shift_schedules') is not null,'hr_shift_schedules table exists');
select ok(to_regclass('public.hr_attendance_events') is not null,'hr_attendance_events table exists');
select ok(to_regclass('public.hr_leave_requests') is not null,'hr_leave_requests table exists');
select ok(to_regclass('public.hr_timesheets') is not null,'hr_timesheets table exists');
select ok(to_regclass('public.hr_payroll_runs') is not null,'hr_payroll_runs table exists');
select ok(to_regclass('public.hr_payroll_lines') is not null,'hr_payroll_lines table exists');
select ok(to_regclass('public.hr_compensation_rates') is not null,'hr_compensation_rates table exists');
select ok(to_regclass('public.hr_employee_records') is not null,'hr_employee_records table exists');
select ok(to_regclass('public.hr_employee_lifecycle_events') is not null,'hr_employee_lifecycle_events table exists');
select ok(to_regclass('public.hr_payroll_finance_account_mappings') is not null,'hr_payroll_finance_account_mappings table exists');
select ok(to_regclass('public.hr_payroll_finance_postings') is not null,'hr_payroll_finance_postings table exists');
select ok(to_regclass('public.hr_payroll_payment_provider_configs') is not null,'hr_payroll_payment_provider_configs table exists');
select ok(to_regclass('public.hr_payroll_beneficiary_profiles') is not null,'hr_payroll_beneficiary_profiles table exists');
select ok(to_regclass('public.hr_payroll_payment_batches') is not null,'hr_payroll_payment_batches table exists');
select ok(to_regclass('public.hr_payroll_payment_items') is not null,'hr_payroll_payment_items table exists');
select ok(to_regclass('public.hr_payroll_provider_events') is not null,'hr_payroll_provider_events table exists');
select ok(to_regclass('public.hr_payroll_payment_reconciliations') is not null,'hr_payroll_payment_reconciliations table exists');

select ok(to_regprocedure('public.hr_audit_row_change()') is not null,'hr_audit_row_change RPC/trigger function exists');
select ok(to_regprocedure('public.hr_record_attendance(uuid,uuid,uuid,text,text,text,text,uuid)') is not null,'hr_record_attendance RPC/trigger function exists');
select ok(to_regprocedure('public.hr_create_leave_request(uuid,uuid,uuid,text,date,date,uuid,text,uuid)') is not null,'hr_create_leave_request RPC/trigger function exists');
select ok(to_regprocedure('public.hr_confirm_leave_coverage(uuid,uuid,boolean,text)') is not null,'hr_confirm_leave_coverage RPC/trigger function exists');
select ok(to_regprocedure('public.hr_review_leave_request(uuid,uuid,boolean,text)') is not null,'hr_review_leave_request RPC/trigger function exists');
select ok(to_regprocedure('public.hr_create_shift_schedule(uuid,uuid,uuid,uuid,timestamptz,timestamptz,uuid,text)') is not null,'hr_create_shift_schedule RPC/trigger function exists');
select ok(to_regprocedure('public.hr_generate_timesheet(uuid,uuid,uuid,date,date,uuid)') is not null,'hr_generate_timesheet RPC/trigger function exists');
select ok(to_regprocedure('public.hr_submit_timesheet(uuid,uuid)') is not null,'hr_submit_timesheet RPC/trigger function exists');
select ok(to_regprocedure('public.hr_approve_timesheet(uuid,uuid)') is not null,'hr_approve_timesheet RPC/trigger function exists');
select ok(to_regprocedure('public.hr_generate_payroll_run(uuid,uuid,date,date,uuid,text)') is not null,'hr_generate_payroll_run RPC/trigger function exists');
select ok(to_regprocedure('public.hr_submit_payroll_run(uuid,uuid)') is not null,'hr_submit_payroll_run RPC/trigger function exists');
select ok(to_regprocedure('public.hr_approve_payroll_run(uuid,uuid)') is not null,'hr_approve_payroll_run RPC/trigger function exists');
select ok(to_regprocedure('public.hr_reject_employee_lifecycle_event_mutation()') is not null,'hr_reject_employee_lifecycle_event_mutation RPC/trigger function exists');
select ok(to_regprocedure('public.hr_create_employee_record(uuid,uuid,uuid,text,text,uuid,date,text,uuid)') is not null,'hr_create_employee_record RPC/trigger function exists');
select ok(to_regprocedure('public.hr_apply_employee_lifecycle_event(uuid,uuid,text,date,uuid,uuid,uuid,text,text,uuid)') is not null,'hr_apply_employee_lifecycle_event RPC/trigger function exists');
select ok(to_regprocedure('public.hr_approve_payroll_finance_mapping(uuid,uuid,uuid)') is not null,'hr_approve_payroll_finance_mapping RPC/trigger function exists');
select ok(to_regprocedure('public.hr_prepare_payroll_finance_posting(uuid,uuid,uuid,uuid,text,uuid)') is not null,'hr_prepare_payroll_finance_posting RPC/trigger function exists');
select ok(to_regprocedure('public.hr_post_payroll_finance_posting(uuid,uuid,uuid)') is not null,'hr_post_payroll_finance_posting RPC/trigger function exists');
select ok(to_regprocedure('public.hr_reconcile_payroll_finance_posting(uuid,uuid,uuid)') is not null,'hr_reconcile_payroll_finance_posting RPC/trigger function exists');
select ok(to_regprocedure('public.hr_approve_payroll_payment_provider(uuid,uuid,uuid)') is not null,'hr_approve_payroll_payment_provider RPC/trigger function exists');
select ok(to_regprocedure('public.hr_approve_payroll_beneficiary_profile(uuid,uuid,uuid)') is not null,'hr_approve_payroll_beneficiary_profile RPC/trigger function exists');
select ok(to_regprocedure('public.hr_prepare_payroll_payment_batch(uuid,uuid,uuid,uuid,text,uuid)') is not null,'hr_prepare_payroll_payment_batch RPC/trigger function exists');
select ok(to_regprocedure('public.hr_approve_payroll_payment_batch(uuid,uuid,uuid)') is not null,'hr_approve_payroll_payment_batch RPC/trigger function exists');
select ok(to_regprocedure('public.hr_apply_payroll_provider_event(uuid,uuid,uuid,text,text,bigint,text,text,timestamptz,boolean,uuid)') is not null,'hr_apply_payroll_provider_event RPC/trigger function exists');
select ok(to_regprocedure('public.hr_reconcile_payroll_payment_batch(uuid,uuid,uuid)') is not null,'hr_reconcile_payroll_payment_batch RPC/trigger function exists');
select ok(to_regprocedure('public.hr_reject_payroll_provider_event_mutation()') is not null,'hr_reject_payroll_provider_event_mutation RPC/trigger function exists');

select ok((select relrowsecurity from pg_class where oid='public.hr_employee_records'::regclass),'hr_employee_records has RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.hr_shift_schedules'::regclass),'hr_shift_schedules has RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.hr_attendance_events'::regclass),'hr_attendance_events has RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.hr_payroll_runs'::regclass),'hr_payroll_runs has RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.hr_payroll_lines'::regclass),'hr_payroll_lines has RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.hr_payroll_finance_postings'::regclass),'hr_payroll_finance_postings has RLS enabled');

select ok(has_table_privilege('service_role','public.hr_payroll_finance_postings','SELECT'),'service role can read payroll Finance posting evidence');
select ok(not has_table_privilege('anon','public.hr_payroll_finance_postings','SELECT'),'anon cannot read payroll Finance posting evidence');
select ok(not has_table_privilege('authenticated','public.hr_payroll_finance_postings','SELECT'),'authenticated cannot read payroll Finance posting evidence');

select ok(exists(select 1 from pg_trigger where tgname='hr_employee_lifecycle_events_append_only' and not tgisinternal),'employee lifecycle events are append-only');
select ok(exists(select 1 from pg_trigger where tgname='hr_payroll_provider_events_append_only' and not tgisinternal),'payroll provider events are append-only');

select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('hr_audit_row_change','hr_record_attendance','hr_create_leave_request','hr_confirm_leave_coverage','hr_review_leave_request','hr_create_shift_schedule','hr_generate_timesheet','hr_submit_timesheet','hr_approve_timesheet','hr_generate_payroll_run','hr_submit_payroll_run','hr_approve_payroll_run','hr_reject_employee_lifecycle_event_mutation','hr_create_employee_record','hr_apply_employee_lifecycle_event','hr_approve_payroll_finance_mapping','hr_prepare_payroll_finance_posting','hr_post_payroll_finance_posting','hr_reconcile_payroll_finance_posting','hr_approve_payroll_payment_provider','hr_approve_payroll_beneficiary_profile','hr_prepare_payroll_payment_batch','hr_approve_payroll_payment_batch','hr_apply_payroll_provider_event','hr_reconcile_payroll_payment_batch','hr_reject_payroll_provider_event_mutation') and p.prosecdef),'all HR workflow functions use SECURITY INVOKER');
select ok(has_function_privilege('service_role','public.hr_post_payroll_finance_posting(uuid,uuid,uuid)','EXECUTE'),'service role can execute payroll Finance posting RPC');
select ok(not has_function_privilege('anon','public.hr_post_payroll_finance_posting(uuid,uuid,uuid)','EXECUTE'),'anon cannot execute payroll Finance posting RPC');

select * from finish();
rollback;
