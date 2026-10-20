# Staging database security and query-plan audit — 2026-10-20

Scope: Supabase staging project `higoadrzxnhzbbwhdbmh` only. This is a read-only audit; no production data or schema was changed.

## Grants and RLS

- Sensitive order/payment/admin/audit/notification/metrics/rate-limit tables inspected have table privileges granted to `service_role` only; no direct `anon` or `authenticated` table grants were returned for the inspected set.
- The only public-schema policy returned by `pg_policies` was `Public can read active Dlice products` on `products`, for `anon, authenticated`, with predicate `is_active = true`.
- Supabase Security Advisor currently reports 12 public tables with RLS enabled but no policies. Given the verified service-role-only table grants, these are intentionally inaccessible through direct anon/authenticated Data API access; do not create permissive policies to silence the informational warning.
- Supabase Security Advisor still reports `auth_leaked_password_protection` as a warning. The connected Supabase tools do not expose the Auth security toggle, so it remains a required manual staging-dashboard action before acceptance.

## Index scan observations

The staging database is currently very small. Six indexes were reported as unused at the time of audit, each about 8–16 kB. In contrast, indexes used by real queries included:
- `orders_order_number_key`: 5 scans
- `orders_tracking_token_hash_key`: 13 scans
- `order_items_order_id_idx`: 76 scans
- `payment_records_order_id_idx`: 79 scans
- `order_reservations_order_id_idx` and `order_reservations_capacity_idx`: 21 scans each
- `notification_log_order_id_idx`: 25 scans

Do not remove indexes solely from zero scans on a small staging dataset. Statistics can reset and real production volume/query mix differs.

## Query plans captured on staging

Read-only `EXPLAIN (ANALYZE, BUFFERS)` tests were run for representative access patterns:
- Latest 20 orders: sequential scan of 7 existing rows plus in-memory sort; ~0.17 ms execution.
- Order-number lookup with a deliberately nonexistent value: `orders_order_number_key` index scan; ~1.39 ms execution.
- Latest order's line items: `order_items_order_id_idx` bitmap index scan; ~2.00 ms execution.
- Pending-verification payment queue: sequential scan of 6 rows plus sort; ~0.85 ms execution.

These timings are only staging smoke-test measurements, not a production performance guarantee. The current payment queue is too small to justify a new index. Re-measure after representative traffic exists; consider a composite `(status, created_at DESC)` index only if real queue queries and volume demonstrate a benefit.

## Decision

No index was removed or added. No permissive RLS policies were added. Keep service-role-mediated access, keep query plans and advisor findings under review, and rerun this audit after meaningful test volume or any schema/query change.
