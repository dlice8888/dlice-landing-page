# Staging retention and RPC privilege audit

Date: 2026-10-21

## Scope and guardrails

This migration is for staging first. It does not delete customer orders, payment records, uploaded payment proofs, notification records, or admin audit logs. It uses the built-in PostgreSQL `pg_cron` extension available in the current Supabase staging project; no paid provider or new Supabase project is added. The daily job uses database resources and must be monitored against the existing free-tier quota.

## Retention policy

- `request_rate_limits`: delete rows whose `updated_at` is older than 30 days. These are ephemeral throttling counters, not audit history.
- `funnel_daily_metrics`: delete daily aggregate rows older than 730 days. Metrics contain whitelisted event counts, not customer identifiers.
- Orders, order items, payments, payment proofs, notification logs, and admin audit logs: preserved indefinitely by this cleanup function. Do not add automatic deletion without a separate retention/legal review.

The scheduled job is named `dlice-operational-retention` and runs daily at 03:17 UTC. The function returns counts of deleted rows so execution can be inspected from PostgreSQL logs. It runs as the role that owns the cron job; the function itself is `SECURITY INVOKER`, uses a fixed search path, and has explicit execution revoked from `PUBLIC`, `anon`, and `authenticated`. Only `service_role` is granted direct execution.

## RPC audit findings

The staging audit found the order/payment/rate-limit business RPCs already restricted to `postgres` and `service_role`. The `set_updated_at()` trigger helper was executable by `PUBLIC`, `anon`, and `authenticated`; this migration revokes direct execution. PostgreSQL checks trigger-function permission when a trigger is created, so existing triggers continue to operate.

## Verification required after staging migration

1. Confirm the migration is recorded and the cron job appears once in `cron.job`.
2. Call `cleanup_operational_data()` as `service_role` in a controlled test and confirm its JSON counts; do not manufacture old customer data to test it.
3. Confirm `anon` and `authenticated` cannot execute the cleanup RPC.
4. Confirm the scheduled job's recent run appears in database logs.
5. Re-run Security and Performance Advisors and review the changed findings.
6. Do not apply this migration to production until staging acceptance is complete and the Owner explicitly approves release.
