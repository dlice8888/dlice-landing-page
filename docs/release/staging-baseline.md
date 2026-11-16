# Staging baseline

**Captured:** 2026-11-16 17:17 UTC  
**Baseline checkout:** `fix/atomic-tenant-bootstrap-staging-20261114`  
**Baseline commit:** `33a561147d20aa0e99d4e7963d62c73dfeb56fe2`  
**Status:** Immutable discovery snapshot. Follow-up findings belong in the other release reports.

## Repository and GitHub

| Item | Observed state |
|---|---|
| Default branch | `main`, SHA `8d74dbda81eb483a26d779b782fd4b37e12af770` |
| Staging branch | SHA `aed2733f62506ed87a5040a48f479753fdafe1b1` |
| Working tree at discovery | Clean |
| PR #64 | Open, Draft, unmerged; preserved |
| PR #75 | Open, non-Draft, base `staging`; head SHA `0f836799b8717f3f34c35441fc11f13e8d913ec1`; no independent reviews |
| PR #76 | Open, Draft, base `staging`; no reviews |
| PR #77 | Open, Draft, base `staging`; no reviews |
| PR #78 | Open, Draft, base `staging`; no reviews |
| Branch protection | API returned HTTP 403; rules not independently readable |
| Staging environment protection | `protection_rules` empty; `can_admins_bypass` true |
| Environment secrets and variables | Both list endpoints returned HTTP 403; names and values not independently enumerable |

PR #75 checks on the observed head were successful for quality checks, procurement
contracts, kitchen/KDS contracts, CORS probes, and Vercel Preview. This is not a
trusted staging runtime acceptance. Preview deployment
[`6sfB87az8xuFa54YdVLdmj7GNAdp`](https://vercel.com/dlice8888-7332/dlice-landing-page/6sfB87az8xuFa54YdVLdmj7GNAdp)
was Ready; it was not promoted.

## Supabase and Vercel

- The unauthenticated staging Auth health request returned HTTP 401. Without a
  project key or authorized Supabase management access, this does not verify
  project health, database connectivity, schema, migration history, RLS,
  identities, or advisors.
- Supabase and Vercel management CLIs and credentials were not available in the
  execution environment. No live database or deployment setting was changed.
- Vercel Preview status was visible through the PR check. Production deployment
  protection, environment variables, runtime logs, and rollback settings were
  not independently accessible.

## CI, migrations, runtime, and release gates

- Disposable migration replay checks were successful for PRs #76, #77, and #78.
  These checks do not constitute a staging migration or a staging replay.
- Scheduled E2E runs on `main` failed: [run 43844108130](https://github.com/dlice8888/dlice-landing-page/actions/runs/43844108130)
  (`purchase-to-stock`) and [run 43843008479](https://github.com/dlice8888/dlice-landing-page/actions/runs/43843008479)
  (`kds-pos-stock`). They are not staging runtime acceptance.
- Authenticated Tenant A/B runtime probes were not run against staging.
- Source flags remained `TENANT_ISOLATION_RELEASED=false` and
  `PUBLIC_TENANT_ROUTING_RELEASED=false`. No production database, deployment,
  branch protection, or release flag was changed.

## Evidence references

- PR #64: https://github.com/dlice8888/dlice-landing-page/pull/64
- PR #75: https://github.com/dlice8888/dlice-landing-page/pull/75
- PR #76: https://github.com/dlice8888/dlice-landing-page/pull/76
- PR #77: https://github.com/dlice8888/dlice-landing-page/pull/77
- PR #78: https://github.com/dlice8888/dlice-landing-page/pull/78
