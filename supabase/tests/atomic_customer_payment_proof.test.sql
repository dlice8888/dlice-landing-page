BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(15);

INSERT INTO public.tenants (id,slug,legal_name)
VALUES ('d2000000-0000-4000-8000-000000000001','qa-proof-20261121','QA Proof')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.branches (id,code,name,status,accepts_online_orders,pickup_enabled,delivery_enabled,tenant_id)
VALUES ('d2000000-0000-4000-8000-000000000002','QA-PROOF-20261121','QA Proof','active',true,true,false,'d2000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO UPDATE SET status='active',accepts_online_orders=true,pickup_enabled=true,delivery_enabled=false;
INSERT INTO public.products (id,slug,name,unit_price_idr,is_active,category,display_order)
VALUES ('d2000000-0000-4000-8000-000000000003','qa-proof-20261121','QA Proof Product',1500,true,'other',99997)
ON CONFLICT (id) DO UPDATE SET is_active=true,unit_price_idr=1500;
INSERT INTO public.orders
(id,tracking_token_hash,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,
 product_subtotal_idr,payment_status,operational_status,fulfillment_status,branch_id,
 receipt_version,receipt_confirmed_version,receipt_snapshot)
VALUES
('d2000000-0000-4000-8000-000000000011',repeat('a',64),'QA Proof','6280000000001',current_date+3,'12:00','pickup',
 1500,'unpaid','received','unassigned','d2000000-0000-4000-8000-000000000002',1,1,
 '{"payment_method":"bank_transfer","payment_instruction":{"bank":"QA","account":"0000"}}'),
('d2000000-0000-4000-8000-000000000012',repeat('b',64),'QA Expired','6280000000002',current_date+3,'12:00','pickup',
 1500,'unpaid','received','unassigned','d2000000-0000-4000-8000-000000000002',1,1,
 '{"payment_method":"bank_transfer","payment_instruction":{"bank":"QA","account":"0000"}}');
INSERT INTO public.order_reservations(order_id,product_id,service_date,quantity,status,expires_at,branch_id)
VALUES
('d2000000-0000-4000-8000-000000000011','d2000000-0000-4000-8000-000000000003',current_date+3,1,'active',now()+interval '10 minutes','d2000000-0000-4000-8000-000000000002'),
('d2000000-0000-4000-8000-000000000012','d2000000-0000-4000-8000-000000000003',current_date+3,1,'active',now()-interval '1 minute','d2000000-0000-4000-8000-000000000002');

CREATE TEMP TABLE proof_first AS
SELECT public.submit_customer_payment_proof_atomic(
 'd2000000-0000-4000-8000-000000000011',
 'd2000000-0000-4000-8000-000000000021',
 'bank_transfer',1500,
 'd2000000-0000-4000-8000-000000000011/qa-proof.png',
 1,'{"bank":"QA","account":"0000"}'::jsonb
) AS result;

SELECT is((SELECT result->>'ok' FROM proof_first),'true','valid proof submission succeeds');
SELECT is((SELECT result->>'idempotent_replay' FROM proof_first),'false','first proof submission is not a replay');
SELECT is((SELECT count(*)::integer FROM public.payment_records WHERE order_id='d2000000-0000-4000-8000-000000000011'),1,'one payment record is created');
SELECT is((SELECT payment_status FROM public.orders WHERE id='d2000000-0000-4000-8000-000000000011'),'pending_verification','order payment state advances atomically');
SELECT is((SELECT status FROM public.order_reservations WHERE order_id='d2000000-0000-4000-8000-000000000011'),'held_for_verification','reservation is held atomically');
SELECT ok(EXISTS(SELECT 1 FROM public.order_status_history WHERE order_id='d2000000-0000-4000-8000-000000000011' AND status_type='payment' AND new_status='pending_verification'),'payment history is written');
SELECT ok(EXISTS(SELECT 1 FROM public.admin_audit_logs WHERE action='customer_payment_proof_uploaded' AND entity_id='d2000000-0000-4000-8000-000000000011'),'proof upload audit is written');

SELECT is((SELECT result->>'idempotent_replay' FROM (
 SELECT public.submit_customer_payment_proof_atomic(
  'd2000000-0000-4000-8000-000000000011',
  'd2000000-0000-4000-8000-000000000021',
  'bank_transfer',1500,
  'd2000000-0000-4000-8000-000000000011/retry-object.png',
  1,'{"bank":"QA","account":"0000"}'::jsonb
 ) AS result
) q),'true','same upload key returns idempotent success');
SELECT is((SELECT count(*)::integer FROM public.payment_records WHERE order_id='d2000000-0000-4000-8000-000000000011'),1,'idempotent retry does not create another payment');
SELECT is((SELECT result->>'code' FROM (
 SELECT public.submit_customer_payment_proof_atomic(
  'd2000000-0000-4000-8000-000000000011',
  'd2000000-0000-4000-8000-000000000022',
  'bank_transfer',1500,
  'd2000000-0000-4000-8000-000000000011/second-proof.png',
  1,'{"bank":"QA","account":"0000"}'::jsonb
 ) AS result
) q),'proof_already_pending','different upload key cannot replace proof under review');

SELECT is((SELECT result->>'code' FROM (
 SELECT public.submit_customer_payment_proof_atomic(
  'd2000000-0000-4000-8000-000000000011',
  'd2000000-0000-4000-8000-000000000023',
  'bank_transfer',999,
  'd2000000-0000-4000-8000-000000000011/wrong-amount.png',
  1,'{"bank":"QA","account":"0000"}'::jsonb
 ) AS result
) q),'receipt_changed','amount mismatch is rejected');
SELECT is((SELECT result->>'code' FROM (
 SELECT public.submit_customer_payment_proof_atomic(
  'd2000000-0000-4000-8000-000000000011',
  'd2000000-0000-4000-8000-000000000024',
  'dlice_qris',1500,
  'd2000000-0000-4000-8000-000000000011/wrong-method.png',
  1,'{"bank":"QA","account":"0000"}'::jsonb
 ) AS result
) q),'receipt_changed','payment method mismatch is rejected');
SELECT is((SELECT result->>'code' FROM (
 SELECT public.submit_customer_payment_proof_atomic(
  'd2000000-0000-4000-8000-000000000012',
  'd2000000-0000-4000-8000-000000000025',
  'bank_transfer',1500,
  'd2000000-0000-4000-8000-000000000012/expired.png',
  1,'{"bank":"QA","account":"0000"}'::jsonb
 ) AS result
) q),'reservation_expired','expired reservation cannot be revived by proof upload');
SELECT ok(NOT has_function_privilege('anon','public.submit_customer_payment_proof_atomic(uuid,uuid,text,integer,text,integer,jsonb)','EXECUTE'),'anon cannot execute proof RPC');
SELECT ok(NOT has_function_privilege('authenticated','public.submit_customer_payment_proof_atomic(uuid,uuid,text,integer,text,integer,jsonb)','EXECUTE'),'authenticated cannot execute proof RPC');

SELECT * FROM finish();
ROLLBACK;
