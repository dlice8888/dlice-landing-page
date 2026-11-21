BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(7);

INSERT INTO public.tenants (id, slug, legal_name)
VALUES ('c1000000-0000-4000-8000-000000000001', 'qa-online-idempotency-20261121', 'QA Online Idempotency')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.branches (
  id, code, name, status, accepts_online_orders, pickup_enabled, delivery_enabled, tenant_id
) VALUES (
  'c1000000-0000-4000-8000-000000000002', 'QA-OI-20261121', 'QA Online Idempotency',
  'active', true, true, false, 'c1000000-0000-4000-8000-000000000001'
) ON CONFLICT (id) DO UPDATE SET
  status='active', accepts_online_orders=true, pickup_enabled=true, delivery_enabled=false;

INSERT INTO public.products (id, slug, name, unit_price_idr, is_active, category, display_order)
VALUES (
  'c1000000-0000-4000-8000-000000000003',
  'qa-online-idempotency-20261121',
  'QA Online Idempotency Product',
  1000, true, 'other', 99999
) ON CONFLICT (id) DO UPDATE SET
  slug=excluded.slug, name=excluded.name, unit_price_idr=excluded.unit_price_idr,
  is_active=true, category='other', display_order=99999;

INSERT INTO public.product_capacity (product_id, service_date, capacity)
VALUES ('c1000000-0000-4000-8000-000000000003', current_date + 3, 100)
ON CONFLICT (product_id, service_date) DO UPDATE SET capacity=100;

INSERT INTO public.branch_product_capacity (branch_id, product_id, service_date, capacity)
VALUES (
  'c1000000-0000-4000-8000-000000000002',
  'c1000000-0000-4000-8000-000000000003',
  current_date + 3, 100
) ON CONFLICT (branch_id, product_id, service_date) DO UPDATE SET capacity=100;

CREATE TEMP TABLE test_online_order_first AS
SELECT public.create_order_with_reservations(
  jsonb_build_object(
    'customer_name','QA Idempotency',
    'customer_whatsapp','6280000000000',
    'requested_date',(current_date + 3)::text,
    'requested_time','12:00',
    'receiving_method','pickup',
    'branch_id','c1000000-0000-4000-8000-000000000002',
    'branch_selection_source','customer_choice',
    'idempotency_key_hash',repeat('a',64),
    'idempotency_request_fingerprint',repeat('b',64)
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id','c1000000-0000-4000-8000-000000000003',
    'quantity',1
  )),
  repeat('a',64)
) AS response;

SELECT is(
  (SELECT response->>'idempotent_replay' FROM test_online_order_first),
  'false',
  'first request creates an order and is not a replay'
);

CREATE TEMP TABLE test_online_order_replay AS
SELECT public.create_order_with_reservations(
  jsonb_build_object(
    'customer_name','QA Idempotency',
    'customer_whatsapp','6280000000000',
    'requested_date',(current_date + 3)::text,
    'requested_time','12:00',
    'receiving_method','pickup',
    'branch_id','c1000000-0000-4000-8000-000000000002',
    'branch_selection_source','customer_choice',
    'idempotency_key_hash',repeat('a',64),
    'idempotency_request_fingerprint',repeat('b',64)
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id','c1000000-0000-4000-8000-000000000003',
    'quantity',1
  )),
  repeat('a',64)
) AS response;

SELECT is(
  (SELECT response->>'idempotent_replay' FROM test_online_order_replay),
  'true',
  'retry returns a replay response'
);
SELECT is(
  (SELECT response->>'order_id' FROM test_online_order_replay),
  (SELECT response->>'order_id' FROM test_online_order_first),
  'retry returns the exact same order id'
);
SELECT throws_ok(
  $$SELECT public.create_order_with_reservations(
    jsonb_build_object(
      'customer_name','QA Idempotency',
      'customer_whatsapp','6280000000000',
      'requested_date',(current_date + 3)::text,
      'requested_time','12:00',
      'receiving_method','pickup',
      'branch_id','c1000000-0000-4000-8000-000000000002',
      'branch_selection_source','customer_choice',
      'idempotency_key_hash',repeat('a',64),
      'idempotency_request_fingerprint',repeat('c',64)
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id','c1000000-0000-4000-8000-000000000003',
      'quantity',1
    )),
    repeat('a',64)
  )$$,
  '23505',
  'idempotency_key_payload_mismatch',
  'rejects reuse of a key with a different payload'
);
SELECT is(
  (SELECT count(*)::integer FROM public.orders WHERE tracking_token_hash=repeat('a',64)),
  1,
  'concurrent/retried requests cannot create duplicate orders for the same key'
);
SELECT is(
  (SELECT count(*)::integer FROM public.online_order_idempotency WHERE idempotency_key_hash=repeat('a',64)),
  1,
  'one durable idempotency record is stored for the order'
);
SELECT is(
  (SELECT count(*)::integer FROM public.order_reservations
   WHERE order_id=(SELECT (response->>'order_id')::uuid FROM test_online_order_first)),
  1,
  'retry does not duplicate capacity reservations'
);

SELECT * FROM finish();
ROLLBACK;
