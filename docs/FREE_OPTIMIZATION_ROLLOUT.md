# Free optimization rollout (staging only)

## Guardrails and cost
- No paid integration, external analytics SDK, new Supabase project/branch, cron, or paid Vercel feature is introduced.
- All code and database changes are scoped to `feat/free-hardening-optimizations` and Supabase staging project `higoadrzxnhzbbwhdbmh`.
- Production project `gdjlkrmlsurcdbwnmqgg` and production domain `https://dlice.vercel.app/` must not be modified until staging acceptance passes and Owner explicitly approves.
- GitHub Actions uses a dependency-free static test job on GitHub-hosted runners. Check account quotas if the repository becomes private; no third-party CI service is required.
- The app's Supabase Auth leaked-password protection setting cannot be changed through the connected Supabase tools available in this workflow. Owner must enable it manually in staging dashboard first and repeat in production only during an approved release.

## Implemented in this branch
1. Operational login now calls the Edge Function `admin-login`, rather than calling password sign-in directly from the browser. The endpoint validates username, applies account/IP rate limits, returns generic credential errors, and checks that the admin profile is active.
2. A database-backed `consume_rate_limit` function and `request_rate_limits` table provide atomic, free rate limiting for admin login, ID tracking, token tracking, and order creation. The table has RLS enabled and grants only to `service_role`; raw IP/usernames are not stored (bucket keys are SHA-256 digests).
3. Supabase URL no longer defaults to the production project if the environment variable is missing. The Edge Function fails closed when `SUPABASE_URL`, service key, or public key is absent.
4. Payment verification and operational status changes now use database transactions that atomically update status, history, audit log, and reservation state, preventing partial updates when one of those writes fails.
5. Added privacy-preserving daily funnel aggregates. Only a fixed event name and server date are stored; no cookies, user IDs, phone numbers, order IDs, or IPs are stored. Owner/staff with `orders` permission can load a 30-day aggregate from the operational dashboard.
6. Added security headers in `vercel.json`: MIME sniffing protection, referrer policy, frame denial, permissions policy, and HSTS.
7. Added free GitHub Actions static quality checks for HTML inline JavaScript syntax, Edge Function security markers, migration guardrails, and Vercel JSON.
8. Landing page hero image has high fetch priority/async decoding; menu images use lazy loading/async decoding. A direct Google Maps reviews link is provided without inventing review content or paying for Places API.
9. Existing catalog already reads from the Supabase `products` table and the order backend computes authoritative prices; keep that single-source-of-truth design.
10. Existing tracking uses transaction ID + full ordering WhatsApp number or a private tracking token; this branch adds request rate limits to both lookup paths.

## Manual dashboard steps required
### Enable leaked-password protection (staging first)
1. Open Supabase Dashboard for project `higoadrzxnhzbbwhdbmh`.
2. Go to Authentication settings / Security (exact menu label may vary).
3. Enable leaked-password protection and save.
4. Test a normal Owner/staff login and the password policy using a test account; do not test with real customer credentials.
5. After production is approved, repeat separately for production project `gdjlkrmlsurcdbwnmqgg`.

Do not change production settings while staging is being tested.

## RLS/grants audit result
Read-only audit of staging showed RLS enabled on all listed public tables. Sensitive tables such as `orders`, `order_items`, `payment_records`, `payment_settings`, `notification_log`, `admin_profiles`, and `admin_audit_logs` have no direct `anon` or `authenticated` table grants in the inspected grant list; service-role grants are present for trusted Edge Function operations. This is intentional for the current server-mediated access model. Do not add broad RLS policies just to remove Advisor warnings. Recheck grants/policies after every schema change.

## Index audit result
The staging dataset is small and many indexes report zero scans, while core indexes have been used (e.g. order item/order ID, payment/order ID, order number, tracking token). Do not delete indexes solely based on zero scans; index stats reset and low-volume tables make that signal unreliable. Capture real query plans and production query stats before any removal. The new rate-limit table has a timestamp index for periodic stale-row cleanup.

## End-to-end staging test checklist
- [ ] Set up and test leaked-password protection in staging.
- [ ] Login with correct Owner credentials; invalid password returns a generic error; repeated failures eventually return HTTP 429.
- [ ] Confirm staff with limited permissions cannot use unauthorized backend actions.
- [ ] Confirm valid tracking lookup works, wrong WhatsApp/nonexistent ID returns no order data, and repeated requests eventually return HTTP 429.
- [ ] Confirm private-token tracking continues to work.
- [ ] Create multi-menu order and verify authoritative totals, DLC transaction code, schedule, receiving method, and delivery address.
- [ ] Confirm capacity/date reservation and 18:00 WITA cutoff behavior; run concurrent checkout tests before production.
- [ ] Confirm proof upload/re-upload, payment verification, WhatsApp notification, and operational status gating.
- [ ] Confirm the new dashboard funnel counts change after page view, menu view, add-to-order, checkout, successful order, proof upload, and WhatsApp click.
- [ ] Verify anonymous/authenticated REST requests cannot read new metrics/rate-limit tables.
- [ ] Verify security headers on the staging preview response.
- [ ] Run GitHub Actions static checks and manually inspect the Preview deployment on desktop/mobile.
- [ ] Review Supabase security/performance advisors after tests.
- [ ] Owner approves promotion only after all mandatory checks pass.

## Index and performance queries
Use read-only query plans on staging, e.g. `EXPLAIN (ANALYZE, BUFFERS) SELECT ...` for the actual orders-list, tracking lookup, order-items lookup, and payment queue queries. Never run `ANALYZE` or delete indexes on production as an optimization experiment without a separate change plan.

## Known limitations / no-cost decisions
- No Google Places API integration or auto-scrolling five-star review carousel is added because a reliable official reviews feed can require API credentials/billing and no verified review dataset was supplied. The site links to the official Google Maps destination instead; never fabricate reviews.
- No external paid monitoring provider is introduced. Supabase/Vercel native logs and the aggregated dashboard are used; inspect available free-tier limits in each account.
- Vercel preview protection and branch protection settings are account-level controls and must be checked in dashboards; no API setting exposed in this workflow could safely enforce them automatically.
- Static CI is not a browser E2E test. The deployment must not be considered production-ready until the manual acceptance checklist passes.
