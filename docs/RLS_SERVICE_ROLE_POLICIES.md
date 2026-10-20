# Internal table RLS hardening

## Scope

Migration `20261020160000_lock_down_internal_table_rls.sql` applies to the D’lice staging database first. It covers these internal tables:

- `admin_audit_logs`, `admin_profiles`
- `funnel_daily_metrics`, `notification_log`
- `order_items`, `order_reservations`, `order_status_history`, `orders`
- `payment_records`, `payment_settings`, `product_capacity`, `request_rate_limits`

## Access model

These tables are accessed through trusted server-side Edge Function operations using the Supabase `service_role`. They must not be directly readable or writable by browser clients. The migration explicitly revokes table privileges from `PUBLIC`, `anon`, and `authenticated`, keeps RLS enabled, and adds explicit `service_role`-only policies. It does not add any client-role policy and does not expose order, payment proof, admin profile, audit, rate-limit, notification, or funnel data.

The service-role key must never be sent to the browser. The policies are defense-in-depth and make the intended access model visible to database review tools; they do not replace Edge Function authorization checks.

## Staging verification checklist

After merging this migration to `feat/staging-order-receipt-gates`, apply it to the Supabase staging project only and verify:

1. All 12 tables still have RLS enabled.
2. Each table has exactly the intended `service_role_only` policy for the `service_role` role.
3. `anon` and `authenticated` have no SELECT/INSERT/UPDATE/DELETE privileges on these tables.
4. `service_role` retains the privileges required by the Edge Function.
5. Run Supabase Security Advisor again. The `rls_enabled_no_policy` findings for these tables should clear after its cache refresh.
6. Smoke-test public catalog reads, checkout, proof upload/re-upload, tracking, payment verification, operational status changes, admin audit writes, and rate limiting.
7. Do not promote the migration to production until staging smoke tests and the complete order-flow E2E checklist pass and the Owner approves.

## Why not create customer-facing policies?

Orders and payment records contain sensitive personal and transactional data. Adding broad `anon` or `authenticated` policies to suppress an INFO finding would risk exposing those records. The correct access boundary is the trusted Edge Function, not direct browser access to these tables.
