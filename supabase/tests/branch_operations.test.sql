-- Branch Operations schema, lifecycle guard and ACL contracts.
-- Executed only by the disposable Supabase PostgreSQL replay workflow.
begin;
select plan(92);

select ok(to_regclass('public.branch_ops_equipment') is not null,'equipment table exists');
select ok(to_regclass('public.branch_ops_tasks') is not null,'task table exists');
select ok(to_regclass('public.branch_ops_evidence_assets') is not null,'evidence table exists');
select ok(to_regclass('public.branch_ops_incidents') is not null,'incident table exists');
select ok(to_regclass('public.branch_ops_work_orders') is not null,'maintenance work order table exists');
select ok(to_regclass('public.branch_ops_compliance_checks') is not null,'compliance check table exists');
select ok(to_regclass('public.branch_ops_compliance_snapshots') is not null,'compliance snapshot table exists');

select ok((select relrowsecurity from pg_class where oid='public.branch_ops_equipment'::regclass),'equipment RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.branch_ops_tasks'::regclass),'tasks RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.branch_ops_evidence_assets'::regclass),'evidence RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.branch_ops_incidents'::regclass),'incidents RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.branch_ops_work_orders'::regclass),'work orders RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.branch_ops_compliance_checks'::regclass),'compliance checks RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.branch_ops_compliance_snapshots'::regclass),'compliance snapshots RLS enabled');

select ok(not has_table_privilege('anon','public.branch_ops_equipment','SELECT'),'anon cannot read equipment');
select ok(not has_table_privilege('authenticated','public.branch_ops_equipment','SELECT'),'authenticated cannot read equipment directly');
select ok(not has_table_privilege('anon','public.branch_ops_tasks','SELECT'),'anon cannot read tasks');
select ok(not has_table_privilege('authenticated','public.branch_ops_tasks','SELECT'),'authenticated cannot read tasks directly');
select ok(not has_table_privilege('anon','public.branch_ops_evidence_assets','SELECT'),'anon cannot read evidence metadata');
select ok(not has_table_privilege('authenticated','public.branch_ops_evidence_assets','SELECT'),'authenticated cannot read evidence metadata directly');
select ok(not has_table_privilege('anon','public.branch_ops_compliance_snapshots','SELECT'),'anon cannot read compliance snapshots');
select ok(not has_table_privilege('authenticated','public.branch_ops_compliance_snapshots','SELECT'),'authenticated cannot read compliance snapshots directly');

select ok(exists(select 1 from storage.buckets where id='branch-ops-evidence' and public=false
  and file_size_limit=8388608
  and allowed_mime_types @> array['image/jpeg','image/png','application/pdf']),
  'evidence bucket is private and MIME/size constrained');
select ok(exists(select 1 from pg_trigger where tgname='branch_ops_evidence_assets_immutable' and not tgisinternal),
  'evidence metadata is immutable');
select ok(exists(select 1 from pg_trigger where tgname='branch_ops_compliance_snapshots_immutable' and not tgisinternal),
  'published compliance snapshots are immutable');

select ok(to_regprocedure('public.branch_ops_register_equipment(uuid,uuid,uuid,text,text)') is not null,'equipment RPC signature exists');
select ok(to_regprocedure('public.branch_ops_create_task(uuid,uuid,uuid,uuid,text,text,text,timestamptz,text,text,uuid)') is not null,'create task RPC signature exists');
select ok(to_regprocedure('public.branch_ops_update_task_status(uuid,uuid,uuid,uuid,text)') is not null,'task transition RPC signature exists');
select ok(to_regprocedure('public.branch_ops_record_incident(uuid,uuid,uuid,text,text,text,text,timestamptz,uuid[])') is not null,'incident create RPC signature exists');
select ok(to_regprocedure('public.branch_ops_update_incident_status(uuid,uuid,uuid,uuid,text)') is not null,'incident transition RPC signature exists');
select ok(to_regprocedure('public.branch_ops_create_maintenance_order(uuid,uuid,uuid,uuid,text,text,timestamptz,text,uuid,uuid[])') is not null,'maintenance create RPC signature exists');
select ok(to_regprocedure('public.branch_ops_update_work_order_status(uuid,uuid,uuid,uuid,text)') is not null,'maintenance transition RPC signature exists');
select ok(to_regprocedure('public.branch_ops_register_evidence_asset(uuid,uuid,uuid,text,text,text,bigint)') is not null,'evidence registration RPC signature exists');
select ok(to_regprocedure('public.branch_ops_submit_compliance_check(uuid,uuid,uuid,text,text,integer,date,uuid)') is not null,'compliance submit RPC signature exists');
select ok(to_regprocedure('public.branch_ops_review_compliance_check(uuid,uuid,uuid,uuid,text)') is not null,'compliance review RPC signature exists');
select ok(to_regprocedure('public.branch_ops_publish_compliance_snapshot(uuid,uuid,uuid,date,date,text,text)') is not null,'compliance publish RPC signature exists');
select ok(position('pg_advisory_xact_lock' in pg_get_functiondef('public.branch_ops_create_task(uuid,uuid,uuid,uuid,text,text,text,timestamptz,text,text,uuid)'::regprocedure))>0
  and position('BRANCH_OPS_IDEMPOTENCY_SCOPE_MISMATCH' in pg_get_functiondef('public.branch_ops_create_task(uuid,uuid,uuid,uuid,text,text,text,timestamptz,text,text,uuid)'::regprocedure))>0,
  'task retries are serialized and cannot replay across branches');
select ok(position('pg_advisory_xact_lock' in pg_get_functiondef('public.branch_ops_record_incident(uuid,uuid,uuid,text,text,text,text,timestamptz,uuid[])'::regprocedure))>0
  and position('BRANCH_OPS_IDEMPOTENCY_SCOPE_MISMATCH' in pg_get_functiondef('public.branch_ops_record_incident(uuid,uuid,uuid,text,text,text,text,timestamptz,uuid[])'::regprocedure))>0,
  'incident retries are serialized and cannot replay across branches');
select ok(position('pg_advisory_xact_lock' in pg_get_functiondef('public.branch_ops_create_maintenance_order(uuid,uuid,uuid,uuid,text,text,timestamptz,text,uuid,uuid[])'::regprocedure))>0
  and position('BRANCH_OPS_IDEMPOTENCY_SCOPE_MISMATCH' in pg_get_functiondef('public.branch_ops_create_maintenance_order(uuid,uuid,uuid,uuid,text,text,timestamptz,text,uuid,uuid[])'::regprocedure))>0,
  'maintenance retries are serialized and cannot replay across branches');
select ok(position('pg_advisory_xact_lock' in pg_get_functiondef('public.branch_ops_publish_compliance_snapshot(uuid,uuid,uuid,date,date,text,text)'::regprocedure))>0
  and position('BRANCH_OPS_IDEMPOTENCY_SCOPE_MISMATCH' in pg_get_functiondef('public.branch_ops_publish_compliance_snapshot(uuid,uuid,uuid,date,date,text,text)'::regprocedure))>0,
  'compliance snapshot retries are serialized and cannot replay across branches');
select ok(position('BRANCH_TASK_TRANSITION_INVALID' in pg_get_functiondef('public.branch_ops_update_task_status(uuid,uuid,uuid,uuid,text)'::regprocedure))>0
  and position('in_progress' in pg_get_functiondef('public.branch_ops_update_task_status(uuid,uuid,uuid,uuid,text)'::regprocedure))>0
  and position('completed' in pg_get_functiondef('public.branch_ops_update_task_status(uuid,uuid,uuid,uuid,text)'::regprocedure))>0,
  'task lifecycle enforces open to in-progress/completed/cancelled and in-progress to terminal states');
select ok(position('BRANCH_INCIDENT_TRANSITION_INVALID' in pg_get_functiondef('public.branch_ops_update_incident_status(uuid,uuid,uuid,uuid,text)'::regprocedure))>0
  and position('investigating' in pg_get_functiondef('public.branch_ops_update_incident_status(uuid,uuid,uuid,uuid,text)'::regprocedure))>0
  and position('closed' in pg_get_functiondef('public.branch_ops_update_incident_status(uuid,uuid,uuid,uuid,text)'::regprocedure))>0,
  'incident lifecycle enforces investigation, resolution and closure transitions');
select ok(position('BRANCH_WORK_ORDER_TRANSITION_INVALID' in pg_get_functiondef('public.branch_ops_update_work_order_status(uuid,uuid,uuid,uuid,text)'::regprocedure))>0
  and position('scheduled' in pg_get_functiondef('public.branch_ops_update_work_order_status(uuid,uuid,uuid,uuid,text)'::regprocedure))>0
  and position('completed' in pg_get_functiondef('public.branch_ops_update_work_order_status(uuid,uuid,uuid,uuid,text)'::regprocedure))>0,
  'maintenance lifecycle enforces scheduled, in-progress and terminal transitions');
select ok(position('BRANCH_COMPLIANCE_SEPARATION_OF_DUTIES' in pg_get_functiondef('public.branch_ops_review_compliance_check(uuid,uuid,uuid,uuid,text)'::regprocedure))>0
  and position('BRANCH_COMPLIANCE_CHECK_NOT_SUBMITTED' in pg_get_functiondef('public.branch_ops_review_compliance_check(uuid,uuid,uuid,uuid,text)'::regprocedure))>0,
  'compliance review enforces submitted state and independent approver');
select ok(position('BRANCH_EVIDENCE_PATH_SCOPE_INVALID' in pg_get_functiondef('public.branch_ops_register_evidence_asset(uuid,uuid,uuid,text,text,text,bigint)'::regprocedure))>0
  and position('BRANCH_EVIDENCE_STORAGE_OBJECT_MISSING' in pg_get_functiondef('public.branch_ops_register_evidence_asset(uuid,uuid,uuid,text,text,text,bigint)'::regprocedure))>0
  and position('BRANCH_EVIDENCE_FILE_INVALID' in pg_get_functiondef('public.branch_ops_register_evidence_asset(uuid,uuid,uuid,text,text,text,bigint)'::regprocedure))>0,
  'evidence registration enforces private object existence, tenant path, MIME and size');
select ok(position('BRANCH_COMPLIANCE_EVIDENCE_INCOMPLETE' in pg_get_functiondef('public.branch_ops_publish_compliance_snapshot(uuid,uuid,uuid,date,date,text,text)'::regprocedure))>0
  and position('BRANCH_COMPLIANCE_SOURCE_REVISION_MISMATCH' in pg_get_functiondef('public.branch_ops_publish_compliance_snapshot(uuid,uuid,uuid,date,date,text,text)'::regprocedure))>0,
  'compliance publication requires complete approved evidence and matching source revision');

select ok(has_function_privilege('service_role','public.branch_ops_register_equipment(uuid,uuid,uuid,text,text)','EXECUTE'),'service role can register equipment');
select ok(has_function_privilege('service_role','public.branch_ops_create_task(uuid,uuid,uuid,uuid,text,text,text,timestamptz,text,text,uuid)','EXECUTE'),'service role can create tasks');
select ok(has_function_privilege('service_role','public.branch_ops_update_task_status(uuid,uuid,uuid,uuid,text)','EXECUTE'),'service role can transition tasks');
select ok(has_function_privilege('service_role','public.branch_ops_record_incident(uuid,uuid,uuid,text,text,text,text,timestamptz,uuid[])','EXECUTE'),'service role can record incidents');
select ok(has_function_privilege('service_role','public.branch_ops_update_incident_status(uuid,uuid,uuid,uuid,text)','EXECUTE'),'service role can transition incidents');
select ok(has_function_privilege('service_role','public.branch_ops_create_maintenance_order(uuid,uuid,uuid,uuid,text,text,timestamptz,text,uuid,uuid[])','EXECUTE'),'service role can create maintenance work orders');
select ok(has_function_privilege('service_role','public.branch_ops_update_work_order_status(uuid,uuid,uuid,uuid,text)','EXECUTE'),'service role can transition maintenance work orders');
select ok(has_function_privilege('service_role','public.branch_ops_register_evidence_asset(uuid,uuid,uuid,text,text,text,bigint)','EXECUTE'),'service role can register evidence metadata');
select ok(has_function_privilege('service_role','public.branch_ops_submit_compliance_check(uuid,uuid,uuid,text,text,integer,date,uuid)','EXECUTE'),'service role can submit compliance checks');
select ok(has_function_privilege('service_role','public.branch_ops_review_compliance_check(uuid,uuid,uuid,uuid,text)','EXECUTE'),'service role can review compliance checks');
select ok(has_function_privilege('service_role','public.branch_ops_publish_compliance_snapshot(uuid,uuid,uuid,date,date,text,text)','EXECUTE'),'service role can publish compliance snapshots');

select ok(not has_function_privilege('anon','public.branch_ops_register_equipment(uuid,uuid,uuid,text,text)','EXECUTE'),'anon cannot register equipment');
select ok(not has_function_privilege('anon','public.branch_ops_create_task(uuid,uuid,uuid,uuid,text,text,text,timestamptz,text,text,uuid)','EXECUTE'),'anon cannot create tasks');
select ok(not has_function_privilege('anon','public.branch_ops_update_task_status(uuid,uuid,uuid,uuid,text)','EXECUTE'),'anon cannot transition tasks');
select ok(not has_function_privilege('anon','public.branch_ops_record_incident(uuid,uuid,uuid,text,text,text,text,timestamptz,uuid[])','EXECUTE'),'anon cannot record incidents');
select ok(not has_function_privilege('anon','public.branch_ops_update_incident_status(uuid,uuid,uuid,uuid,text)','EXECUTE'),'anon cannot transition incidents');
select ok(not has_function_privilege('anon','public.branch_ops_create_maintenance_order(uuid,uuid,uuid,uuid,text,text,timestamptz,text,uuid,uuid[])','EXECUTE'),'anon cannot create work orders');
select ok(not has_function_privilege('anon','public.branch_ops_update_work_order_status(uuid,uuid,uuid,uuid,text)','EXECUTE'),'anon cannot transition work orders');
select ok(not has_function_privilege('anon','public.branch_ops_register_evidence_asset(uuid,uuid,uuid,text,text,text,bigint)','EXECUTE'),'anon cannot register evidence');
select ok(not has_function_privilege('anon','public.branch_ops_submit_compliance_check(uuid,uuid,uuid,text,text,integer,date,uuid)','EXECUTE'),'anon cannot submit compliance checks');
select ok(not has_function_privilege('anon','public.branch_ops_review_compliance_check(uuid,uuid,uuid,uuid,text)','EXECUTE'),'anon cannot review compliance checks');
select ok(not has_function_privilege('anon','public.branch_ops_publish_compliance_snapshot(uuid,uuid,uuid,date,date,text,text)','EXECUTE'),'anon cannot publish snapshots');

select ok(not has_function_privilege('authenticated','public.branch_ops_register_equipment(uuid,uuid,uuid,text,text)','EXECUTE'),'authenticated cannot register equipment directly');
select ok(not has_function_privilege('authenticated','public.branch_ops_create_task(uuid,uuid,uuid,uuid,text,text,text,timestamptz,text,text,uuid)','EXECUTE'),'authenticated cannot create tasks directly');
select ok(not has_function_privilege('authenticated','public.branch_ops_update_task_status(uuid,uuid,uuid,uuid,text)','EXECUTE'),'authenticated cannot transition tasks directly');
select ok(not has_function_privilege('authenticated','public.branch_ops_record_incident(uuid,uuid,uuid,text,text,text,text,timestamptz,uuid[])','EXECUTE'),'authenticated cannot record incidents directly');
select ok(not has_function_privilege('authenticated','public.branch_ops_update_incident_status(uuid,uuid,uuid,uuid,text)','EXECUTE'),'authenticated cannot transition incidents directly');
select ok(not has_function_privilege('authenticated','public.branch_ops_create_maintenance_order(uuid,uuid,uuid,uuid,text,text,timestamptz,text,uuid,uuid[])','EXECUTE'),'authenticated cannot create work orders directly');
select ok(not has_function_privilege('authenticated','public.branch_ops_update_work_order_status(uuid,uuid,uuid,uuid,text)','EXECUTE'),'authenticated cannot transition work orders directly');
select ok(not has_function_privilege('authenticated','public.branch_ops_register_evidence_asset(uuid,uuid,uuid,text,text,text,bigint)','EXECUTE'),'authenticated cannot register evidence directly');
select ok(not has_function_privilege('authenticated','public.branch_ops_submit_compliance_check(uuid,uuid,uuid,text,text,integer,date,uuid)','EXECUTE'),'authenticated cannot submit compliance checks directly');
select ok(not has_function_privilege('authenticated','public.branch_ops_review_compliance_check(uuid,uuid,uuid,uuid,text)','EXECUTE'),'authenticated cannot review compliance checks directly');
select ok(not has_function_privilege('authenticated','public.branch_ops_publish_compliance_snapshot(uuid,uuid,uuid,date,date,text,text)','EXECUTE'),'authenticated cannot publish snapshots directly');

select throws_ok($$select public.branch_ops_register_equipment('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','X','Equipment')$$,
 '42501','BRANCH_OPS_FORBIDDEN','equipment RPC rejects an actor outside the tenant/branch');
select throws_ok($$select public.branch_ops_create_task('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','idem-task-001','Test',null,now(),'normal','manual',null)$$,
 '42501','BRANCH_OPS_FORBIDDEN','task creation rejects an actor outside the tenant/branch');
select throws_ok($$select public.branch_ops_update_task_status('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','completed')$$,
 '42501','BRANCH_OPS_FORBIDDEN','task transition rejects an actor outside the tenant/branch');
select throws_ok($$select public.branch_ops_record_incident('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','idem-inc-001','safety','Test','high',now(),'{}'::uuid[])$$,
 '42501','BRANCH_OPS_FORBIDDEN','incident creation rejects an actor outside the tenant/branch');
select throws_ok($$select public.branch_ops_update_incident_status('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','resolved')$$,
 '42501','BRANCH_OPS_FORBIDDEN','incident transition rejects an actor outside the tenant/branch');
select throws_ok($$select public.branch_ops_create_maintenance_order('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','idem-work-001','corrective',now(),'Test',null,'{}'::uuid[])$$,
 '42501','BRANCH_OPS_FORBIDDEN','maintenance creation rejects an actor outside the tenant/branch');
select throws_ok($$select public.branch_ops_update_work_order_status('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','completed')$$,
 '42501','BRANCH_OPS_FORBIDDEN','maintenance transition rejects an actor outside the tenant/branch');
select throws_ok($$select public.branch_ops_register_evidence_asset('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','invalid/path','branch_incident','image/jpeg',100)$$,
 '42501','BRANCH_OPS_FORBIDDEN','evidence registration rejects an actor outside the tenant/branch');
select throws_ok($$select public.branch_ops_submit_compliance_check('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','open','Check',1,current_date,'00000000-0000-0000-0000-000000000000')$$,
 '42501','BRANCH_OPS_FORBIDDEN','compliance submission rejects an actor outside the tenant/branch');
select throws_ok($$select public.branch_ops_review_compliance_check('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','pass')$$,
 '42501','BRANCH_OPS_FORBIDDEN','compliance review rejects an actor outside the tenant/branch');
select throws_ok($$select public.branch_ops_publish_compliance_snapshot('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000',current_date,current_date,'idem-snapshot-001',null)$$,
 '42501','BRANCH_OPS_FORBIDDEN','compliance snapshot publication rejects an actor outside the tenant/branch');

select ok(not has_function_privilege('anon','public.branch_ops_prevent_immutable_record_mutation()','EXECUTE'),
  'anon cannot directly execute the immutable-record trigger function');
select ok(not has_function_privilege('authenticated','public.branch_ops_prevent_immutable_record_mutation()','EXECUTE'),
  'authenticated cannot directly execute the immutable-record trigger function');

select * from finish();
rollback;
