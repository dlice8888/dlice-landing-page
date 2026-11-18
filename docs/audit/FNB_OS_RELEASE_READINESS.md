# FnB OS Release Readiness

**Decision:** NO-GO  
**Snapshot:** 18 November 2026  
**Target:** staging only; production excluded

## Release gates

| Gate | Current result | Evidence |
|---|---|---|
| `TENANT_ISOLATION_RELEASED=false` | PRESERVED | Edge source `supabase/functions/dlice-orders/index.ts:52` |
| `PUBLIC_TENANT_ROUTING_RELEASED=false` | PRESERVED | Edge source `supabase/functions/dlice-orders/index.ts:135-144` |
| PR #64 migration | HOLD / NOT APPLIED | Staging migration history ends at `20261027140145` |
| P01–P09 | BLOCKED / NOT RUN | Last runtime attempt 44208204366 blocked before network access |
| Owner authorization | BLOCKED | Active Owner profile exists; Auth app_metadata boolean true absent; allowlist not independently verifiable |
| Worker A/B identity and scope | BLOCKED | Distinct Auth users, separate active branch_manager memberships and equal permissions; both global profiles are sales_admin, not branch_worker |
| RLS | CONFIGURATION PASS ONLY | 64/64 public tables have RLS; policy semantics not fully adversarially verified |
| Migration parity | BLOCKED | 46 applied rows vs 45 source files |
| Operational E2E | NOT VERIFIED | Required seven business flows not proven end-to-end |
| Open PR reconciliation | IN PROGRESS | 17 current open PRs, all Draft |
| GitHub protection | P0 BLOCKED | staging reports `protected=false`; rulesets empty; protection read endpoint 403 |
| Vercel Preview | READY | Preview readiness is not authenticated staging acceptance; project SSO protection is enabled for all deployments except custom domains |
| Production | UNTOUCHED | No production deployment or database change |

## External configuration actions that cannot be performed through this connection

1. **GitHub Environment `staging` secrets/variables:** verify presence of the six tenant credential secrets and six tenant fixture variables without revealing values. Location: repository Settings → Environments → staging. Reason: connected integration cannot read environment metadata; workflow dispatch API is not exposed here. Verify by trusted staging workflow preflight.
2. **P03 fixture semantics:** review/merge PR #87. The second Worker A assignment is same-tenant and valid; do not remove it merely to satisfy the old exact-one assertion. Verify P03 sees the configured QA branch and never sees the other tenant's branch.
3. **Owner Auth metadata:** through Supabase Authentication → Users / authorized Auth Admin, preserve existing app metadata and set boolean `platform_owner: true` only if the account is genuinely authorized. Verify Auth read-back and UUID allowlist membership independently.
4. **GitHub branch protection/rulesets:** configure required reviews/status checks/no force-push/no delete and staging deployment reviewers through repository Settings. The current API reports staging unprotected and rulesets empty; this audit did not weaken protection.
5. **Missing migration source:** recover `20261022140302` from the authoritative source and checksum it against the applied version.

## Additional P0 dependency

PR #85 is a Draft code candidate for the own-branch inventory read path required by P04/P06. Its exact-head quality CI passed, but it has not been merged or deployed to staging. Do not run P01–P09 against v69 expecting P04/P06 to pass; after review and staging merge, run the trusted workflow and preserve BLOCKED results if inputs are missing.

## Release sequence

Do not merge PR #64 or apply its migration until P01–P09, supplemental direct REST/RPC checks, migration replay, operational regression, independent security review and all release gates pass. Do not merge PR #74 as a bulk promotion. Do not deploy production.

## Additional P0 identity gate

Staging's two candidate tenant users are both classified globally as `sales_admin`; the database role constraint has no ordinary worker value. Their tenant membership role is `branch_manager`, but this alone does not satisfy the explicit non-Admin fixture requirement. PR #86 adds the source-only `branch_worker` role and Owner-authorized conversion path. Do not apply its migration or change user profiles until migration review and authorized Owner verification pass. P03 remains BLOCKED.

## Runtime CORS gate

Staging CORS runtime workflow [44307838539](https://github.com/dlice8888/dlice-landing-page/actions/runs/44307838539) passed all three live probes: allowlisted origin HTTP 200 with exact ACAO, foreign origin HTTP 403 without ACAO, and absent Origin HTTP 200 without fallback ACAO. This gate is PASS; tenant P01–P09 remain BLOCKED/NOT RUN.
