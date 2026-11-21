-- Disposable-only fixtures for API/runtime fault injection. Never run against staging or production.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

INSERT INTO public.tenants (id, slug, legal_name)
VALUES ('c1000000-0000-4000-8000-000000000001','qa-runtime-faults-local','QA Runtime Faults Local')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.branches (id, code, name, status, accepts_online_orders, pickup_enabled, delivery_enabled, tenant_id)
VALUES ('c1000000-0000-4000-8000-000000000002','QA-RUNTIME-LOCAL','QA Runtime Faults Local','active',true,true,false,'c1000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO UPDATE SET status='active', accepts_online_orders=true, pickup_enabled=true, delivery_enabled=false;

INSERT INTO public.products (id, slug, name, unit_price_idr, is_active, category, display_order)
VALUES ('c1000000-0000-4000-8000-000000000003','qa-runtime-faults-local','QA Runtime Faults Local Product',1000,true,'other',99990)
ON CONFLICT (id) DO UPDATE SET slug=excluded.slug, name=excluded.name, unit_price_idr=1000, is_active=true, category='other', display_order=99990;

INSERT INTO public.product_capacity (product_id, service_date, capacity)
VALUES
 ('c1000000-0000-4000-8000-000000000003',current_date+3,100),
 ('c1000000-0000-4000-8000-000000000003',current_date+4,1)
ON CONFLICT (product_id,service_date) DO UPDATE SET capacity=excluded.capacity;

INSERT INTO public.branch_product_capacity (branch_id,product_id,service_date,capacity)
VALUES
 ('c1000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000003',current_date+3,100),
 ('c1000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000003',current_date+4,1)
ON CONFLICT (branch_id,product_id,service_date) DO UPDATE SET capacity=excluded.capacity;

INSERT INTO storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
VALUES ('dlice-payment-proofs','dlice-payment-proofs',false,5242880,ARRAY['image/jpeg','image/png','image/webp','application/pdf'])
ON CONFLICT (id) DO UPDATE SET public=false,file_size_limit=5242880,allowed_mime_types=EXCLUDED.allowed_mime_types;

INSERT INTO public.orders
(id,tracking_token_hash,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,
 product_subtotal_idr,payment_status,operational_status,fulfillment_status,branch_id,
 receipt_version,receipt_confirmed_version,receipt_snapshot)
VALUES
('d2000000-0000-4000-8000-000000000101',encode(extensions.digest(repeat('a',64),'sha256'),'hex'),'QA Upload Failure','6280000000001',current_date+3,'12:00','pickup',1500,'unpaid','received','unassigned','c1000000-0000-4000-8000-000000000002',1,1,'{"payment_method":"bank_transfer","payment_instruction":{"bank":"LOCAL QA","account":"0000"}}'),
('d2000000-0000-4000-8000-000000000102',encode(extensions.digest(repeat('b',64),'sha256'),'hex'),'QA RPC Failure','6280000000002',current_date+3,'12:00','pickup',1500,'unpaid','received','unassigned','c1000000-0000-4000-8000-000000000002',1,1,'{"payment_method":"bank_transfer","payment_instruction":{"bank":"LOCAL QA","account":"0000"}}'),
('d2000000-0000-4000-8000-000000000103',encode(extensions.digest(repeat('c',64),'sha256'),'hex'),'QA Compensation Failure','6280000000003',current_date+3,'12:00','pickup',1500,'unpaid','received','unassigned','c1000000-0000-4000-8000-000000000002',1,1,'{"payment_method":"bank_transfer","payment_instruction":{"bank":"LOCAL QA","account":"0000"}}'),
('d2000000-0000-4000-8000-000000000104',encode(extensions.digest(repeat('d',64),'sha256'),'hex'),'QA Expiry Race','6280000000004',current_date+3,'12:00','pickup',1500,'unpaid','received','unassigned','c1000000-0000-4000-8000-000000000002',1,1,'{"payment_method":"bank_transfer","payment_instruction":{"bank":"LOCAL QA","account":"0000"}}'),
('d2000000-0000-4000-8000-000000000105',encode(extensions.digest(repeat('e',64),'sha256'),'hex'),'QA Expiry Worker','6280000000005',current_date+3,'12:00','pickup',1500,'unpaid','received','unassigned','c1000000-0000-4000-8000-000000000002',1,1,'{"payment_method":"bank_transfer","payment_instruction":{"bank":"LOCAL QA","account":"0000"}}')
ON CONFLICT (id) DO UPDATE SET payment_status='unpaid',operational_status='received',fulfillment_status='unassigned',receipt_version=1,receipt_confirmed_version=1;

INSERT INTO public.order_reservations(order_id,product_id,service_date,quantity,status,expires_at,branch_id)
VALUES
('d2000000-0000-4000-8000-000000000101','c1000000-0000-4000-8000-000000000003',current_date+3,1,'active',now()+interval '1 hour','c1000000-0000-4000-8000-000000000002'),
('d2000000-0000-4000-8000-000000000102','c1000000-0000-4000-8000-000000000003',current_date+3,1,'active',now()+interval '1 hour','c1000000-0000-4000-8000-000000000002'),
('d2000000-0000-4000-8000-000000000103','c1000000-0000-4000-8000-000000000003',current_date+3,1,'active',now()+interval '1 hour','c1000000-0000-4000-8000-000000000002'),
('d2000000-0000-4000-8000-000000000104','c1000000-0000-4000-8000-000000000003',current_date+3,1,'active',now()+interval '1 hour','c1000000-0000-4000-8000-000000000002'),
('d2000000-0000-4000-8000-000000000105','c1000000-0000-4000-8000-000000000003',current_date+3,1,'active',now()-interval '2 minutes','c1000000-0000-4000-8000-000000000002')
;
