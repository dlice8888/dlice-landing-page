-- PGTAP DRAFT — run only after applying QUALITY_COMPLIANCE_SCHEMA_DRAFT.sql
-- and QUALITY_COMPLIANCE_ADAPTERS_EXTENSION_DRAFT.sql to a disposable local DB.
begin;
select plan(34);

select ok(to_regclass('public.food_lot_registry') is not null,'food lot registry exists');
select ok(to_regclass('public.food_lot_distributions') is not null,'food lot distribution trace exists');
select ok(to_regclass('public.food_safety_inspections') is not null,'food safety inspection evidence exists');
select ok(to_regclass('public.food_recalls') is not null,'food recalls exist');
select ok(to_regclass('public.food_recall_impacts') is not null,'food recall impact ledger exists');
select ok(to_regclass('public.supplier_quality_inspections') is not null,'supplier quality inspections exist');
select ok(to_regclass('public.supplier_corrective_actions') is not null,'supplier CAPA exists');
select ok(to_regclass('public.quality_compliance_events') is not null,'quality compliance event ledger exists');

select ok(to_regprocedure('public.quality_approve_food_safety_policy(uuid,uuid,uuid,uuid)') is not null,'food policy approval RPC exists');
select ok(to_regprocedure('public.quality_request_food_safety_policy(uuid,uuid,text,numeric,numeric,text[],timestamptz,timestamptz,text,uuid)') is not null,'food policy request RPC exists');
select ok(to_regprocedure('public.quality_approve_supplier_quality_policy(uuid,uuid,uuid,uuid)') is not null,'supplier policy approval RPC exists');
select ok(to_regprocedure('public.quality_request_supplier_quality_policy(uuid,uuid,uuid,text[],timestamptz,timestamptz,text,uuid)') is not null,'supplier policy request RPC exists');
select ok(to_regprocedure('public.quality_register_food_lot(uuid,uuid,text,uuid,text,numeric,text,text,uuid)') is not null,'food lot registration RPC exists');
select ok(to_regprocedure('public.quality_link_food_lot_distribution(uuid,uuid,uuid,text,uuid,numeric,text,uuid)') is not null,'food lot distribution RPC exists');
select ok(to_regprocedure('public.quality_record_food_safety_inspection(uuid,uuid,text,uuid,text,uuid,numeric,text[],text,uuid)') is not null,'food safety inspection RPC exists');
select ok(to_regprocedure('public.quality_initiate_food_recall(uuid,uuid,text,text,text,text,uuid)') is not null,'food recall RPC exists');
select ok(to_regprocedure('public.quality_record_supplier_quality_inspection(uuid,uuid,uuid,uuid,jsonb,text,uuid)') is not null,'supplier quality inspection RPC exists');
select ok(to_regprocedure('public.quality_submit_supplier_capa(uuid,uuid,uuid,text,text,text,text,uuid)') is not null,'supplier CAPA submission RPC exists');
select ok(to_regprocedure('public.quality_verify_supplier_capa(uuid,uuid,uuid,text,text,boolean,uuid)') is not null,'supplier CAPA verification RPC exists');

select ok((select relrowsecurity from pg_class where oid='public.food_lot_registry'::regclass),'food lot registry has RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.food_lot_distributions'::regclass),'food lot distributions have RLS enabled');
select ok(has_table_privilege('service_role','public.food_lot_registry','SELECT'),'service role can read food lot registry');
select ok(not has_table_privilege('anon','public.food_lot_registry','SELECT'),'anon cannot read food lot registry');
select ok(not has_table_privilege('authenticated','public.food_lot_registry','SELECT'),'authenticated cannot read food lot registry');
select ok(not has_table_privilege('anon','public.food_lot_distributions','SELECT'),'anon cannot read food lot distributions');

select ok(exists(select 1 from pg_trigger where tgname='food_safety_inspections_append_only' and not tgisinternal),'food safety inspection is append only');
select ok(exists(select 1 from pg_trigger where tgname='food_recall_impacts_append_only' and not tgisinternal),'food recall impacts are append only');
select ok(exists(select 1 from pg_trigger where tgname='quality_compliance_events_append_only' and not tgisinternal),'quality compliance events are append only');

select ok(has_function_privilege('service_role',to_regprocedure('public.quality_record_food_safety_inspection(uuid,uuid,text,uuid,text,uuid,numeric,text[],text,uuid)'),'EXECUTE'),'service role can execute inspection RPC');
select ok(not has_function_privilege('anon',to_regprocedure('public.quality_record_food_safety_inspection(uuid,uuid,text,uuid,text,uuid,numeric,text[],text,uuid)'),'EXECUTE'),'anon cannot execute inspection RPC');
select ok(not has_function_privilege('authenticated',to_regprocedure('public.quality_record_food_safety_inspection(uuid,uuid,text,uuid,text,uuid,numeric,text[],text,uuid)'),'EXECUTE'),'authenticated cannot execute inspection RPC');

select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('quality_approve_food_safety_policy','quality_approve_supplier_quality_policy','quality_request_food_safety_policy','quality_request_supplier_quality_policy',
 'quality_register_food_lot','quality_link_food_lot_distribution','quality_record_food_safety_inspection',
 'quality_initiate_food_recall','quality_record_supplier_quality_inspection','quality_submit_supplier_capa',
 'quality_verify_supplier_capa') and p.prosecdef),'all Quality RPCs are SECURITY INVOKER');

select ok(to_regclass('public.food_lot_one_active_quarantine_uq') is not null,'food lot active quarantine uniqueness index exists');
select ok(to_regclass('public.supplier_quality_one_active_quarantine_uq') is not null,'supplier active quarantine uniqueness index exists');

select * from finish();
rollback;
