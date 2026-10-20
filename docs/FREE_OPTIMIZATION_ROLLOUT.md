# Free optimization rollout (staging only)

## Guardrails and cost
- No paid integration, external analytics SDK, new Supabase project/branch, cron, or paid Vercel feature is introduced.
- All code and database changes are scoped to `feat/free-hardening-optimizations` and Supabase staging project `higoadrzxnhzbbwhdbmh`.
- Production project `gdjlkrmlsurcdbwnmqgg` and production domain `https://dlice.vercel.app/` must not be modified until staging acceptance passes and Owner explicitly approves.
- GitHub Actions uses a dependency-free static test job on GitHub-hosted runners. Check account quotas if the repository becomes private; no third-party CI service is required.
- Supabase Auth leaked-password protection cannot be toggled by the connected Supabase tools. Owner must enable it manually in staging first, then separately in production only during an approved release.

## Implemented in this branch
1. Operational login uses Edge Function `admin-login`, not direct browser password sign-in. It validates username, applies account/IP rate limits, returns generic credential errors, and checks that the admin profile is active.
2. Database-backed `consume_rate_limit` provides atomic limits for login, transaction-code tracking, token tracking, and order creation. Bucket keys are SHA-256 digests; raw IP/usernames are not stored. Old rate-limit buckets are cleaned opportunistically without a scheduled job.
3. The Edge Function no longer defaults to a production Supabase URL if configuration is missing; it fails closed when required URL/service/public key configuration is absent.
4. Payment verification and operational status changes use atomic database RPCs for state, history, audit log, and reservation changes.
5. Daily funnel analytics stores only whitelisted event counts by date, without cookies, user IDs, phone numbers, order IDs, or IPs. Authorized operational users can view a 30-day aggregate.
6. Security headers are configured in `vercel.json`: MIME sniffing protection, referrer policy, frame denial, permissions policy, and HSTS.
7. GitHub Actions static checks run on every branch and PR; the workflow checks HTML inline JavaScript syntax, Edge Function security markers, migrations, Vercel JSON, and requires documentation changes when a PR changes migrations.
8. Landing-page hero image uses high fetch priority/async decoding; menu images use lazy loading/async decoding. A direct Google Maps reviews link was added without inventing review content or paying for Places API.
9. The catalog uses the Supabase `products` table as source of truth; the order backend calculates authoritative prices.
10. Tracking uses transaction code + full ordering WhatsApp number or private tracking token, with request rate limits.
11. Added `docs/STAGING_RELEASE_CHECKLIST.md` and `docs/STAGING_DATABASE_AUDIT_2026-10-20.md` to document acceptance gates, environment policy, RLS/grants, query plans, and index decisions.

## Verified status on 2026-10-20
- GitHub Actions `Free quality checks` passed for commit `fae6a4dfacaa54fd1a70a6a85a445835ce15b97f`.
- Vercel created a READY preview for that exact commit: `https://dlice-landing-page-10ljbr75e-dlice8888-7332.vercel.app/`. READY means build/deployment completed, not that browser E2E passed.
- Vercel project reports SSO protection enabled for deployments except custom domains. The preview still needs an actual Owner browser access check.
- Staging Supabase read-only audit found service-role-only table grants for the inspected sensitive tables, and only one public read policy on active products.
- Supabase security advisor still reports leaked-password protection disabled; this is not marked complete.
- Staging query plans were captured. No indexes were added or removed because the database is very small and current query timings do not justify index changes. See the dated database audit.
- Vercel environment variables `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` were observed with targets across production, preview, and development. These target scopes have **not** been changed because changing them without inspecting/confirming each environment's intended value risks altering production behavior. Strict variable separation remains a release blocker; review and split scopes in the Vercel dashboard after the staging acceptance plan is approved, without exposing decrypted values.

## Manual dashboard steps required
### Enable leaked-password protection (staging first)
1. Open Supabase Dashboard for project `higoadrzxnhzbbwhdbmh`.
2. Go to Authentication settings / Security or Password Security (menu labels may vary).
3. Enable leaked-password protection and save.
4. Validate using test accounts only.
5. Repeat in production only during an approved release.

### Environment separation and repository controls
- In Vercel, review variable names and target scopes without decrypting values. Split staging Preview/Development from Production only after confirming each intended project URL and publishable key. Do not remove/replace a variable until all consumers are checked.
- GitHub branch protection / required checks are account-level repository settings and were not changed by the repository tools. Require `Free quality checks` for merges to protected branches.
- Vercel reports SSO protection enabled for preview deployments except custom domains; confirm that the Owner can access the exact preview without broadly disabling protection.

Do not change production settings while staging is being tested.

## RLS/grants audit result
Read-only staging audit showed RLS enabled on the inspected public tables. Sensitive tables such as `orders`, `order_items`, `payment_records`, `payment_settings`, `notification_log`, `admin_profiles`, `admin_audit_logs`, `funnel_daily_metrics`, and `request_rate_limits` had no direct `anon` or `authenticated` table grants in the inspected grant list; `service_role` grants were present. The only policy returned by `pg_policies` was public SELECT of active `products`. Advisor reports 12 RLS-enabled tables with no policies; given service-role-only grants, do not add broad policies just to silence this informational warning. Recheck grants and policies after schema changes.

## Index and performance audit
Six indexes were reported unused at audit time, each roughly 8–16 kB. Core indexes were used, including order number, tracking token, order item/order ID, payment/order ID, reservation capacity/order ID, and notification/order ID. Four representative staging plans ran quickly (about 0.17–2.00 ms), but the dataset contains only seven orders and six payment records. No index was added or removed; low-volume staging statistics are not enough to justify production index changes. Capture plans and query statistics after representative traffic.

## End-to-end staging test checklist
- [ ] Enable/test leaked-password protection in staging.
- [ ] Test Owner login, generic invalid-password response, and HTTP 429 after repeated failures.
- [ ] Confirm staff permission boundaries, logout, and expired session behavior.
- [ ] Test valid/invalid tracking by transaction code + WhatsApp and by private token; invalid lookups reveal no order data and repeated requests hit HTTP 429.
- [ ] Create a multi-menu order and verify server totals, `DLC-dd/mm/yyyy-xxxxx` code, WITA schedule, receiving method, and delivery address.
- [ ] Test capacity conflicts and concurrent checkout; capacity must not be oversold.
- [ ] Test receipt confirmation, bank/QRIS instructions, proof upload/re-upload, payment verification, notification idempotency, and fulfillment gates.
- [ ] Test every operational transition, cancellation/delivery issue reason, and customer tracking.
- [ ] Confirm funnel aggregates update and contain no customer identifiers.
- [ ] Confirm anon/authenticated REST cannot read metrics/rate-limit tables.
- [ ] Verify security headers and preview protection on the exact preview.
- [ ] Inspect landing and checkout on mobile and desktop.
- [ ] Review Supabase security/performance advisors and attach test evidence to PR.
- [ ] Owner explicitly approves promotion only after all mandatory checks pass.

## No-cost limitations
- No Google Places API integration or auto-scrolling five-star carousel was added because no verified review feed was supplied and official API use may require billing. The site links to Google Maps instead; never fabricate reviews.
- No paid monitoring provider or external analytics SDK was added. Use native Supabase/Vercel logs and the privacy-safe aggregate dashboard; these still consume included free-tier quotas.
- Static CI is not a browser E2E test. Do not mark the deployment production-ready until all manual acceptance checks pass.
