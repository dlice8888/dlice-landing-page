# POS & Checkout — Promotions, Coupons and Vouchers (2026-11-27)

## Feature ID started
- D02-F05 — Discounts, coupons, vouchers and special pricing.

## Implemented
`src/pos-promotion-voucher-workflows.mjs` adds:
- approved, effective-dated promotion validation by tenant, branch, customer segment and minimum spend;
- percentage/fixed discount calculation with maximum cap and subtotal protection;
- transactional promotion application from server-loaded sale and usage records, with idempotency and audit;
- voucher redemption against a locked voucher balance and unpaid sale, with customer/expiry validation and atomic consumption/balance update.

Contract tests cover fixed/percentage discounts, max cap, eligibility, period, redemption limit, voucher expiry/customer scope and atomic balance persistence.

## Remaining acceptance
- Canonical promotion/coupon/voucher schema, versioning, RLS, usage counters and append-only consumption/reversal ledgers.
- Concrete Supabase adapters and authenticated Edge Function actions; no client-supplied subtotal/discount authority.
- Coupon code issuance/validation, stacking/exclusion policy, channel/branch/product scope and manager approval.
- Refund/void reversal, partial refund and settlement/Finance journal reconciliation.
- POS UI for promotion selection, voucher balance and cashier approval.
- Staging concurrency/idempotency E2E and tenant/branch isolation tests.
