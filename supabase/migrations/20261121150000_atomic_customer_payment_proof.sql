-- Atomic customer payment-proof declaration.
-- Storage upload remains outside the Postgres transaction; the Edge Function removes
-- the uploaded object when this RPC rejects or errors. A process crash between the
-- Storage upload and RPC can still leave an orphan object; the Edge Function performs
-- best-effort per-order cleanup on subsequent successful proof uploads.
ALTER TABLE public.payment_records
  ADD COLUMN IF NOT EXISTS proof_upload_key uuid;

CREATE UNIQUE INDEX IF NOT EXISTS payment_records_proof_upload_key_uidx
  ON public.payment_records (proof_upload_key)
  WHERE proof_upload_key IS NOT NULL;

CREATE OR REPLACE FUNCTION public.submit_customer_payment_proof_atomic(
  p_order_id uuid,
  p_upload_key uuid,
  p_method text,
  p_amount_idr integer,
  p_proof_storage_path text,
  p_receipt_version integer,
  p_payment_instruction_snapshot jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
DECLARE
  v_order public.orders%ROWTYPE;
  v_payment_id uuid;
  v_existing_path text;
  v_reservation_count integer := 0;
  v_reservations_valid boolean := false;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF p_order_id IS NULL OR p_upload_key IS NULL OR p_method IS NULL
     OR p_method NOT IN ('bank_transfer','dlice_qris')
     OR p_amount_idr IS NULL OR p_amount_idr < 0
     OR p_receipt_version IS NULL OR p_receipt_version < 1
     OR p_proof_storage_path IS NULL
     OR length(p_proof_storage_path) > 500
     OR p_proof_storage_path NOT LIKE p_order_id::text || '/%'
     OR position('..' in p_proof_storage_path) > 0
     OR p_payment_instruction_snapshot IS NULL
     OR jsonb_typeof(p_payment_instruction_snapshot) <> 'object'
  THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_input');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','order_not_found');
  END IF;

  -- A retry with the same client key is successful even if the order was
  -- subsequently verified, because the first transaction already committed.
  SELECT id, proof_storage_path
    INTO v_payment_id, v_existing_path
  FROM public.payment_records
  WHERE order_id = p_order_id AND proof_upload_key = p_upload_key
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok',true,'payment_id',v_payment_id,'idempotent_replay',true
    );
  END IF;

  IF v_order.payment_status NOT IN ('unpaid','pending_verification') THEN
    RETURN jsonb_build_object('ok',false,'code','order_payment_closed');
  END IF;

  IF p_amount_idr <> v_order.product_subtotal_idr
     OR p_receipt_version <> v_order.receipt_version
     OR v_order.receipt_confirmed_version IS DISTINCT FROM p_receipt_version
     OR v_order.receipt_snapshot->>'payment_method' IS DISTINCT FROM p_method
     OR v_order.receipt_snapshot->'payment_instruction' IS DISTINCT FROM p_payment_instruction_snapshot
  THEN
    RETURN jsonb_build_object('ok',false,'code','receipt_changed');
  END IF;

  -- Lock reservation rows after the order row. The expiry worker locks the order
  -- first as well, so proof upload and expiry serialize without a race.
  PERFORM 1
  FROM public.order_reservations
  WHERE order_id = p_order_id
  ORDER BY id
  FOR UPDATE;

  SELECT count(*),
         coalesce(bool_and(
           (status = 'active' AND expires_at > v_now)
           OR (status = 'held_for_verification' AND expires_at > v_now)
         ),false)
    INTO v_reservation_count, v_reservations_valid
  FROM public.order_reservations
  WHERE order_id = p_order_id;

  IF v_reservation_count = 0 OR NOT v_reservations_valid THEN
    RETURN jsonb_build_object('ok',false,'code','reservation_expired');
  END IF;

  -- Do not overwrite a previously submitted proof. A new key is a distinct
  -- customer submission and must not silently replace evidence under review.
  SELECT id INTO v_payment_id
  FROM public.payment_records
  WHERE order_id = p_order_id
    AND status = 'pending_verification'
    AND proof_storage_path IS NOT NULL
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','proof_already_pending');
  END IF;

  SELECT id INTO v_payment_id
  FROM public.payment_records
  WHERE order_id = p_order_id
    AND status = 'pending_verification'
    AND proof_storage_path IS NULL
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    UPDATE public.payment_records
    SET method = p_method,
        amount_idr = p_amount_idr,
        proof_storage_path = p_proof_storage_path,
        receipt_version = p_receipt_version,
        payment_instruction_snapshot = p_payment_instruction_snapshot,
        proof_upload_key = p_upload_key,
        updated_at = v_now
    WHERE id = v_payment_id;
  ELSE
    INSERT INTO public.payment_records
      (order_id,method,amount_idr,status,proof_storage_path,
       receipt_version,payment_instruction_snapshot,proof_upload_key,created_at,updated_at)
    VALUES
      (p_order_id,p_method,p_amount_idr,'pending_verification',p_proof_storage_path,
       p_receipt_version,p_payment_instruction_snapshot,p_upload_key,v_now,v_now)
    RETURNING id INTO v_payment_id;
  END IF;

  UPDATE public.order_reservations
  SET status = 'held_for_verification',
      proof_received_at = v_now,
      updated_at = v_now
  WHERE order_id = p_order_id
    AND status IN ('active','held_for_verification');

  UPDATE public.orders
  SET payment_status = 'pending_verification',
      updated_at = v_now
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history
    (order_id,status_type,old_status,new_status,changed_by,note)
  VALUES
    (p_order_id,'payment',v_order.payment_status,'pending_verification',NULL,
     'Customer payment proof uploaded; awaiting admin verification.');

  INSERT INTO public.admin_audit_logs
    (actor_user_id,action,entity_type,entity_id,metadata)
  VALUES
    (NULL,'customer_payment_proof_uploaded','order',p_order_id::text,
     jsonb_build_object('payment_id',v_payment_id,'method',p_method,
       'amount_idr',p_amount_idr,'receipt_version',p_receipt_version,
       'upload_key',p_upload_key,'uploaded_at',v_now));

  RETURN jsonb_build_object(
    'ok',true,'payment_id',v_payment_id,'idempotent_replay',false
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_customer_payment_proof_atomic(uuid,uuid,text,integer,text,integer,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_customer_payment_proof_atomic(uuid,uuid,text,integer,text,integer,jsonb)
  TO service_role;
