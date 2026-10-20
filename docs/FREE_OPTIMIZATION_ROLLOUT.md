# Free optimization rollout (staging only)

## Guardrails and cost
- No paid integration, external analytics SDK, new Supabase project/branch, cron, or paid Vercel feature is introduced.
- Code and database changes remain scoped to `feat/free-hardening-optimizations` and Supabase staging project `higoadrzxnhzbbwhdbmh`.
- Production domain remains `https://dlice.vercel.app/`; production database/Edge Function changes are blocked until staging acceptance passes and Owner explicitly approves.
- GitHub Actions uses dependency-free checks. Included quotas still apply; no third-party CI service is required.
- Supabase Auth leaked-password protection cannot be toggled by the connected Supabase tools. Owner must enable it manually in staging first.

## Implemented in this branch
1. Operational login calls Edge Function `admin-login`; account/IP limits, generic credential errors, and active-profile checks are server-side.
2. Database-backed `consume_rate_limit` provides atomic limits for login, order-code tracking, private-token tracking, and order creation. Bucket keys are SHA-256 digests; raw IP/usernames are not stored.
3. Edge Function fails closed if required URL/service/public key configuration is absent; no production URL fallback.
4. Payment verification and operational status changes use atomic database RPCs for state, history, audit log, and reservation updates.
5. Daily funnel analytics stores only whitelisted event counts by date; no customer IDs, phone numbers, order IDs, IPs, or cookies.
6. `vercel.json` configures MIME sniffing, referrer, frame, permissions, and HSTS headers.
7. GitHub Actions runs static checks on branch pushes and PRs; migration-changing PRs must update documentation.
8. Hero/menu image loading was optimized; Google Maps reviews link added without fake content or paid Places API.
9. Supabase `products` is the catalog source of truth; backend calculates authoritative prices.
10. Tracking paths have rate limiting.
11. Added staging release checklist and dated RLS/grants/query-plan audit.
12. Vercel environment scopes were separated in the project configuration: `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are now Production-only for production Supabase, and separate Preview/Development values point to staging Supabase.

## Verified status on 2026-10-20
- GitHub Actions `Free quality checks` passed on commit `5e00d51b71aa9f406eb21b1f6cab415b31c7541b` before the subsequent environment configuration change.
- Vercel preview for that commit is READY at `https://dlice-landing-page-6ol4m67v5-dlice8888-7332.vercel.app/`. READY means deployment completed, not that browser E2E passed. Environment changes require a fresh deployment before testing those values in runtime.
- Vercel reports SSO protection enabled for preview deployments except custom domains; Owner access to a fresh preview still needs verification.
- Staging Supabase read-only audit found service-role-only grants for inspected sensitive tables and one public SELECT policy on active products.
- Supabase Security Advisor still reports leaked-password protection disabled.
- Query plans were captured; no indexes were added/removed because staging data is too small to justify changes.
- GitHub branch protection / required checks are still not confirmed as enforced at repository settings level.

## Manual dashboard steps
### Enable leaked-password protection (staging first)
1. Open Supabase Dashboard for `higoadrzxnhzbbwhdbmh`.
2. Go to Authentication → Security / Password Security (labels may vary).
3. Enable leaked-password protection and save.
4. Validate using test accounts only. Repeat in production only during an approved release.

### Required CI / repository controls
- Require `Free quality checks` for merges to protected branches in GitHub repository settings; the connected tools did not expose branch-protection settings.
- Confirm the Owner can access the SSO-protected Preview URL. Do not broadly disable preview protection.

Do not promote production while the staging acceptance checklist has unchecked items.

## RLS/grants audit
Read-only staging audit showed RLS enabled on inspected public tables. Sensitive tables including `orders`, `order_items`, `payment_records`, `payment_settings`, `notification_log`, `admin_profiles`, `admin_audit_logs`, `funnel_daily_metrics`, and `request_rate_limits` had no direct `anon`/`authenticated` table grants in the inspected grant list; `service_role` grants were present. The only policy returned by `pg_policies` was public SELECT of active `products`. Advisor reports 12 RLS-enabled tables without policies; given service-role-only grants, do not add broad policies just to silence the warning. Recheck grants and policies after schema changes.

## Index and query-plan audit
Six indexes were reported unused at audit time, each roughly 8–16 kB. Core indexes for order number, tracking token, order item/order ID, payment/order ID, reservation capacity/order ID, and notification/order ID were used. Four staging plans ran around 0.17–2.00 ms on a tiny dataset (seven orders, six payment records). No index was added or removed; low-volume staging statistics are not enough to justify production changes.

## Staging E2E acceptance checklist
- [ ] Enable/test leaked-password protection.
- [ ] Test Owner login, generic invalid-password response, and HTTP 429 after repeated failures.
- [ ] Confirm staff permission boundaries, logout, and expired session behavior.
- [ ] Test valid/invalid tracking by order code + WhatsApp and private token; invalid lookups reveal no order data; repeated requests hit HTTP 429.
- [ ] Create multi-menu order; verify authoritative totals, `DLC-dd/mm/yyyy-xxxxx`, WITA schedule, receiving method, delivery address.
- [ ] Test capacity conflicts and concurrent checkout; no overselling.
- [ ] Test bank/QRIS instructions, proof upload/re-upload, payment verification, notification idempotency, and fulfillment gates.
- [ ] Test every operational transition, required cancellation/delivery-issue reason, and customer tracking.
- [ ] Confirm funnel aggregates update and contain no customer identifiers.
- [ ] Confirm anon/authenticated REST cannot read metrics/rate-limit tables.
- [ ] Verify headers, SSO preview access, and environment routing on a fresh deployment.
- [ ] Inspect landing/checkout on mobile and desktop.
- [ ] Review Supabase security/performance advisors and attach evidence to PR.
- [ ] Owner approves promotion only after all mandatory checks pass.

## No-cost limitations
- No Google Places API or auto-scrolling five-star carousel: no verified feed was supplied and official API use may require billing. Link to Google Maps instead; never fabricate reviews.
- No paid monitoring provider or external analytics SDK. Use native Supabase/Vercel logs and privacy-safe aggregate dashboard; included free-tier quotas still apply.
- Static CI is not browser E2E. Do not mark production-ready until the acceptance checklist passes.
