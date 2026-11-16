# Security assessment

**Overall status: BLOCKED for release.** Static checks and focused local tests
passed, but live RLS/grant/advisor review, authenticated staging acceptance,
Owner verification, and independent approval remain outstanding.

## Finding from independent review

| Severity | Finding | Status |
|---|---|---|
| 🟡 MEDIUM | A non-platform Owner with an active Head Office inventory assignment could approve another tenant's draft stock transfer by ID; the previous check did not scope Head Office assignments to the transfer's tenant. | Fixed and pushed to PR #75 at `ac1a64b9cf4a57f2ac60d4ea82a8f7001e27a2f4`. Tenant-scoped membership and assignment checks, cross-tenant owner-only exception, and regression tests were added. Checks passed on that commit; independent review and live runtime verification remain pending. |

The fix checks the source/destination tenant records, permits cross-tenant
approval only for a verified platform Owner, and otherwise requires active
membership plus an inventory Head Office assignment in the transfer tenant.
Authorization lookup errors now return an explicit server error rather than
being treated as a successful check.

## Verification completed locally

- Tenant authorization and runtime contract tests: **8/8 PASS**.
- Deno permission unit tests: **7/7 PASS**.
- Repository quality and release contract checks: **PASS**.
- Full Edge Function `deno check` remains blocked by 11 diagnostics in other
  handlers/return paths; none points to the new tenant-scoped permission helper
  or approval guard. The complete file is not type-check clean.
- `TENANT_ISOLATION_RELEASED=false` and
  `PUBLIC_TENANT_ROUTING_RELEASED=false` remain unchanged.

## Not verified live

- Supabase RLS, grants, functions, triggers, Edge Function settings, Auth
  metadata, tenant records, advisor results, and index warnings.
- Historical advisory items (Leaked Password Protection disabled, 26
  foreign-key index warnings, and 49 unused-index warnings) were not
  re-queried; their current state is unknown.
- Runtime API authorization for transfer approval or Tenant A/B isolation.
- Leaked Password Protection state, production security settings, Vercel
  protection, backup/restore, and alerting.

Do not treat passing source tests or a Preview deployment as proof of live
tenant isolation. Keep release gates closed pending trusted runtime evidence
and independent approval.
