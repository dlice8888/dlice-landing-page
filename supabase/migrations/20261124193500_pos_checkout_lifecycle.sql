BEGIN;

-- A sale remains paid only when its complete tender allocation has been committed.
-- The split wrapper uses the existing atomic sale/idempotency/stock routine, then records
-- the tender breakdown in the same transaction and adjusts cash drawer expectations.
ALTER TABLE public.pos_sales
  DROP CONSTRAINT IF EXISTS pos_sales_payment_method_check;
ALTER TABLE public.pos_sales
  ADD CONSTRAINT pos_sales_payment_method_check
  CHECK (payment_method = ANY (ARRAY['cash','bank_transfer','qris','split']));

ALTER TABLE public.pos_sales
  ADD CONSTRAINT pos_sales_id_branch_id_key UNIQUE (id, branch_id);
ALTER TABLE public.pos_shifts
  ADD CONSTRAINT pos_shifts_id_branch_id_key UNIQUE (id, branch_id);

CREATE TABLE public.pos_sale_tenders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  tender_sequence smallint NOT NULL CHECK (tender_sequence BETWEEN 1 AND 5),
  payment_method text NOT NULL CHECK (payment_method IN ('cash','bank_transfer','qris')),
  amount_idr bigint NOT NULL CHECK (amount_idr > 0),
  reference text,
  created_by uuid NOT NULL REFERENCES public.admin_profiles(user_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pos_sale_tenders_sale_branch_fkey
    FOREIGN KEY (sale_id, branch_id)
    REFERENCES public.pos_sales(id, branch_id) ON DELETE RESTRICT,
  CONSTRAINT pos_sale_tenders_sale_sequence_key UNIQUE (sale_id, tender_sequence)
);
CREATE INDEX pos_sale_tenders_branch_created_idx
  ON public.pos_sale_tenders (branch_id, created_at DESC);
CREATE INDEX pos_sale_tenders_sale_id_idx
  ON public.pos_sale_tenders (sale_id);

CREATE TABLE public.pos_checkout_idempotency_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES public.admin_profiles(user_id) ON DELETE RESTRICT,
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 8 AND 120),
  payload_fingerprint text NOT NULL CHECK (payload_fingerprint ~ '^[0-9a-f]{64}$'),
  response jsonb NOT NULL CHECK (jsonb_typeof(response) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pos_checkout_idempotency_actor_key
    UNIQUE (branch_id, actor_user_id, idempotency_key)
);
CREATE INDEX pos_checkout_idempotency_created_idx
  ON public.pos_checkout_idempotency_requests (created_at);

CREATE TABLE public.pos_held_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  shift_id uuid NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES public.admin_profiles(user_id) ON DELETE RESTRICT,
  hold_key text NOT NULL CHECK (length(hold_key) BETWEEN 8 AND 120),
  payload_fingerprint text NOT NULL CHECK (payload_fingerprint ~ '^[0-9a-f]{64}$'),
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  status text NOT NULL DEFAULT 'held'
    CHECK (status IN ('held','resumed','cancelled','expired')),
  held_at timestamptz NOT NULL DEFAULT now(),
  resumed_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  CONSTRAINT pos_held_orders_shift_branch_fkey
    FOREIGN KEY (shift_id, branch_id)
    REFERENCES public.pos_shifts(id, branch_id) ON DELETE RESTRICT,
  CONSTRAINT pos_held_orders_branch_actor_key
    UNIQUE (branch_id, actor_user_id, hold_key),
  CONSTRAINT pos_held_orders_resumed_at_check
    CHECK ((status = 'held' AND resumed_at IS NULL) OR (status <> 'held' AND resumed_at IS NOT NULL))
);
CREATE INDEX pos_held_orders_branch_status_idx
  ON public.pos_held_orders (branch_id, status, held_at DESC);

CREATE TABLE public.pos_sale_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  receipt_version integer NOT NULL DEFAULT 1 CHECK (receipt_version > 0),
  snapshot jsonb NOT NULL CHECK (jsonb_typeof(snapshot) = 'object'),
  created_by uuid NOT NULL REFERENCES public.admin_profiles(user_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pos_sale_receipts_sale_key UNIQUE (sale_id),
  CONSTRAINT pos_sale_receipts_sale_branch_fkey
    FOREIGN KEY (sale_id, branch_id)
    REFERENCES public.pos_sales(id, branch_id) ON DELETE RESTRICT
);
CREATE INDEX pos_sale_receipts_branch_created_idx
  ON public.pos_sale_receipts (branch_id, created_at DESC);

ALTER TABLE public.pos_sale_tenders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_checkout_idempotency_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_held_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_sale_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY pos_sale_tenders_deny_direct_client_access
  ON public.pos_sale_tenders FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);
CREATE POLICY pos_checkout_idempotency_deny_direct_client_access
  ON public.pos_checkout_idempotency_requests FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);
CREATE POLICY pos_held_orders_deny_direct_client_access
  ON public.pos_held_orders FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);
CREATE POLICY pos_sale_receipts_deny_direct_client_access
  ON public.pos_sale_receipts FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

REVOKE ALL ON public.pos_sale_tenders, public.pos_checkout_idempotency_requests,
  public.pos_held_orders, public.pos_sale_receipts FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_sale_tenders,
  public.pos_checkout_idempotency_requests, public.pos_held_orders,
  public.pos_sale_receipts TO service_role;

CREATE OR REPLACE FUNCTION public.erp_create_pos_sale_split_tender_idempotent(
  p_branch_id uuid,
  p_shift_id uuid,
  p_items jsonb,
  p_discount_idr bigint,
  p_customer_reference text,
  p_notes text,
  p_actor_user_id uuid,
  p_idempotency_key text,
  p_tenders jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $function$
DECLARE
  v_fingerprint text;
  v_prior public.pos_checkout_idempotency_requests%rowtype;
  v_result jsonb;
  v_sale_id uuid;
  v_total bigint;
  v_tender_total bigint := 0;
  v_cash_total bigint := 0;
  v_count integer := 0;
  v_methods text[] := ARRAY[]::text[];
  v_tender jsonb;
  v_method text;
  v_amount bigint;
  v_inner_key text;
BEGIN
  IF coalesce(auth.jwt() ->> 'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'service_role_required';
  END IF;
  IF p_idempotency_key IS NULL OR length(trim(p_idempotency_key)) < 8
     OR length(p_idempotency_key) > 120 THEN
    RAISE EXCEPTION 'invalid_idempotency_key';
  END IF;
  IF jsonb_typeof(p_tenders) <> 'array'
     OR jsonb_array_length(p_tenders) < 2
     OR jsonb_array_length(p_tenders) > 5 THEN
    RAISE EXCEPTION 'invalid_split_tenders';
  END IF;
  v_fingerprint := encode(extensions.digest(jsonb_build_object(
    'branch_id', p_branch_id, 'shift_id', p_shift_id, 'items', p_items,
    'discount_idr', p_discount_idr, 'customer_reference', p_customer_reference,
    'notes', p_notes, 'tenders', p_tenders
  )::text, 'sha256'), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(
    p_branch_id::text || ':' || p_actor_user_id::text || ':' || p_idempotency_key, 0
  ));
  SELECT * INTO v_prior
  FROM public.pos_checkout_idempotency_requests
  WHERE branch_id = p_branch_id AND actor_user_id = p_actor_user_id
    AND idempotency_key = p_idempotency_key
  FOR UPDATE;
  IF FOUND THEN
    IF v_prior.payload_fingerprint <> v_fingerprint THEN
      RAISE EXCEPTION 'idempotency_key_payload_mismatch';
    END IF;
    RETURN v_prior.response || jsonb_build_object('idempotent_replay', true);
  END IF;

  FOR v_tender IN SELECT value FROM jsonb_array_elements(p_tenders) LOOP
    v_method := v_tender ->> 'payment_method';
    IF v_method IS NULL OR v_method NOT IN ('cash', 'bank_transfer', 'qris') THEN
      RAISE EXCEPTION 'invalid_tender_method';
    END IF;
    IF v_tender ->> 'amount_idr' IS NULL OR (v_tender ->> 'amount_idr') !~ '^[0-9]+
      RAISE EXCEPTION 'invalid_tender_amount';
    END IF;
    v_amount := (v_tender ->> 'amount_idr')::bigint;
    IF v_amount <= 0 OR v_amount > 1000000000 THEN
      RAISE EXCEPTION 'invalid_tender_amount';
    END IF;
    v_tender_total := v_tender_total + v_amount;
    IF v_tender_total > 1000000000 THEN RAISE EXCEPTION 'invalid_tender_amount'; END IF;
    IF v_method = 'cash' THEN v_cash_total := v_cash_total + v_amount; END IF;
    IF NOT v_method = ANY(v_methods) THEN v_methods := array_append(v_methods, v_method); END IF;
    v_count := v_count + 1;
  END LOOP;
  IF cardinality(v_methods) < 2 THEN RAISE EXCEPTION 'split_requires_distinct_methods'; END IF;

  -- Reuse the proven atomic sale path for price, modifiers, stock, KDS, and base idempotency.
  -- The wrapper and its tender ledger share this transaction; any later validation failure rolls it back.
  v_inner_key := 'split:' || encode(extensions.digest(p_idempotency_key, 'sha256'), 'hex');
  v_result := public.erp_create_pos_sale_idempotent(
    p_branch_id, p_shift_id, p_items, 'bank_transfer', p_discount_idr,
    p_customer_reference, p_notes, p_actor_user_id, v_inner_key
  );
  v_sale_id := (v_result ->> 'sale_id')::uuid;
  v_total := (v_result ->> 'total_idr')::bigint;
  IF v_total <= 0 OR v_tender_total <> v_total THEN
    RAISE EXCEPTION 'split_tender_total_mismatch';
  END IF;

  UPDATE public.pos_sales
  SET payment_method = 'split'
  WHERE id = v_sale_id AND branch_id = p_branch_id;

  v_count := 0;
  FOR v_tender IN SELECT value FROM jsonb_array_elements(p_tenders) LOOP
    v_count := v_count + 1;
    INSERT INTO public.pos_sale_tenders (
      sale_id, branch_id, tender_sequence, payment_method, amount_idr, reference, created_by
    ) VALUES (
      v_sale_id, p_branch_id, v_count, v_tender ->> 'payment_method',
      (v_tender ->> 'amount_idr')::bigint,
      nullif(left(trim(coalesce(v_tender ->> 'reference', '')), 120), ''),
      p_actor_user_id
    );
  END LOOP;

  IF v_cash_total > 0 THEN
    UPDATE public.pos_shifts
    SET expected_cash_idr = expected_cash_idr + v_cash_total
    WHERE id = p_shift_id AND branch_id = p_branch_id AND status = 'open';
    IF NOT FOUND THEN RAISE EXCEPTION 'open_shift_required'; END IF;
  END IF;

  v_result := v_result || jsonb_build_object(
    'payment_method', 'split',
    'tenders', p_tenders,
    'total_idr', v_total
  );
  INSERT INTO public.pos_checkout_idempotency_requests (
    branch_id, actor_user_id, idempotency_key, payload_fingerprint, response
  ) VALUES (
    p_branch_id, p_actor_user_id, p_idempotency_key, v_fingerprint, v_result
  );
  RETURN v_result || jsonb_build_object('idempotent_replay', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.erp_hold_pos_order(
  p_branch_id uuid,
  p_shift_id uuid,
  p_actor_user_id uuid,
  p_hold_key text,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $function$
DECLARE
  v_fingerprint text;
  v_prior public.pos_held_orders%rowtype;
  v_created public.pos_held_orders%rowtype;
BEGIN
  IF coalesce(auth.jwt() ->> 'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'service_role_required';
  END IF;
  IF p_hold_key IS NULL OR length(trim(p_hold_key)) < 8 OR length(p_hold_key) > 120
     OR jsonb_typeof(p_payload) <> 'object'
     OR jsonb_typeof(p_payload -> 'items') <> 'array'
     OR jsonb_array_length(p_payload -> 'items') < 1
     OR jsonb_array_length(p_payload -> 'items') > 50 THEN
    RAISE EXCEPTION 'invalid_held_order';
  END IF;
  PERFORM 1 FROM public.pos_shifts
  WHERE id = p_shift_id AND branch_id = p_branch_id
    AND opened_by = p_actor_user_id AND status = 'open'
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'open_shift_required'; END IF;
  v_fingerprint := encode(extensions.digest(p_payload::text, 'sha256'), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(
    p_branch_id::text || ':' || p_actor_user_id::text || ':' || p_hold_key, 0
  ));
  SELECT * INTO v_prior FROM public.pos_held_orders
  WHERE branch_id = p_branch_id AND actor_user_id = p_actor_user_id AND hold_key = p_hold_key
  FOR UPDATE;
  IF FOUND THEN
    IF v_prior.payload_fingerprint <> v_fingerprint THEN
      RAISE EXCEPTION 'hold_key_payload_mismatch';
    END IF;
    RETURN jsonb_build_object(
      'ok', true, 'hold_id', v_prior.id, 'status', v_prior.status,
      'payload', v_prior.payload, 'idempotent_replay', true
    );
  END IF;
  INSERT INTO public.pos_held_orders (
    branch_id, shift_id, actor_user_id, hold_key, payload_fingerprint, payload
  ) VALUES (
    p_branch_id, p_shift_id, p_actor_user_id, p_hold_key, v_fingerprint, p_payload
  ) RETURNING * INTO v_created;
  RETURN jsonb_build_object(
    'ok', true, 'hold_id', v_created.id, 'status', v_created.status,
    'payload', v_created.payload, 'idempotent_replay', false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.erp_resume_pos_order(
  p_branch_id uuid,
  p_hold_id uuid,
  p_actor_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $function$
DECLARE
  v_hold public.pos_held_orders%rowtype;
BEGIN
  IF coalesce(auth.jwt() ->> 'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'service_role_required';
  END IF;
  SELECT * INTO v_hold FROM public.pos_held_orders
  WHERE id = p_hold_id AND branch_id = p_branch_id AND actor_user_id = p_actor_user_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'held_order_not_found'; END IF;
  IF v_hold.status = 'resumed' THEN
    RETURN jsonb_build_object(
      'ok', true, 'hold_id', v_hold.id, 'status', v_hold.status,
      'payload', v_hold.payload, 'idempotent_replay', true,
      'sale_idempotency_key', 'hold:' || v_hold.id::text
    );
  END IF;
  IF v_hold.status <> 'held' THEN RAISE EXCEPTION 'held_order_not_resumable'; END IF;
  IF v_hold.expires_at <= now() THEN
    UPDATE public.pos_held_orders SET status = 'expired', resumed_at = now() WHERE id = v_hold.id;
    RETURN jsonb_build_object(
      'ok', false, 'hold_id', v_hold.id, 'status', 'expired',
      'payload', v_hold.payload, 'idempotent_replay', false
    );
  END IF;
  PERFORM 1 FROM public.pos_shifts
  WHERE id = v_hold.shift_id AND branch_id = v_hold.branch_id
    AND opened_by = p_actor_user_id AND status = 'open'
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'open_shift_required'; END IF;
  UPDATE public.pos_held_orders
  SET status = 'resumed', resumed_at = now()
  WHERE id = v_hold.id AND status = 'held';
  RETURN jsonb_build_object(
    'ok', true, 'hold_id', v_hold.id, 'status', 'resumed',
    'payload', v_hold.payload, 'idempotent_replay', false,
    'sale_idempotency_key', 'hold:' || v_hold.id::text
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.erp_get_pos_receipt(
  p_branch_id uuid,
  p_sale_id uuid,
  p_actor_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $function$
DECLARE
  v_existing public.pos_sale_receipts%rowtype;
  v_sale public.pos_sales%rowtype;
  v_snapshot jsonb;
  v_receipt public.pos_sale_receipts%rowtype;
BEGIN
  IF coalesce(auth.jwt() ->> 'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'service_role_required';
  END IF;
  SELECT * INTO v_existing FROM public.pos_sale_receipts
  WHERE sale_id = p_sale_id AND branch_id = p_branch_id;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', true, 'receipt_id', v_existing.id, 'receipt_version', v_existing.receipt_version,
      'snapshot', v_existing.snapshot, 'created_at', v_existing.created_at, 'replayed', true
    );
  END IF;
  SELECT * INTO v_sale FROM public.pos_sales
  WHERE id = p_sale_id AND branch_id = p_branch_id AND payment_status = 'paid'
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'paid_pos_sale_required'; END IF;
  SELECT jsonb_build_object(
    'transaction_code', v_sale.transaction_code,
    'branch_id', v_sale.branch_id,
    'sale_id', v_sale.id,
    'created_at', v_sale.created_at,
    'subtotal_idr', v_sale.subtotal_idr,
    'discount_idr', v_sale.discount_idr,
    'total_idr', v_sale.total_idr,
    'payment_method', v_sale.payment_method,
    'payment_status', v_sale.payment_status,
    'customer_reference', v_sale.customer_reference,
    'items', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'product_name', product_name_snapshot,
        'quantity', quantity,
        'unit_price_idr', unit_price_idr,
        'line_total_idr', line_total_idr,
        'modifiers', modifier_snapshot,
        'substitutions', substitution_snapshot
      ) ORDER BY id)
      FROM public.pos_sale_items WHERE sale_id = v_sale.id
    ), '[]'::jsonb),
    'tenders', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'payment_method', payment_method, 'amount_idr', amount_idr, 'reference', reference
      ) ORDER BY tender_sequence)
      FROM public.pos_sale_tenders WHERE sale_id = v_sale.id
    ), jsonb_build_array(jsonb_build_object(
      'payment_method', v_sale.payment_method, 'amount_idr', v_sale.total_idr, 'reference', null
    )))
  ) INTO v_snapshot;
  INSERT INTO public.pos_sale_receipts (sale_id, branch_id, snapshot, created_by)
  VALUES (v_sale.id, v_sale.branch_id, v_snapshot, p_actor_user_id)
  ON CONFLICT (sale_id) DO NOTHING;
  SELECT * INTO v_receipt FROM public.pos_sale_receipts
  WHERE sale_id = p_sale_id AND branch_id = p_branch_id;
  RETURN jsonb_build_object(
    'ok', true, 'receipt_id', v_receipt.id, 'receipt_version', v_receipt.receipt_version,
    'snapshot', v_receipt.snapshot, 'created_at', v_receipt.created_at, 'replayed', true
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.erp_create_pos_sale_split_tender_idempotent(uuid,uuid,jsonb,bigint,text,text,uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.erp_hold_pos_order(uuid,uuid,uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.erp_resume_pos_order(uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.erp_get_pos_receipt(uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.erp_create_pos_sale_split_tender_idempotent(uuid,uuid,jsonb,bigint,text,text,uuid,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.erp_hold_pos_order(uuid,uuid,uuid,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.erp_resume_pos_order(uuid,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.erp_get_pos_receipt(uuid,uuid,uuid) TO service_role;

COMMIT;
 THEN
      RAISE EXCEPTION 'invalid_tender_amount';
    END IF;
    v_amount := (v_tender ->> 'amount_idr')::bigint;
    IF v_amount <= 0 OR v_amount > 1000000000 THEN
      RAISE EXCEPTION 'invalid_tender_amount';
    END IF;
    v_tender_total := v_tender_total + v_amount;
    IF v_tender_total > 1000000000 THEN RAISE EXCEPTION 'invalid_tender_amount'; END IF;
    IF v_method = 'cash' THEN v_cash_total := v_cash_total + v_amount; END IF;
    IF NOT v_method = ANY(v_methods) THEN v_methods := array_append(v_methods, v_method); END IF;
    v_count := v_count + 1;
  END LOOP;
  IF cardinality(v_methods) < 2 THEN RAISE EXCEPTION 'split_requires_distinct_methods'; END IF;

  -- Reuse the proven atomic sale path for price, modifiers, stock, KDS, and base idempotency.
  -- The wrapper and its tender ledger share this transaction; any later validation failure rolls it back.
  v_inner_key := 'split:' || encode(extensions.digest(p_idempotency_key, 'sha256'), 'hex');
  v_result := public.erp_create_pos_sale_idempotent(
    p_branch_id, p_shift_id, p_items, 'bank_transfer', p_discount_idr,
    p_customer_reference, p_notes, p_actor_user_id, v_inner_key
  );
  v_sale_id := (v_result ->> 'sale_id')::uuid;
  v_total := (v_result ->> 'total_idr')::bigint;
  IF v_total <= 0 OR v_tender_total <> v_total THEN
    RAISE EXCEPTION 'split_tender_total_mismatch';
  END IF;

  UPDATE public.pos_sales
  SET payment_method = 'split'
  WHERE id = v_sale_id AND branch_id = p_branch_id;

  v_count := 0;
  FOR v_tender IN SELECT value FROM jsonb_array_elements(p_tenders) LOOP
    v_count := v_count + 1;
    INSERT INTO public.pos_sale_tenders (
      sale_id, branch_id, tender_sequence, payment_method, amount_idr, reference, created_by
    ) VALUES (
      v_sale_id, p_branch_id, v_count, v_tender ->> 'payment_method',
      (v_tender ->> 'amount_idr')::bigint,
      nullif(left(trim(coalesce(v_tender ->> 'reference', '')), 120), ''),
      p_actor_user_id
    );
  END LOOP;

  IF v_cash_total > 0 THEN
    UPDATE public.pos_shifts
    SET expected_cash_idr = expected_cash_idr + v_cash_total
    WHERE id = p_shift_id AND branch_id = p_branch_id AND status = 'open';
    IF NOT FOUND THEN RAISE EXCEPTION 'open_shift_required'; END IF;
  END IF;

  v_result := v_result || jsonb_build_object(
    'payment_method', 'split',
    'tenders', p_tenders,
    'total_idr', v_total
  );
  INSERT INTO public.pos_checkout_idempotency_requests (
    branch_id, actor_user_id, idempotency_key, payload_fingerprint, response
  ) VALUES (
    p_branch_id, p_actor_user_id, p_idempotency_key, v_fingerprint, v_result
  );
  RETURN v_result || jsonb_build_object('idempotent_replay', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.erp_hold_pos_order(
  p_branch_id uuid,
  p_shift_id uuid,
  p_actor_user_id uuid,
  p_hold_key text,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $function$
DECLARE
  v_fingerprint text;
  v_prior public.pos_held_orders%rowtype;
  v_created public.pos_held_orders%rowtype;
BEGIN
  IF coalesce(auth.jwt() ->> 'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'service_role_required';
  END IF;
  IF p_hold_key IS NULL OR length(trim(p_hold_key)) < 8 OR length(p_hold_key) > 120
     OR jsonb_typeof(p_payload) <> 'object'
     OR jsonb_typeof(p_payload -> 'items') <> 'array'
     OR jsonb_array_length(p_payload -> 'items') < 1
     OR jsonb_array_length(p_payload -> 'items') > 50 THEN
    RAISE EXCEPTION 'invalid_held_order';
  END IF;
  PERFORM 1 FROM public.pos_shifts
  WHERE id = p_shift_id AND branch_id = p_branch_id
    AND opened_by = p_actor_user_id AND status = 'open'
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'open_shift_required'; END IF;
  v_fingerprint := encode(extensions.digest(p_payload::text, 'sha256'), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(
    p_branch_id::text || ':' || p_actor_user_id::text || ':' || p_hold_key, 0
  ));
  SELECT * INTO v_prior FROM public.pos_held_orders
  WHERE branch_id = p_branch_id AND actor_user_id = p_actor_user_id AND hold_key = p_hold_key
  FOR UPDATE;
  IF FOUND THEN
    IF v_prior.payload_fingerprint <> v_fingerprint THEN
      RAISE EXCEPTION 'hold_key_payload_mismatch';
    END IF;
    RETURN jsonb_build_object(
      'ok', true, 'hold_id', v_prior.id, 'status', v_prior.status,
      'payload', v_prior.payload, 'idempotent_replay', true
    );
  END IF;
  INSERT INTO public.pos_held_orders (
    branch_id, shift_id, actor_user_id, hold_key, payload_fingerprint, payload
  ) VALUES (
    p_branch_id, p_shift_id, p_actor_user_id, p_hold_key, v_fingerprint, p_payload
  ) RETURNING * INTO v_created;
  RETURN jsonb_build_object(
    'ok', true, 'hold_id', v_created.id, 'status', v_created.status,
    'payload', v_created.payload, 'idempotent_replay', false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.erp_resume_pos_order(
  p_branch_id uuid,
  p_hold_id uuid,
  p_actor_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $function$
DECLARE
  v_hold public.pos_held_orders%rowtype;
BEGIN
  IF coalesce(auth.jwt() ->> 'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'service_role_required';
  END IF;
  SELECT * INTO v_hold FROM public.pos_held_orders
  WHERE id = p_hold_id AND branch_id = p_branch_id AND actor_user_id = p_actor_user_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'held_order_not_found'; END IF;
  IF v_hold.status = 'resumed' THEN
    RETURN jsonb_build_object(
      'ok', true, 'hold_id', v_hold.id, 'status', v_hold.status,
      'payload', v_hold.payload, 'idempotent_replay', true,
      'sale_idempotency_key', 'hold:' || v_hold.id::text
    );
  END IF;
  IF v_hold.status <> 'held' THEN RAISE EXCEPTION 'held_order_not_resumable'; END IF;
  IF v_hold.expires_at <= now() THEN
    UPDATE public.pos_held_orders SET status = 'expired', resumed_at = now() WHERE id = v_hold.id;
    RETURN jsonb_build_object(
      'ok', false, 'hold_id', v_hold.id, 'status', 'expired',
      'payload', v_hold.payload, 'idempotent_replay', false
    );
  END IF;
  PERFORM 1 FROM public.pos_shifts
  WHERE id = v_hold.shift_id AND branch_id = v_hold.branch_id
    AND opened_by = p_actor_user_id AND status = 'open'
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'open_shift_required'; END IF;
  UPDATE public.pos_held_orders
  SET status = 'resumed', resumed_at = now()
  WHERE id = v_hold.id AND status = 'held';
  RETURN jsonb_build_object(
    'ok', true, 'hold_id', v_hold.id, 'status', 'resumed',
    'payload', v_hold.payload, 'idempotent_replay', false,
    'sale_idempotency_key', 'hold:' || v_hold.id::text
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.erp_get_pos_receipt(
  p_branch_id uuid,
  p_sale_id uuid,
  p_actor_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $function$
DECLARE
  v_existing public.pos_sale_receipts%rowtype;
  v_sale public.pos_sales%rowtype;
  v_snapshot jsonb;
  v_receipt public.pos_sale_receipts%rowtype;
BEGIN
  IF coalesce(auth.jwt() ->> 'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'service_role_required';
  END IF;
  SELECT * INTO v_existing FROM public.pos_sale_receipts
  WHERE sale_id = p_sale_id AND branch_id = p_branch_id;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', true, 'receipt_id', v_existing.id, 'receipt_version', v_existing.receipt_version,
      'snapshot', v_existing.snapshot, 'created_at', v_existing.created_at, 'replayed', true
    );
  END IF;
  SELECT * INTO v_sale FROM public.pos_sales
  WHERE id = p_sale_id AND branch_id = p_branch_id AND payment_status = 'paid'
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'paid_pos_sale_required'; END IF;
  SELECT jsonb_build_object(
    'transaction_code', v_sale.transaction_code,
    'branch_id', v_sale.branch_id,
    'sale_id', v_sale.id,
    'created_at', v_sale.created_at,
    'subtotal_idr', v_sale.subtotal_idr,
    'discount_idr', v_sale.discount_idr,
    'total_idr', v_sale.total_idr,
    'payment_method', v_sale.payment_method,
    'payment_status', v_sale.payment_status,
    'customer_reference', v_sale.customer_reference,
    'items', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'product_name', product_name_snapshot,
        'quantity', quantity,
        'unit_price_idr', unit_price_idr,
        'line_total_idr', line_total_idr,
        'modifiers', modifier_snapshot,
        'substitutions', substitution_snapshot
      ) ORDER BY id)
      FROM public.pos_sale_items WHERE sale_id = v_sale.id
    ), '[]'::jsonb),
    'tenders', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'payment_method', payment_method, 'amount_idr', amount_idr, 'reference', reference
      ) ORDER BY tender_sequence)
      FROM public.pos_sale_tenders WHERE sale_id = v_sale.id
    ), jsonb_build_array(jsonb_build_object(
      'payment_method', v_sale.payment_method, 'amount_idr', v_sale.total_idr, 'reference', null
    )))
  ) INTO v_snapshot;
  INSERT INTO public.pos_sale_receipts (sale_id, branch_id, snapshot, created_by)
  VALUES (v_sale.id, v_sale.branch_id, v_snapshot, p_actor_user_id)
  ON CONFLICT (sale_id) DO NOTHING;
  SELECT * INTO v_receipt FROM public.pos_sale_receipts
  WHERE sale_id = p_sale_id AND branch_id = p_branch_id;
  RETURN jsonb_build_object(
    'ok', true, 'receipt_id', v_receipt.id, 'receipt_version', v_receipt.receipt_version,
    'snapshot', v_receipt.snapshot, 'created_at', v_receipt.created_at, 'replayed', true
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.erp_create_pos_sale_split_tender_idempotent(uuid,uuid,jsonb,bigint,text,text,uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.erp_hold_pos_order(uuid,uuid,uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.erp_resume_pos_order(uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.erp_get_pos_receipt(uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.erp_create_pos_sale_split_tender_idempotent(uuid,uuid,jsonb,bigint,text,text,uuid,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.erp_hold_pos_order(uuid,uuid,uuid,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.erp_resume_pos_order(uuid,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.erp_get_pos_receipt(uuid,uuid,uuid) TO service_role;

COMMIT;
