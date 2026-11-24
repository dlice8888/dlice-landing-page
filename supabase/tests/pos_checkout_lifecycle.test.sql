BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(45);

SELECT ok(to_regclass('public.pos_sale_tenders') IS NOT NULL, 'split tender ledger table exists');
SELECT ok(to_regclass('public.pos_checkout_idempotency_requests') IS NOT NULL, 'split checkout idempotency table exists');
SELECT ok(to_regclass('public.pos_held_orders') IS NOT NULL, 'held POS order table exists');
SELECT ok(to_regclass('public.pos_sale_receipts') IS NOT NULL, 'immutable POS receipt table exists');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.pos_sale_tenders'::regclass), 'tender ledger has RLS enabled');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.pos_checkout_idempotency_requests'::regclass), 'checkout idempotency has RLS enabled');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.pos_held_orders'::regclass), 'held orders have RLS enabled');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.pos_sale_receipts'::regclass), 'receipts have RLS enabled');

SELECT ok(NOT has_table_privilege('anon','public.pos_sale_tenders','SELECT'), 'anon cannot read tender ledger');
SELECT ok(NOT has_table_privilege('authenticated','public.pos_sale_tenders','SELECT'), 'authenticated cannot read tender ledger');
SELECT ok(NOT has_table_privilege('anon','public.pos_checkout_idempotency_requests','SELECT'), 'anon cannot read checkout idempotency');
SELECT ok(NOT has_table_privilege('authenticated','public.pos_checkout_idempotency_requests','SELECT'), 'authenticated cannot read checkout idempotency');
SELECT ok(NOT has_table_privilege('anon','public.pos_held_orders','SELECT'), 'anon cannot read held orders');
SELECT ok(NOT has_table_privilege('authenticated','public.pos_held_orders','SELECT'), 'authenticated cannot read held orders');
SELECT ok(NOT has_table_privilege('anon','public.pos_sale_receipts','SELECT'), 'anon cannot read POS receipts');
SELECT ok(NOT has_table_privilege('authenticated','public.pos_sale_receipts','SELECT'), 'authenticated cannot read POS receipts');

SELECT ok(has_table_privilege('service_role','public.pos_sale_tenders','SELECT,INSERT,UPDATE,DELETE'), 'service_role can manage tender ledger');
SELECT ok(has_table_privilege('service_role','public.pos_checkout_idempotency_requests','SELECT,INSERT,UPDATE,DELETE'), 'service_role can manage checkout idempotency');
SELECT ok(has_table_privilege('service_role','public.pos_held_orders','SELECT,INSERT,UPDATE,DELETE'), 'service_role can manage held orders');
SELECT ok(has_table_privilege('service_role','public.pos_sale_receipts','SELECT,INSERT,UPDATE,DELETE'), 'service_role can manage receipts');

SELECT ok(to_regprocedure('public.erp_create_pos_sale_split_tender_idempotent(uuid,uuid,jsonb,bigint,text,text,uuid,text,jsonb)') IS NOT NULL, 'split tender RPC exists');
SELECT ok(to_regprocedure('public.erp_hold_pos_order(uuid,uuid,uuid,text,jsonb)') IS NOT NULL, 'hold POS order RPC exists');
SELECT ok(to_regprocedure('public.erp_resume_pos_order(uuid,uuid,uuid)') IS NOT NULL, 'resume POS order RPC exists');
SELECT ok(to_regprocedure('public.erp_get_pos_receipt(uuid,uuid,uuid)') IS NOT NULL, 'POS receipt snapshot RPC exists');

SELECT ok(NOT has_function_privilege('anon','public.erp_create_pos_sale_split_tender_idempotent(uuid,uuid,jsonb,bigint,text,text,uuid,text,jsonb)','EXECUTE'), 'anon cannot execute split tender RPC');
SELECT ok(NOT has_function_privilege('authenticated','public.erp_create_pos_sale_split_tender_idempotent(uuid,uuid,jsonb,bigint,text,text,uuid,text,jsonb)','EXECUTE'), 'authenticated cannot execute split tender RPC');
SELECT ok(has_function_privilege('service_role','public.erp_create_pos_sale_split_tender_idempotent(uuid,uuid,jsonb,bigint,text,text,uuid,text,jsonb)','EXECUTE'), 'service_role can execute split tender RPC');

SELECT ok(NOT has_function_privilege('anon','public.erp_hold_pos_order(uuid,uuid,uuid,text,jsonb)','EXECUTE'), 'anon cannot execute hold POS order RPC');
SELECT ok(NOT has_function_privilege('authenticated','public.erp_hold_pos_order(uuid,uuid,uuid,text,jsonb)','EXECUTE'), 'authenticated cannot execute hold POS order RPC');
SELECT ok(has_function_privilege('service_role','public.erp_hold_pos_order(uuid,uuid,uuid,text,jsonb)','EXECUTE'), 'service_role can execute hold POS order RPC');

SELECT ok(NOT has_function_privilege('anon','public.erp_resume_pos_order(uuid,uuid,uuid)','EXECUTE'), 'anon cannot execute resume POS order RPC');
SELECT ok(NOT has_function_privilege('authenticated','public.erp_resume_pos_order(uuid,uuid,uuid)','EXECUTE'), 'authenticated cannot execute resume POS order RPC');
SELECT ok(has_function_privilege('service_role','public.erp_resume_pos_order(uuid,uuid,uuid)','EXECUTE'), 'service_role can execute resume POS order RPC');

SELECT ok(NOT has_function_privilege('anon','public.erp_get_pos_receipt(uuid,uuid,uuid)','EXECUTE'), 'anon cannot execute receipt RPC');
SELECT ok(NOT has_function_privilege('authenticated','public.erp_get_pos_receipt(uuid,uuid,uuid)','EXECUTE'), 'authenticated cannot execute receipt RPC');
SELECT ok(has_function_privilege('service_role','public.erp_get_pos_receipt(uuid,uuid,uuid)','EXECUTE'), 'service_role can execute receipt RPC');

SELECT ok(NOT EXISTS (
  SELECT 1 FROM pg_proc p
  WHERE p.oid IN (
    'public.erp_create_pos_sale_split_tender_idempotent(uuid,uuid,jsonb,bigint,text,text,uuid,text,jsonb)'::regprocedure,
    'public.erp_hold_pos_order(uuid,uuid,uuid,text,jsonb)'::regprocedure,
    'public.erp_resume_pos_order(uuid,uuid,uuid)'::regprocedure,
    'public.erp_get_pos_receipt(uuid,uuid,uuid)'::regprocedure
  ) AND (p.prosecdef OR NOT (p.proconfig @> ARRAY['search_path=public']))
), 'all new POS RPCs are SECURITY INVOKER with pinned search_path');

SELECT ok(NOT EXISTS (
  SELECT 1 FROM pg_proc p
  WHERE p.oid IN (
    'public.erp_create_pos_sale_split_tender_idempotent(uuid,uuid,jsonb,bigint,text,text,uuid,text,jsonb)'::regprocedure,
    'public.erp_hold_pos_order(uuid,uuid,uuid,text,jsonb)'::regprocedure,
    'public.erp_resume_pos_order(uuid,uuid,uuid)'::regprocedure,
    'public.erp_get_pos_receipt(uuid,uuid,uuid)'::regprocedure
  ) AND position('auth.jwt()' in pg_get_functiondef(p.oid)) = 0
), 'all new POS RPCs enforce service_role JWT claim');

SELECT ok(position('split' in pg_get_constraintdef((
  SELECT oid FROM pg_constraint WHERE conrelid='public.pos_sales'::regclass
    AND conname='pos_sales_payment_method_check'
))) > 0, 'POS payment method constraint explicitly supports split');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint
  WHERE conrelid='public.pos_sale_tenders'::regclass
    AND conname='pos_sale_tenders_sale_branch_fkey'
), 'tender sale/branch composite FK prevents cross-branch attachment');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint WHERE conrelid='public.pos_sale_tenders'::regclass
    AND conname='pos_sale_tenders_payment_method_check'
), 'tender ledger restricts methods to supported POS tenders');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint WHERE conrelid='public.pos_sale_tenders'::regclass
    AND conname='pos_sale_tenders_amount_idr_check'
), 'tender ledger rejects zero or negative amounts');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint WHERE conrelid='public.pos_checkout_idempotency_requests'::regclass
    AND conname='pos_checkout_idempotency_actor_key'
), 'split checkout idempotency key is unique per branch and actor');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint WHERE conrelid='public.pos_held_orders'::regclass
    AND conname='pos_held_orders_branch_actor_key'
), 'hold key is unique per branch and cashier');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint WHERE conrelid='public.pos_sale_receipts'::regclass
    AND conname='pos_sale_receipts_sale_key'
), 'receipt snapshot is unique per committed sale');

SELECT * FROM finish();
ROLLBACK;
