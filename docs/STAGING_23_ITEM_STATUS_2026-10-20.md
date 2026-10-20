# D’lice 23-point rollout status — staging only
Date: 2026-10-20

## Release rule

All code and schema changes go through a feature/documentation branch and Pull Request into `feat/staging-order-receipt-gates`. CI must pass before merge. Apply and verify database migrations in Supabase staging (`higoadrzxnhzbbwhdbmh`) first. Do not change the production database (`gdjlkrmlsurcdbwnmqgg`) or promote `https://dlice.vercel.app/` until the Owner explicitly approves after staging acceptance. No new paid services are allowed.

Legend:
- **DONE (implementation)** — the repository/configuration change exists; this does not imply browser E2E acceptance.
- **PENDING** — needs a manual account setting, runtime test, repository permission, or additional implementation.

## Checklist

| # | Workstream | Status | Evidence / remaining gate |
|---:|---|---|---|
| 1 | Supabase Auth leaked-password protection | **PENDING** | Staging Security Advisor still reports `auth_leaked_password_protection`. Enable manually in Supabase Dashboard → Authentication → Security/Password Security for staging, then retest with test accounts. |
| 2 | RLS and sensitive table privileges | **DONE (staging verified)** | Migration `20261020160307 lock_internal_table_rls` applied. All 12 internal tables have RLS and an explicit `service_role_only` policy; `anon` and `authenticated` lack SELECT privileges. Security Advisor no longer reports the 12 no-policy findings. |
| 3 | Login and tracking rate limits | **DONE (implementation)** | Database-backed `consume_rate_limit` is used for login, tracking by code/token, and order creation. Runtime 429 behavior still needs E2E confirmation. |
| 4 | Strict staging/production separation | **DONE (configuration recorded)** | Vercel Production Supabase URL/public key are scoped to Production; Preview/Development values point to staging. Confirm routing again on a fresh Preview deployment. |
| 5 | Full order-cycle security and consistency tests | **PENDING** | Static CI is not browser E2E. Test checkout, receipt/proof upload, payment verification, notifications, status transitions, tracking, concurrency, and permissions on staging. |
| 6 | Database indexes against observed queries | **DONE (evaluation; no index changes)** | Read staging `pg_stat_user_indexes`/`pg_stat_user_tables`. Core order, token, item/order, payment/order, reservation, and notification indexes have scans. Six indexes are currently unused, but staging is tiny (7 orders, 3 products) and usage counters are limited; keep them until representative workload justifies a change. `pg_stat_statements` is not available in this project. |
| 7 | Migrations as the consistent schema change source | **DONE (staging baseline)** | Fourteen migrations are recorded in staging through `lock_internal_table_rls`. Schema changes must be committed as migration files and applied to staging before production. |
| 8 | Edge Function hardening | **DONE (implementation)** | `dlice-orders` fails closed if required config is absent, has no production URL fallback, and uses atomic payment and operational status RPCs. Runtime edge-case testing remains part of item 5. |
| 9 | Audit logs and notifications | **PARTIAL** | Atomic payment/status RPCs update history/audit and reservation state; notification idempotency exists. Verify retry behavior, redaction, delivery failures, and log retention in E2E. |
| 10 | Performance and cost monitoring | **PARTIAL** | Use existing Supabase advisors/logs, Vercel deployment/runtime logs, and aggregate funnel dashboard at no additional service cost. No external telemetry or alerting provider added; review included quotas periodically. |
| 11 | Staging-to-production promotion rules | **DONE (documented gate)** | `docs/STAGING_RELEASE_CHECKLIST.md` requires acceptance evidence, rollback plan, and explicit Owner approval. Repository/account settings must still enforce the gate where available. |
| 12 | Environment variables and secrets | **DONE (policy/configuration)** | Environment matrix and secret-handling rules documented. Never expose service-role keys to browser code. Rotate/remove the one-time owner bootstrap secret after bootstrap if that has not already been done. |
| 13 | Mobile landing performance | **PARTIAL** | Hero priority/async decoding and lazy menu images are implemented. Test narrow-screen layout, checkout, image load, and tracking in an actual mobile browser before acceptance. |
| 14 | Domains, preview protection, and security headers | **PARTIAL** | `vercel.json` sets security headers; Preview SSO protection was reported enabled except custom domains. Verify owner access, exact headers, domain aliases, and no unintended public preview access. |
| 15 | Automated tests and CI as merge requirements | **PARTIAL** | Dependency-free GitHub Actions static checks run on branches and PRs and check critical source patterns. Required-status-check/branch protection is not verified as enforced in repository settings. |
| 16 | Branch and PR strategy | **PARTIAL** | Feature work targets staging via PRs. Confirm repository default/protected branches and ensure no feature branch is treated as production. Existing PR state should be reviewed before declaring the repository fully tidy. |
| 17 | Migration and documentation review | **DONE (CI check)** | CI requires migration files and release docs; migration-changing PRs must update Markdown documentation. |
| 18 | Long-term code modularity | **PENDING** | The Edge Function still needs a reviewed, behavior-preserving module-boundary plan/refactor. Do not mix a large refactor into order/payment security changes; cover with tests first. |
| 19 | Consistent product catalog source | **DONE (implementation)** | Supabase `products` is the source of truth; backend-calculated prices are authoritative. Verify product edits, disabled items, and stale client prices during E2E. |
| 20 | Checkout and abandoned-order reduction | **PARTIAL** | Multi-item checkout, receiving method/address fields, generated order summary/message, server price calculation, receipt/payment gates, and transaction-code conventions are implemented. Confirm mandatory proof upload, errors/retry, capacity conflict, and full flow in E2E. |
| 21 | Privacy-preserving sales funnel analytics | **DONE (implementation)** | Whitelisted event counts are aggregated by day without customer IDs, phone numbers, order IDs, IPs, or cookies. Confirm the staging dashboard changes and stored rows remain aggregate-only. |
| 22 | Product photos, featured products, and promotions | **PARTIAL** | Hero/menu loading improvements and real menu assets are in place. Verify image mapping on mobile; promotion effectiveness is not yet supported by a paid/third-party analytics service. |
| 23 | Tracking trust and reviews | **PARTIAL** | Order tracking and Google Maps link are present. A continuously scrolling five-star review carousel is not implemented because no verified permitted free feed is connected; never fabricate reviews or introduce a billing-based Places API. |

## Latest staging evidence

- Staging Supabase project: `higoadrzxnhzbbwhdbmh`.
- Latest staging migration list ends with `20261020160307 lock_internal_table_rls`.
- Staging `dlice-orders` Edge Function is ACTIVE, version 22.
- Latest known Vercel Preview deployment for commit `caa09630e42c321c22db5432bd2bcdc1eaf57c27` is READY at [Preview deployment](https://dlice-landing-page-af6419ttg-dlice8888-7332.vercel.app/). READY means build/deploy completed, not that E2E passed; Preview may require SSO.
- Latest Supabase Security Advisor: leaked-password protection disabled (WARN); the 12 RLS no-policy findings are gone.
- Latest Performance Advisor flags six unused indexes. Do not drop them based on this low-volume staging snapshot alone.
- Production has not been changed by this staging RLS rollout. Do not promote automatically.

## Mandatory remaining blockers before production

1. Enable leaked-password protection in staging Dashboard.
2. Complete the staging browser/mobile E2E acceptance checklist and attach evidence to the release PR.
3. Verify Preview SSO access and response headers.
4. Verify GitHub branch protection / required CI checks are enforced, or document the limitation if repository permissions prevent it.
5. Resolve or explicitly accept the pending/partial workstreams above; Owner reviews and explicitly approves the exact tested commit.
6. Only then prepare a separate production release PR and apply reviewed migrations in order. No automatic production promotion.
