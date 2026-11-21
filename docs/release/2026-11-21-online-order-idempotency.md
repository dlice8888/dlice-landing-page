# Online order idempotency — 2026-11-21

## Gap addressed

The public `create-order` handler called `create_order_with_reservations` without a stable idempotency key. If the database committed but the HTTP response was lost, a browser retry could create a second order and a second capacity reservation. The existing POS/offline idempotency path did not protect public online checkout.

## Implementation

- Browser creates a cryptographically random 256-bit checkout key and persists it in `sessionStorage` until a successful response.
- The same opaque key is used as the tracking bearer token; only its SHA-256 hash is persisted in the database. This lets a retry recover the same tracking token without storing the raw token.
- Edge Function validates the key, normalizes the order, computes a canonical SHA-256 request fingerprint, and passes both hashes into the atomic RPC.
- The RPC takes a transaction-scoped advisory lock on the key hash before capacity locks, checks an internal idempotency ledger, returns the original response on an identical retry, and rejects changed payloads with `idempotency_key_payload_mismatch`.
- Order, reservations, and idempotency ledger row are committed in one transaction. A failure before commit leaves no idempotency record and is safe to retry.
- The internal ledger has RLS enabled and no grants to `anon` or `authenticated`; service-role access only.

## Validation

- pgTAP covers first creation, identical retry, same order ID, changed-payload rejection, one ledger row, and one reservation.
- Node contract tests verify browser persistence, Edge Function fingerprint wiring, advisory locking, and database ACL.
- Disposable migration replay and exact-head CI must pass before merge.
- Public checkout remains blocked by `PUBLIC_TENANT_ROUTING_RELEASED=false`; this PR does not enable it.
- No shared staging migration or Edge Function deployment is performed here.

## Remaining acceptance

- Browser/network fault-injection test: commit succeeds, response is dropped, same tab retries, and exactly one order is visible.
- Concurrent duplicate-request test with same key and different request arrival times.
- Verify tracking token remains recoverable only by the initiating checkout session.
- Reconcile capacity reservation count and order count after replay.

## Follow-up lifecycle remediation

PR #125 separately adds unpaid/unproven-payment reservation expiry, rejected-payment compensation, stale no-proof payment-attempt cleanup and a one-minute pg_cron worker. PR #123 remains scoped to idempotent order creation/replay. The atomic customer proof-upload/declaration RPC and browser race/fault-injection test remain open, so the overall order lifecycle is not DONE.
