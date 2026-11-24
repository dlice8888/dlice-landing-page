BEGIN;

-- Cover every POS foreign key introduced by the checkout lifecycle migration.
CREATE INDEX pos_checkout_idempotency_actor_user_idx
  ON public.pos_checkout_idempotency_requests (actor_user_id);
CREATE INDEX pos_held_orders_actor_user_idx
  ON public.pos_held_orders (actor_user_id);
CREATE INDEX pos_held_orders_shift_branch_idx
  ON public.pos_held_orders (shift_id, branch_id);
CREATE INDEX pos_sale_receipts_created_by_idx
  ON public.pos_sale_receipts (created_by);
CREATE INDEX pos_sale_receipts_sale_branch_idx
  ON public.pos_sale_receipts (sale_id, branch_id);
CREATE INDEX pos_sale_tenders_created_by_idx
  ON public.pos_sale_tenders (created_by);
CREATE INDEX pos_sale_tenders_sale_branch_idx
  ON public.pos_sale_tenders (sale_id, branch_id);

COMMIT;
