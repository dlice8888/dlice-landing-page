-- Order/payment lifecycle compensation and reservation expiry.
-- Existing paid/rejected payment verification is preserved from the live staging
-- function definition; rejected decisions now close the order and stale no-proof attempts.
ALTER TABLE public.order_status_history
  DROP CONSTRAINT IF EXISTS order_status_history_status_type_check;
ALTER TABLE public.order_status_history
  ADD CONSTRAINT order_status_history_status_type_check
  CHECK (status_type IN ('payment','operational','reservation','fulfillment'));

CREATE INDEX IF NOT EXISTS idx_order_reservations_active_expiry
  ON public.order_reservations (expires_at, order_id)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_payment_records_pending_without_proof
  ON public.payment_records (order_id, created_at)
  WHERE status = 'pending_verification' AND proof_storage_path IS NULL;

CREATE OR REPLACE FUNCTION public.admin_apply_payment_verification(p_order_id uuid, p_payment_id uuid, p_actor_user_id uuid, p_result text, p_note text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_old_status text;
  v_old_fulfillment_status text;
  v_old_operational_status text;
  v_proof_path text;
  v_payment_status text;
  v_closed_pending_attempts integer := 0;
begin
  if p_result not in ('paid','rejected') then
    raise exception 'Invalid payment result';
  end if;

  select payment_status, fulfillment_status, operational_status
    into v_old_status, v_old_fulfillment_status, v_old_operational_status
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_old_status in ('paid','refunded') then
    return false;
  end if;

  select status, proof_storage_path into v_payment_status, v_proof_path
  from public.payment_records
  where id = p_payment_id and order_id = p_order_id
  for update;

  if not found or v_payment_status <> 'pending_verification' then
    return false;
  end if;
  if p_result = 'paid' and (v_proof_path is null or length(v_proof_path) = 0) then
    return false;
  end if;

  update public.payment_records
  set status = p_result,
      verified_by = p_actor_user_id,
      verified_at = now(),
      admin_note = nullif(left(coalesce(p_note,''),500),''),
      updated_at = now()
  where id = p_payment_id;

  update public.orders
  set payment_status = p_result,
      fulfillment_status = case when p_result = 'rejected' then 'failed' else fulfillment_status end,
      operational_status = case when p_result = 'rejected' then 'cancelled' else operational_status end,
      updated_at = now()
  where id = p_order_id;

  insert into public.order_status_history
    (order_id, status_type, old_status, new_status, changed_by, note)
  values
    (p_order_id, 'payment', v_old_status, p_result, p_actor_user_id, nullif(left(coalesce(p_note,''),500),''));
  if p_result = 'rejected' then
    if v_old_fulfillment_status <> 'failed' then
      insert into public.order_status_history
        (order_id, status_type, old_status, new_status, changed_by, note)
      values (p_order_id, 'fulfillment', v_old_fulfillment_status, 'failed', p_actor_user_id,
        'Payment verification rejected; order closed and reservations released.');
    end if;
    if v_old_operational_status <> 'cancelled' then
      insert into public.order_status_history
        (order_id, status_type, old_status, new_status, changed_by, note)
      values (p_order_id, 'operational', v_old_operational_status, 'cancelled', p_actor_user_id,
        'Payment verification rejected; order closed and reservations released.');
    end if;
  end if;

  -- Close other pending attempts that have no proof. Proof-bearing attempts remain open
  -- for manual double-payment review and must never be auto-discarded.
  update public.payment_records
  set status = 'rejected',
      verified_by = p_actor_user_id,
      verified_at = now(),
      admin_note = 'Closed automatically: the order was resolved by another payment decision.',
      updated_at = now()
  where order_id = p_order_id
    and id <> p_payment_id
    and status = 'pending_verification'
    and proof_storage_path is null;
  get diagnostics v_closed_pending_attempts = row_count;

  if v_closed_pending_attempts > 0 then
    insert into public.order_status_history
      (order_id, status_type, old_status, new_status, changed_by, note)
    values (p_order_id, 'payment', 'pending_verification', 'rejected', p_actor_user_id,
      format('%s pending payment attempt(s) without proof were closed.', v_closed_pending_attempts));
  end if;

  insert into public.admin_audit_logs
    (actor_user_id, action, entity_type, entity_id, metadata)
  values
    (p_actor_user_id, 'verify_payment', 'order', p_order_id::text,
     jsonb_build_object('result',p_result,'payment_id',p_payment_id,
       'closed_pending_no_proof_attempts',v_closed_pending_attempts,
       'note',left(coalesce(p_note,''),500)));

  if p_result = 'paid' then
    update public.order_reservations
    set status = 'consumed', updated_at = now()
    where order_id = p_order_id and status in ('held_for_verification','active');
  else
    update public.order_reservations
    set status = 'released', released_at = now(), updated_at = now()
    where order_id = p_order_id and status in ('held_for_verification','active');
  end if;

  return true;
end;
$function$
;

REVOKE ALL ON FUNCTION public.admin_apply_payment_verification(uuid,uuid,uuid,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_apply_payment_verification(uuid,uuid,uuid,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.expire_stale_order_reservations(p_batch_size integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_order record;
  v_expired_orders integer := 0;
  v_expired_reservations integer := 0;
  v_closed_payment_attempts integer := 0;
  v_reservation_rows integer := 0;
  v_payment_rows integer := 0;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size < 1 OR p_batch_size > 1000 THEN
    RAISE EXCEPTION 'invalid_batch_size' USING ERRCODE = '22023';
  END IF;

  -- Expire only unpaid orders with no held reservations, no unexpired active
  -- reservations and no pending proof. Proof-bearing orders are held for manual review.
  FOR v_order IN
    SELECT o.id, o.fulfillment_status, o.operational_status
    FROM public.orders o
    WHERE o.payment_status = 'unpaid'
      AND o.fulfillment_status NOT IN ('failed','cancelled','fulfilled')
      AND EXISTS (
        SELECT 1 FROM public.order_reservations r
        WHERE r.order_id = o.id AND r.status = 'active' AND r.expires_at <= v_now
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.order_reservations r
        WHERE r.order_id = o.id AND r.status = 'held_for_verification'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.order_reservations r
        WHERE r.order_id = o.id AND r.status = 'active' AND r.expires_at > v_now
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.payment_records p
        WHERE p.order_id = o.id AND p.status = 'pending_verification'
          AND p.proof_storage_path IS NOT NULL
      )
    ORDER BY o.created_at
    LIMIT p_batch_size
    FOR UPDATE OF o SKIP LOCKED
  LOOP
    UPDATE public.order_reservations
    SET status = 'expired',
        released_at = COALESCE(released_at, v_now),
        updated_at = v_now
    WHERE order_id = v_order.id
      AND status = 'active'
      AND expires_at <= v_now;
    GET DIAGNOSTICS v_reservation_rows = ROW_COUNT;

    IF v_reservation_rows > 0 THEN
      UPDATE public.orders
      SET fulfillment_status = 'failed',
          operational_status = 'cancelled',
          updated_at = v_now
      WHERE id = v_order.id
        AND payment_status = 'unpaid'
        AND fulfillment_status NOT IN ('failed','cancelled','fulfilled');

      IF FOUND THEN
        v_expired_orders := v_expired_orders + 1;
        v_expired_reservations := v_expired_reservations + v_reservation_rows;

        INSERT INTO public.order_status_history
          (order_id,status_type,old_status,new_status,changed_by,note)
        VALUES
          (v_order.id,'reservation','active','expired',NULL,'Payment window elapsed; reservation capacity released.'),
          (v_order.id,'fulfillment',v_order.fulfillment_status,'failed',NULL,'Order automatically failed because payment was not received before reservation expiry.'),
          (v_order.id,'operational',v_order.operational_status,'cancelled',NULL,'Order automatically cancelled after unpaid reservation expiry.');

        UPDATE public.payment_records
        SET status = 'rejected',
            verified_at = v_now,
            admin_note = 'Closed automatically: order reservation expired before payment proof was submitted.',
            updated_at = v_now
        WHERE order_id = v_order.id
          AND status = 'pending_verification'
          AND proof_storage_path IS NULL;
        GET DIAGNOSTICS v_payment_rows = ROW_COUNT;
        v_closed_payment_attempts := v_closed_payment_attempts + v_payment_rows;

        IF v_payment_rows > 0 THEN
          INSERT INTO public.order_status_history
            (order_id,status_type,old_status,new_status,changed_by,note)
          VALUES (v_order.id,'payment','pending_verification','rejected',NULL,
            format('%s payment attempt(s) without proof closed after reservation expiry.',v_payment_rows));
        END IF;

        INSERT INTO public.admin_audit_logs
          (actor_user_id,action,entity_type,entity_id,metadata)
        VALUES
          (NULL,'system_expire_unpaid_order','order',v_order.id::text,
           jsonb_build_object('expired_reservations',v_reservation_rows,
             'reason','unpaid_reservation_expired','checked_at',v_now));
      END IF;
    END IF;
  END LOOP;

  -- A declared payment without uploaded proof also has a finite proof window.
  -- Keep proof-bearing attempts held for human review; fail only pending attempts
  -- whose reservation deadline passed and whose payment record has no proof.
  FOR v_order IN
    SELECT o.id, o.payment_status, o.fulfillment_status, o.operational_status
    FROM public.orders o
    WHERE o.payment_status = 'pending_verification'
      AND o.fulfillment_status NOT IN ('failed','cancelled','fulfilled')
      AND EXISTS (
        SELECT 1 FROM public.order_reservations r
        WHERE r.order_id = o.id AND r.status = 'held_for_verification' AND r.expires_at <= v_now
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.order_reservations r
        WHERE r.order_id = o.id AND r.status = 'held_for_verification' AND r.expires_at > v_now
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.order_reservations r
        WHERE r.order_id = o.id AND r.status = 'active' AND r.expires_at > v_now
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.payment_records p
        WHERE p.order_id = o.id AND p.status = 'pending_verification'
          AND p.proof_storage_path IS NOT NULL
      )
    ORDER BY o.created_at
    LIMIT p_batch_size
    FOR UPDATE OF o SKIP LOCKED
  LOOP
    UPDATE public.order_reservations
    SET status = 'expired',
        released_at = COALESCE(released_at, v_now),
        updated_at = v_now
    WHERE order_id = v_order.id
      AND status = 'held_for_verification'
      AND expires_at <= v_now;
    GET DIAGNOSTICS v_reservation_rows = ROW_COUNT;

    IF v_reservation_rows > 0 THEN
      UPDATE public.orders
      SET payment_status = 'rejected',
          fulfillment_status = 'failed',
          operational_status = 'cancelled',
          updated_at = v_now
      WHERE id = v_order.id
        AND payment_status = 'pending_verification'
        AND fulfillment_status NOT IN ('failed','cancelled','fulfilled');

      IF FOUND THEN
        v_expired_orders := v_expired_orders + 1;
        v_expired_reservations := v_expired_reservations + v_reservation_rows;

        UPDATE public.payment_records
        SET status = 'rejected',
            verified_at = v_now,
            admin_note = 'Closed automatically: payment was declared but proof was not uploaded before reservation expiry.',
            updated_at = v_now
        WHERE order_id = v_order.id
          AND status = 'pending_verification'
          AND proof_storage_path IS NULL;
        GET DIAGNOSTICS v_payment_rows = ROW_COUNT;
        v_closed_payment_attempts := v_closed_payment_attempts + v_payment_rows;

        INSERT INTO public.order_status_history
          (order_id,status_type,old_status,new_status,changed_by,note)
        VALUES
          (v_order.id,'reservation','held_for_verification','expired',NULL,'Payment proof deadline elapsed; reservation capacity released.'),
          (v_order.id,'payment','pending_verification','rejected',NULL,'Payment was declared but no proof was uploaded before reservation expiry.'),
          (v_order.id,'fulfillment',v_order.fulfillment_status,'failed',NULL,'Order automatically failed because payment proof was not uploaded before reservation expiry.'),
          (v_order.id,'operational',v_order.operational_status,'cancelled',NULL,'Order automatically cancelled after proof deadline elapsed.');

        INSERT INTO public.admin_audit_logs
          (actor_user_id,action,entity_type,entity_id,metadata)
        VALUES
          (NULL,'system_expire_unproven_payment_order','order',v_order.id::text,
           jsonb_build_object('expired_reservations',v_reservation_rows,
             'closed_payment_attempts',v_payment_rows,
             'reason','payment_declared_without_proof_before_expiry','checked_at',v_now));
      END IF;
    END IF;
  END LOOP;

  -- A paid order must not retain a pending no-proof payment attempt. Proof-bearing
  -- attempts are intentionally left open for manual double-payment/refund review.
  FOR v_order IN
    SELECT o.id
    FROM public.orders o
    WHERE o.payment_status = 'paid'
      AND EXISTS (
        SELECT 1 FROM public.payment_records p
        WHERE p.order_id = o.id AND p.status = 'pending_verification'
          AND p.proof_storage_path IS NULL
      )
    ORDER BY o.created_at
    LIMIT p_batch_size
    FOR UPDATE OF o SKIP LOCKED
  LOOP
    UPDATE public.payment_records
    SET status = 'rejected',
        verified_at = v_now,
        admin_note = 'Closed automatically: order is already paid; no proof was attached to this pending attempt.',
        updated_at = v_now
    WHERE order_id = v_order.id
      AND status = 'pending_verification'
      AND proof_storage_path IS NULL;
    GET DIAGNOSTICS v_payment_rows = ROW_COUNT;

    IF v_payment_rows > 0 THEN
      v_closed_payment_attempts := v_closed_payment_attempts + v_payment_rows;
      INSERT INTO public.order_status_history
        (order_id,status_type,old_status,new_status,changed_by,note)
      VALUES (v_order.id,'payment','pending_verification','rejected',NULL,
        format('%s stale no-proof payment attempt(s) closed because order is paid.',v_payment_rows));
      INSERT INTO public.admin_audit_logs
        (actor_user_id,action,entity_type,entity_id,metadata)
      VALUES (NULL,'system_close_stale_payment_attempts','order',v_order.id::text,
        jsonb_build_object('closed_attempts',v_payment_rows,'reason','order_already_paid','checked_at',v_now));
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'expired_orders',v_expired_orders,
    'expired_reservations',v_expired_reservations,
    'closed_payment_attempts',v_closed_payment_attempts,
    'checked_at',v_now
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.expire_stale_order_reservations(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_stale_order_reservations(integer) TO service_role;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
DO $schedule$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dlice-expire-stale-online-orders') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'dlice-expire-stale-online-orders';
  END IF;
  PERFORM cron.schedule(
    'dlice-expire-stale-online-orders',
    '* * * * *',
    'SELECT public.expire_stale_order_reservations(200);'
  );
END
$schedule$;
