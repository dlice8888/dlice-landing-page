BEGIN;

ALTER TABLE public.payment_records
  ADD COLUMN IF NOT EXISTS superseded_by_payment_id uuid
    REFERENCES public.payment_records(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS superseded_at timestamptz;

ALTER TABLE public.payment_records
  DROP CONSTRAINT IF EXISTS payment_records_status_check;

ALTER TABLE public.payment_records
  ADD CONSTRAINT payment_records_status_check
  CHECK (status = ANY (ARRAY[
    'unpaid'::text,
    'pending_verification'::text,
    'paid'::text,
    'rejected'::text,
    'refunded'::text,
    'superseded'::text
  ]));

ALTER TABLE public.payment_records
  ADD CONSTRAINT payment_records_supersession_state_check
  CHECK (
    (status = 'superseded' AND superseded_by_payment_id IS NOT NULL AND superseded_at IS NOT NULL)
    OR
    (status <> 'superseded' AND superseded_by_payment_id IS NULL AND superseded_at IS NULL)
  );

CREATE INDEX IF NOT EXISTS payment_records_superseded_by_payment_idx
  ON public.payment_records(superseded_by_payment_id)
  WHERE superseded_by_payment_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS payment_records_one_paid_per_order_idx
  ON public.payment_records(order_id)
  WHERE status = 'paid';

CREATE OR REPLACE FUNCTION public.admin_apply_payment_verification(
  p_order_id uuid,
  p_payment_id uuid,
  p_actor_user_id uuid,
  p_result text,
  p_note text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_old_status text;
  v_proof_path text;
  v_payment_status text;
  v_superseded_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  IF p_result NOT IN ('paid','rejected') THEN
    RAISE EXCEPTION 'Invalid payment result';
  END IF;

  SELECT payment_status INTO v_old_status
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_old_status IN ('paid','refunded') THEN
    RETURN false;
  END IF;

  SELECT status, proof_storage_path INTO v_payment_status, v_proof_path
  FROM public.payment_records
  WHERE id = p_payment_id AND order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_payment_status <> 'pending_verification' THEN
    RETURN false;
  END IF;
  IF p_result = 'paid' AND (v_proof_path IS NULL OR length(v_proof_path) = 0) THEN
    RETURN false;
  END IF;

  UPDATE public.payment_records
  SET status = p_result,
      verified_by = p_actor_user_id,
      verified_at = now(),
      admin_note = nullif(left(coalesce(p_note,''),500),'')
  WHERE id = p_payment_id;

  IF p_result = 'paid' THEN
    WITH superseded AS (
      UPDATE public.payment_records
      SET status = 'superseded',
          superseded_by_payment_id = p_payment_id,
          superseded_at = now(),
          admin_note = left(
            concat_ws(
              '; ',
              nullif(left(coalesce(admin_note,''),300),''),
              'Superseded by approved payment record ' || p_payment_id::text
            ),
            500
          )
      WHERE order_id = p_order_id
        AND id <> p_payment_id
        AND status IN ('unpaid','pending_verification')
      RETURNING id
    )
    SELECT coalesce(array_agg(id), ARRAY[]::uuid[])
    INTO v_superseded_ids
    FROM superseded;
  END IF;

  UPDATE public.orders
  SET payment_status = p_result
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history
    (order_id, status_type, old_status, new_status, changed_by, note)
  VALUES
    (p_order_id, 'payment', v_old_status, p_result, p_actor_user_id, nullif(left(coalesce(p_note,''),500),''));

  INSERT INTO public.admin_audit_logs
    (actor_user_id, action, entity_type, entity_id, metadata)
  VALUES
    (p_actor_user_id, 'verify_payment', 'order', p_order_id::text,
     jsonb_build_object(
       'result',p_result,
       'payment_id',p_payment_id,
       'note',left(coalesce(p_note,''),500),
       'superseded_payment_ids',v_superseded_ids,
       'superseded_payment_count',cardinality(v_superseded_ids)
     ));

  IF p_result = 'paid' THEN
    UPDATE public.order_reservations
    SET status = 'consumed'
    WHERE order_id = p_order_id AND status IN ('held_for_verification','active');
  ELSE
    UPDATE public.order_reservations
    SET status = 'released', released_at = now()
    WHERE order_id = p_order_id AND status IN ('held_for_verification','active');
  END IF;

  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_apply_payment_verification(uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_apply_payment_verification(uuid,uuid,uuid,text,text)
  TO service_role;

COMMIT;
