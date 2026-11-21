BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(27);

INSERT INTO public.tenants (id,slug,legal_name)
VALUES ('d1000000-0000-4000-8000-000000000001','qa-expiry-20261121','QA Expiry')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.branches (id,code,name,status,accepts_online_orders,pickup_enabled,delivery_enabled,tenant_id)
VALUES ('d1000000-0000-4000-8000-000000000002','QA-EXP-20261121','QA Expiry','active',true,true,false,'d1000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO UPDATE SET status='active',accepts_online_orders=true,pickup_enabled=true,delivery_enabled=false;
INSERT INTO public.products (id,slug,name,unit_price_idr,is_active,category,display_order)
VALUES ('d1000000-0000-4000-8000-000000000003','qa-expiry-20261121','QA Expiry Product',1000,true,'other',99998)
ON CONFLICT (id) DO UPDATE SET is_active=true,unit_price_idr=1000;

INSERT INTO public.orders (id,tracking_token_hash,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,product_subtotal_idr,payment_status,operational_status,fulfillment_status,branch_id)
VALUES
 ('d1000000-0000-4000-8000-000000000011',repeat('1',64),'QA Expired','6280000000001',current_date+3,'12:00','pickup',1000,'unpaid','received','unassigned','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000012',repeat('2',64),'QA Held','6280000000002',current_date+3,'12:00','pickup',1000,'pending_verification','received','unassigned','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000013',repeat('3',64),'QA Reject','6280000000003',current_date+3,'12:00','pickup',1000,'pending_verification','received','unassigned','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000014',repeat('4',64),'QA Paid','6280000000004',current_date+3,'12:00','pickup',1000,'paid','received','unassigned','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000015',repeat('5',64),'QA Unproven','6280000000005',current_date+3,'12:00','pickup',1000,'pending_verification','received','unassigned','d1000000-0000-4000-8000-000000000002');

INSERT INTO public.order_reservations (order_id,product_id,service_date,quantity,status,expires_at,branch_id)
VALUES
 ('d1000000-0000-4000-8000-000000000011','d1000000-0000-4000-8000-000000000003',current_date+3,1,'active',now()-interval '2 minutes','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000012','d1000000-0000-4000-8000-000000000003',current_date+3,1,'held_for_verification',now()-interval '2 minutes','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000013','d1000000-0000-4000-8000-000000000003',current_date+3,1,'held_for_verification',now()+interval '10 minutes','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000014','d1000000-0000-4000-8000-000000000003',current_date+3,1,'consumed',now()-interval '2 minutes','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000015','d1000000-0000-4000-8000-000000000003',current_date+3,1,'held_for_verification',now()-interval '2 minutes','d1000000-0000-4000-8000-000000000002');

CREATE TEMP TABLE test_payment_ids(kind text PRIMARY KEY,id uuid);
WITH ins AS (
 INSERT INTO public.payment_records(order_id,method,amount_idr,status,proof_storage_path,receipt_version)
 VALUES ('d1000000-0000-4000-8000-000000000011','bank_transfer',1000,'pending_verification',NULL,1)
 RETURNING id
) INSERT INTO test_payment_ids SELECT 'expired_no_proof',id FROM ins;
WITH ins AS (
 INSERT INTO public.payment_records(order_id,method,amount_idr,status,proof_storage_path,receipt_version)
 VALUES ('d1000000-0000-4000-8000-000000000012','bank_transfer',1000,'pending_verification','qa-expiry/held-proof.png',1)
 RETURNING id
) INSERT INTO test_payment_ids SELECT 'held_proof',id FROM ins;
WITH ins AS (
 INSERT INTO public.payment_records(order_id,method,amount_idr,status,proof_storage_path,receipt_version)
 VALUES ('d1000000-0000-4000-8000-000000000013','bank_transfer',1000,'pending_verification','qa-expiry/reject-proof.png',1)
 RETURNING id
) INSERT INTO test_payment_ids SELECT 'reject_proof',id FROM ins;
WITH ins AS (
 INSERT INTO public.payment_records(order_id,method,amount_idr,status,proof_storage_path,receipt_version)
 VALUES ('d1000000-0000-4000-8000-000000000013','bank_transfer',1000,'pending_verification',NULL,1)
 RETURNING id
) INSERT INTO test_payment_ids SELECT 'reject_no_proof',id FROM ins;
WITH ins AS (
 INSERT INTO public.payment_records(order_id,method,amount_idr,status,proof_storage_path,receipt_version)
 VALUES ('d1000000-0000-4000-8000-000000000014','bank_transfer',1000,'pending_verification',NULL,1)
 RETURNING id
) INSERT INTO test_payment_ids SELECT 'paid_no_proof',id FROM ins;
WITH ins AS (
 INSERT INTO public.payment_records(order_id,method,amount_idr,status,proof_storage_path,receipt_version)
 VALUES ('d1000000-0000-4000-8000-000000000015','bank_transfer',1000,'pending_verification',NULL,1)
 RETURNING id
) INSERT INTO test_payment_ids SELECT 'unproven_no_proof',id FROM ins;

CREATE TEMP TABLE test_expiry_result AS
SELECT public.expire_stale_order_reservations(50) AS result;

SELECT is((SELECT (result->>'expired_orders')::integer FROM test_expiry_result),2,'expires unpaid and unproven pending orders with expired reservations');
SELECT is((SELECT (result->>'expired_reservations')::integer FROM test_expiry_result),2,'expires active and held expired reservation rows');
SELECT is((SELECT fulfillment_status FROM public.orders WHERE id='d1000000-0000-4000-8000-000000000011'),'failed','expired unpaid order moves to failed fulfillment');
SELECT is((SELECT operational_status FROM public.orders WHERE id='d1000000-0000-4000-8000-000000000011'),'cancelled','expired unpaid order is operationally cancelled');
SELECT is((SELECT status FROM public.order_reservations WHERE order_id='d1000000-0000-4000-8000-000000000011'),'expired','expired reservation is released from capacity');
SELECT is((SELECT status FROM public.payment_records WHERE id=(SELECT id FROM test_payment_ids WHERE kind='expired_no_proof')),'rejected','no-proof pending attempt on expired order is closed');
SELECT is((SELECT payment_status FROM public.orders WHERE id='d1000000-0000-4000-8000-000000000012'),'pending_verification','proof-bearing pending order is not auto-expired');
SELECT is((SELECT status FROM public.order_reservations WHERE order_id='d1000000-0000-4000-8000-000000000012'),'held_for_verification','proof-bearing reservation remains held');
SELECT is((SELECT status FROM public.payment_records WHERE id=(SELECT id FROM test_payment_ids WHERE kind='paid_no_proof')),'superseded','stale no-proof attempt on an already-paid order is superseded');

SELECT is((SELECT payment_status FROM public.orders WHERE id='d1000000-0000-4000-8000-000000000015'),'rejected','pending payment without proof is rejected after its deadline');
SELECT is((SELECT fulfillment_status FROM public.orders WHERE id='d1000000-0000-4000-8000-000000000015'),'failed','unproven pending order moves to failed fulfillment');
SELECT is((SELECT status FROM public.order_reservations WHERE order_id='d1000000-0000-4000-8000-000000000015'),'expired','unproven pending reservation expires after deadline');
SELECT is((SELECT status FROM public.payment_records WHERE id=(SELECT id FROM test_payment_ids WHERE kind='unproven_no_proof')),'rejected','unproven pending payment attempt is closed');
SELECT is((SELECT (result->>'closed_payment_attempts')::integer FROM test_expiry_result),3,'closes no-proof attempts for expired and paid orders');

SELECT ok(public.admin_apply_payment_verification(
  'd1000000-0000-4000-8000-000000000013',
  (SELECT id FROM test_payment_ids WHERE kind='reject_proof'),
  NULL,'rejected','QA lifecycle rejection'
),'admin rejection applies atomically');
SELECT ok(NOT public.admin_apply_payment_verification(
  'd1000000-0000-4000-8000-000000000013',
  (SELECT id FROM test_payment_ids WHERE kind='reject_proof'),
  NULL,'paid','late payment after order rejection'
),'rejected order cannot be reopened by a late payment decision');
SELECT is((SELECT payment_status FROM public.orders WHERE id='d1000000-0000-4000-8000-000000000013'),'rejected','rejected payment marks payment state rejected');
SELECT is((SELECT fulfillment_status FROM public.orders WHERE id='d1000000-0000-4000-8000-000000000013'),'failed','rejected payment marks fulfillment failed');
SELECT is((SELECT operational_status FROM public.orders WHERE id='d1000000-0000-4000-8000-000000000013'),'cancelled','rejected payment cancels operational state');
SELECT is((SELECT status FROM public.order_reservations WHERE order_id='d1000000-0000-4000-8000-000000000013'),'released','rejected payment releases held reservations');
SELECT is((SELECT status FROM public.payment_records WHERE id=(SELECT id FROM test_payment_ids WHERE kind='reject_no_proof')),'rejected','other no-proof pending attempt is closed on rejection');
SELECT ok(EXISTS(SELECT 1 FROM public.order_status_history WHERE order_id='d1000000-0000-4000-8000-000000000013' AND status_type='fulfillment' AND new_status='failed'),'fulfillment failure is auditable');
SELECT ok(EXISTS(SELECT 1 FROM cron.job WHERE jobname='dlice-expire-stale-online-orders' AND active AND schedule='* * * * *'),'minute expiry cron job is installed');
SELECT has_index('public','order_reservations','idx_order_reservations_active_expiry','expiry worker reservation index exists');
SELECT has_index('public','payment_records','idx_payment_records_pending_without_proof','pending payment cleanup index exists');

CREATE TEMP TABLE test_expiry_rerun AS
SELECT public.expire_stale_order_reservations(50) AS result;
SELECT is((SELECT (result->>'expired_orders')::integer FROM test_expiry_rerun),0,'expiry worker is idempotent on repeat');
SELECT is((SELECT (result->>'closed_payment_attempts')::integer FROM test_expiry_rerun),0,'payment cleanup is idempotent on repeat');

SELECT * FROM finish();
ROLLBACK;
