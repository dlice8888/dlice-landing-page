BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(13);

INSERT INTO auth.users
(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('d7000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','qa.payment.approver.20261121@accounts.dlice.internal','',
 now(),'{}'::jsonb,'{}'::jsonb,now(),now());

INSERT INTO public.tenants(id,slug,legal_name,status)
VALUES('d7000000-0000-4000-8000-000000000002','qa-payment-supersession-20261121','QA Payment Supersession','trial')
ON CONFLICT(id) DO NOTHING;

INSERT INTO public.branches(id,code,name,status,accepts_online_orders,pickup_enabled,delivery_enabled,tenant_id)
VALUES('d7000000-0000-4000-8000-000000000003','QA-PAY-SUP-20261121','QA Payment Supersession','active',true,true,false,'d7000000-0000-4000-8000-000000000002')
ON CONFLICT(id) DO UPDATE SET status='active',accepts_online_orders=true,pickup_enabled=true,delivery_enabled=false;

INSERT INTO public.orders
(id,tracking_token_hash,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,
 product_subtotal_idr,payment_status,operational_status,fulfillment_status,branch_id,
 receipt_version,receipt_confirmed_version,receipt_snapshot)
VALUES
('d7000000-0000-4000-8000-000000000011',repeat('c',64),'QA Payment','6280000000011',current_date+3,'12:00','pickup',
 1500,'pending_verification','received','unassigned','d7000000-0000-4000-8000-000000000003',1,1,
 '{"payment_method":"bank_transfer","payment_instruction":{"bank":"QA","account":"0000"}}');

INSERT INTO public.order_reservations(order_id,product_id,service_date,quantity,status,expires_at,branch_id)
VALUES
('d7000000-0000-4000-8000-000000000011',
 (SELECT id FROM public.products ORDER BY created_at LIMIT 1),
 current_date+3,1,'held_for_verification',now()+interval '10 minutes',
 'd7000000-0000-4000-8000-000000000003');

INSERT INTO public.payment_records(id,order_id,method,amount_idr,status,proof_storage_path)
VALUES
('d7000000-0000-4000-8000-000000000021','d7000000-0000-4000-8000-000000000011','bank_transfer',1500,'pending_verification','qa/payment/current.png'),
('d7000000-0000-4000-8000-000000000022','d7000000-0000-4000-8000-000000000011','bank_transfer',1500,'pending_verification','qa/payment/older.png'),
('d7000000-0000-4000-8000-000000000023','d7000000-0000-4000-8000-000000000011','bank_transfer',1500,'unpaid',NULL);

SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

SELECT is(
 public.admin_apply_payment_verification(
  'd7000000-0000-4000-8000-000000000011',
  'd7000000-0000-4000-8000-000000000021',
  'd7000000-0000-4000-8000-000000000001',
  'paid','QA approval'
 ),
 true,
 'approving one payment atomically settles the order'
);

SELECT is(
 (SELECT payment_status FROM public.orders WHERE id='d7000000-0000-4000-8000-000000000011'),
 'paid',
 'order is paid after approval'
);

SELECT is(
 (SELECT status FROM public.payment_records WHERE id='d7000000-0000-4000-8000-000000000021'),
 'paid',
 'approved payment attempt is paid'
);

SELECT is(
 (SELECT status FROM public.payment_records WHERE id='d7000000-0000-4000-8000-000000000022'),
 'superseded',
 'older pending payment attempt is superseded'
);

SELECT is(
 (SELECT status FROM public.payment_records WHERE id='d7000000-0000-4000-8000-000000000023'),
 'superseded',
 'unpaid duplicate attempt is superseded'
);

SELECT is(
 (SELECT superseded_by_payment_id FROM public.payment_records WHERE id='d7000000-0000-4000-8000-000000000022'),
 'd7000000-0000-4000-8000-000000000021'::uuid,
 'superseded attempt links to the approved payment'
);

SELECT ok(
 (SELECT superseded_at IS NOT NULL FROM public.payment_records WHERE id='d7000000-0000-4000-8000-000000000022'),
 'superseded attempt has a timestamp'
);

SELECT is(
 (SELECT count(*)::integer FROM public.payment_records
  WHERE order_id='d7000000-0000-4000-8000-000000000011'
    AND status IN ('unpaid','pending_verification')),
 0,
 'no actionable unpaid or pending attempts remain after payment approval'
);

SELECT is(
 (SELECT status FROM public.order_reservations WHERE order_id='d7000000-0000-4000-8000-000000000011'),
 'consumed',
 'reservation is consumed with payment settlement'
);

SELECT ok(
 EXISTS(
  SELECT 1 FROM public.admin_audit_logs
  WHERE action='verify_payment'
    AND entity_id='d7000000-0000-4000-8000-000000000011'
    AND (metadata->'superseded_payment_ids') @> jsonb_build_array('d7000000-0000-4000-8000-000000000022')
    AND (metadata->>'superseded_payment_count')='2'
 ),
 'payment audit records all superseded attempts'
);

SELECT is(
 public.admin_apply_payment_verification(
  'd7000000-0000-4000-8000-000000000011',
  'd7000000-0000-4000-8000-000000000021',
  'd7000000-0000-4000-8000-000000000001',
  'paid','duplicate approval'
 ),
 false,
 'a repeated approval cannot settle an already-paid order again'
);

SELECT ok(
 EXISTS(select 1 from pg_indexes where schemaname='public' and indexname='payment_records_one_paid_per_order_idx'),
 'database enforces at most one paid payment record per order'
);

SELECT ok(
 NOT has_function_privilege('authenticated','public.admin_apply_payment_verification(uuid,uuid,uuid,text,text)','EXECUTE')
 AND has_function_privilege('service_role','public.admin_apply_payment_verification(uuid,uuid,uuid,text,text)','EXECUTE'),
 'payment verification RPC remains service-role only'
);

SELECT * FROM finish();
ROLLBACK;
