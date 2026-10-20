# Staging implementation audit — 2026-10-21

## Release boundary

- Staging branch: `feat/staging-order-receipt-gates`
- Staging head audited: `ac4ee4071ab3ba0f9c663057253f055a324411a3`
- Staging Supabase project: `higoadrzxnhzbbwhdbmh`
- Production Supabase project: `gdjlkrmlsurcdbwnmqgg`
- Production domain: `https://dlice.vercel.app/`
- Production has not been changed by this staging audit.
- No paid provider, external analytics SDK, new Supabase branch/project, or paid Vercel feature is introduced by this audit.

## Database migration parity

- Staging currently records 15 migrations.
- Production currently records 4 migrations.
- This is an intentional release blocker, not permission to apply every migration blindly. Several later migrations add operational/admin tables and workflows; validate dependencies, seed-data effects, grants, storage policies, and rollback/recovery before an Owner-approved production release.
- Migration `20261020171825_safe_operational_retention_and_rpc_acl` is present in staging migration history and repository.
- Do not apply staging migrations to production until staging acceptance passes and the Owner explicitly approves.

## Edge Functions and Storage

- Staging `dlice-orders`: active version 23.
- Production `dlice-orders`: active version 3.
- Staging Storage has 3 buckets; production previously audited with 1 bucket. Bucket parity is not yet complete.
- Do not deploy Edge Functions or create/change production buckets without explicit release approval. First verify bucket policies, private proof access, object limits, and the app's expected bucket names.

## Security and database findings

- Staging Security Advisor currently reports leaked-password protection disabled. This setting must be enabled manually in Supabase Dashboard for staging: Authentication → Security / Password Security → leaked-password protection. Re-test with test accounts; do not change production Auth settings until an approved release.
- Production Security Advisor reports 11 RLS-enabled tables with no policies. This is an informational finding; inspected sensitive tables do not grant direct `anon`/`authenticated` table access. Do not add broad policies just to silence the advisor. Re-check grants, RLS, RPC execute privileges, and actual access paths before changing production.
- Staging policies currently include service-role-only access for internal order/payment/admin/metrics/rate-limit tables and public SELECT only for active catalog products.
- Staging read-only function privilege audit returned no public/anon/authenticated execute grants for the inspected public routines.
- Staging cleanup RPC was manually executed successfully. The result reported 0 old rate-limit rows and 0 expired metric days deleted; orders, payment records/proofs, notifications, and audit logs are preserved. The daily `pg_cron` schedule exists, but its first scheduled run still needs verification.
- Staging advisor reports 5 indexes unused since the current statistics window began. Production reports 11. Counters may reset and the staging dataset is small; do not drop indexes without workload evidence and query plans.

## Observability snapshot

Read-only unified logs query for the last 24 hours returned the following staging entries by source:
- pgbouncer_logs: 11,590
- postgrest_logs: 91
- postgres_logs: 57
- function_logs: 56
- edge_logs: 33
- function_edge_logs: 26
- storage_logs: 4
- auth_logs: 1

Production returned pgbouncer_logs 11,590 and postgres_logs 11 in the same query window. These are log-entry counts, not request counts or billable usage; investigate error/latency fields before drawing conclusions. Keep monitoring within included Supabase/Vercel logs and their free-tier retention/quotas.

## CI and branch discipline

- Dependency-free quality and staging contract tests exist in `.github/workflows/quality-checks.yml`.
- The latest workflow run observed during this audit was successful but attached to an older commit than the staging head audited above. This PR is intended to force a fresh PR check on the current staging baseline.
- GitHub branch protection / required status checks are not confirmed enforced at repository settings level. The connected GitHub tooling can inspect protection but does not provide a verified write path to enforce it. Repository owner must enable required checks for staging and production branches in GitHub settings.
- Several historical non-production branch refs remain. Their code contents were compared against staging in the previous audit and found integrated or stale; divergent history should not be force-rewritten merely to make branch labels look synchronized. Preserve history until each ref is verified and deliberately archived/deleted.
- `main` remains the production release branch and must not be merged wholesale into staging, nor moved to staging, before an approved release.

## Staging acceptance gates still open

- [ ] Enable and test leaked-password protection on staging.
- [ ] Fresh GitHub Actions checks pass on the current staging baseline and PR.
- [ ] Enforce required CI checks in GitHub branch settings.
- [ ] Verify Owner access through Vercel Preview SSO and confirm Preview uses staging Supabase.
- [ ] Browser E2E: Owner/admin auth, invalid login throttling, role boundaries, logout/expired sessions.
- [ ] Browser E2E: multi-menu checkout, authoritative totals, capacity/concurrency, order ID, receiving method, address, scheduled time.
- [ ] Browser E2E: payment proof upload validation (size/type/signature), re-upload, payment verification, notification idempotency, unpaid fulfillment rejection.
- [ ] Browser E2E: order tracking privacy/rate limits and all operational status transitions.
- [ ] Verify retention cron's first scheduled execution and record evidence.
- [ ] Reconcile staging/production migration history, Edge Function versions, and Storage buckets in a separate release plan with rollback checks.
- [ ] Audit dependencies/secrets and document findings.
- [ ] Owner approves production release explicitly only after all mandatory gates pass.

## Decision

Staging remains the only implementation target. The production site and production Supabase database/Edge Function/Storage are not to be changed until all mandatory staging acceptance gates pass and the Owner explicitly approves.
