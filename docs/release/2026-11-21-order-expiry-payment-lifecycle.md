# Order expiry and payment lifecycle compensation — 2026-11-21

## Live staging evidence (read-only)

The staging project currently contains seven legacy online orders, all created on 2026-10-17:
- 3 orders are paid, 3 unpaid, 1 pending_verification.
- All seven remain operational_status=received and fulfillment_status=unassigned.
- 9 reservation rows are still status=active although their expires_at timestamps are in the past; they belong to unpaid orders.
- 3 reservations are held_for_verification with past expires_at timestamps; these remain held because payment is pending verification.
- 6 payment records exist: 3 paid with proof, 1 pending_verification with proof on the pending order, and 2 pending_verification records without proof attached to already-paid orders.
- Existing pg_cron only schedules dlice-operational-retention at 03:17 daily; there is no online-order reservation expiry job.

No order, payment, reservation, or payment-proof record was modified during this audit.

## Changes proposed

- Add a one-minute pg_cron worker that expires unpaid orders only when every active reservation has passed expiry, no reservation is held for verification, and no pending proof exists.
- Mark expired reservations as expired, the order fulfillment state as failed, and operational state as cancelled. Record reservation, fulfillment, operational and audit events.
- Close pending payment attempts without proof for expired orders and already-paid orders. Proof-bearing duplicate attempts are deliberately left open for manual double-payment/refund review.
- Update atomic admin payment verification so a rejected payment closes the order (fulfillment failed, operational cancelled), releases reservations, and closes other no-proof pending attempts.
- Add fulfillment to the order status-history event types.
- Add two partial indexes for the expiry worker's access paths.

## Remaining limitations

- This does not auto-approve or reject proof-bearing late payments. Those require human review.
- The current Edge Function's customer proof-upload flow still performs several database writes separately; an atomic customer payment-proof RPC and browser race/fault-injection test remain required.
- Existing seven orders and their stale records are not reconciled by this PR. The scheduled worker only acts after an authorized migration rollout; final reconciliation must separately review proof-bearing records and confirm no double payment.
- No shared staging migration or production change is made by this PR.
