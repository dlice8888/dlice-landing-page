# Atomic customer payment-proof upload — 21 November 2026

## Failure being corrected
The previous public `upload-proof` handler uploaded an object and then issued independent writes to `payment_records`, `order_reservations`, `orders`, and `order_status_history`. A mid-sequence failure could leave the order, payment, reservation and audit states inconsistent. Expiry could also race a proof upload.

## Transaction design
1. Edge Function validates file MIME/size, tracking token, confirmed receipt, payment method and upload UUID.
2. Edge Function uploads the proof to the private `dlice-payment-proofs` bucket under the order UUID prefix.
3. Edge Function calls `submit_customer_payment_proof_atomic`.
4. The RPC locks the order row and then reservation rows, matching the expiry worker lock order.
5. The RPC revalidates payment state, receipt version/method/instruction/amount, reservation deadlines and object path.
6. In one Postgres transaction it inserts/updates the pending payment, moves reservations to `held_for_verification`, sets order payment state to `pending_verification`, and writes status history + audit log.
7. A unique `proof_upload_key` makes retries idempotent. A replay returns the original payment ID; a distinct upload cannot replace evidence already under review.

## Storage boundary and orphan handling
Supabase Storage and Postgres do not share a transaction. The Edge Function compensates by deleting the just-uploaded object when the RPC rejects/errors. If a retry with the same key finds a committed proof, the newly uploaded duplicate object is removed.

The handler also performs best-effort, per-order cleanup after a successful upload: it lists up to 100 objects in that order's folder, considers only files older than one hour, checks each candidate against `payment_records.proof_storage_path`, and removes only unreferenced files through the Storage API. It does not delete through SQL. This opportunistic sweep is not a global scheduled sweeper; an orphan for an order with no subsequent upload can remain until an explicit cleanup operation is added.

## Security
- RPC uses `SECURITY INVOKER`, an empty search_path, and is executable only by `service_role`.
- No service key is sent to the browser.
- Proof files remain private; the RPC stores only the private object path.
- Late or expired reservations are rejected inside the transaction.
- Existing proof under review is never overwritten by a different request key.

## Validation
- 15 pgTAP assertions cover valid submission, payment/order/reservation state, history/audit writes, idempotent replay, duplicate proof rejection, amount/method mismatch, expired reservation and RPC ACL.
- Source-contract tests cover the single-RPC handler, compensation, frontend retry key and orphan cleanup.
- Full disposable migration replay and workflow contracts must pass on the exact final PR head.
- Browser fault injection, parallel proof-vs-expiry concurrency, real storage lifecycle tests and staging runtime acceptance remain required before DONE.

## Rollout boundary
Draft PR only. No shared staging migration, Edge Function deployment, cron activation, legacy order reconciliation or production change. Those occur only in the final authorized release/reconciliation stage.
