BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(14);

INSERT INTO public.tenants (id,slug,legal_name)
VALUES ('d1000000-0000-4000-8000-000000000001','qa-expiry-20261121','QA Expiry')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.branches (id,code,name,status,accepts_online_orders,pickup_enabled,delivery_enabled,tenant_id)
VALUES ('d1000000-0000-4000-8000-000000000002','QA-EXP-20261121','QA Expiry','active',true,true,false,'d1000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO UPDATE SET status='active',accepts_online_orders=true,pickup_enabled=true,delivery_enabled=false;
INSERT INTO public.products (id,slug,name,unit_price_idr,is_active,category,display_order)
VALUES ('d1000000-0000-4000-8000-000000000003','qa-expiry-20261121','QA Expiry Product',1000,true,'other',99998)
ON CONFLICT (id) DO UPDATE SET is_active=true,unit_price_idr=1000;

CREATE TEMP TABLE test_order_ids(kind text PRIMARY KEY,id uuid);
INSERT INTO public.orders (id,tracking_token_hash,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,product_subtotal_idr,payment_status,operational_status,fulfillment_status,branch_id)
VALUES
 ('d1000000-0000-4000-8000-000000000011',repeat('1',64),'QA Expired','6280000000001',current_date+3,'12:00','pickup',1000,'unpaid','received','unassigned','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000012',repeat('2',64),'QA Held','6280000000002',current_date+3,'12:00','pickup',1000,'pending_verification','received','unassigned','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000013',repeat('3',64),'QA Reject','6280000000003',current_date+3,'12:00','pickup',1000,'pending_verification','received','unassigned','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000014',repeat('4',64),'QA Paid','6280000000004',current_date+3,'12:00','pickup',1000,'paid','received','unassigned','d1000000-0000-4000-8000-000000000002');
INSERT INTO test_order_ids VALUES
 ('expired','d1000000-0000-4000-8000-000000000011'),
 ('held','d1000000-0000-4000-8000-000000000012'),
 ('reject','d1000000-0000-4000-8000-000000000013'),
 ('paid','d1000000-0000-4000-8000-000000000014');

INSERT INTO public.order_reservations (order_id,product_id,service_date,quantity,status,expires_at,branch_id)
VALUES
 ('d1000000-0000-4000-8000-000000000011','d1000000-0000-4000-8000-000000000003',current_date+3,1,'active',now()-interval '2 minutes','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000012','d1000000-0000-4000-8000-000000000003',current_date+3,1,'held_for_verification',now()-interval '2 minutes','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000013','d1000000-0000-4000-8000-000000000003',current_date+3,1,'held_for_verification',now()+interval '10 minutes','d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000014','d1000000-0000-4000-8000-000000000003',current_date+3,1,'consumed',now()-interval '2 minutes','d1000000-0000-4000-8000-000000000002');

CREATE TEMP TABLE test_payment_ids(kind text PRIMARY KEY,id uuid);
INSERT INTO public.payment_records (order_id,method,amount_idr,status,proof_storage_path,receipt_version)
VALUES ('d1000000-0000-4000-8000-000000000011','bank_transfer',1000,'pending_verification',NULL,1)
RETURNING id;
