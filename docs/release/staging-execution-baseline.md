# D’Lice staging execution baseline

**Audit timestamp:** 2026-11-17 (UTC; connector execution)  
**Repository:** `dlice8888/dlice-landing-page`  
**Baseline branch:** `staging`  
**Baseline commit:** `aed2733f62506ed87a5040a48f479753fdafe1b1`  
**Audit branch:** `docs/staging-execution-baseline-20261117`  
**Scope:** Read-only discovery of GitHub, Supabase staging, and Vercel Preview. No production mutation.

## Repository

- Default branch: `main`.
- Repository permission returned by GitHub: admin, maintain, push.
- `staging` ref resolved to `aed2733f62506ed87a5040a48f479753fdafe1b1`.
- Repository is public; branch listing reported `protected=false` for sampled branches. This is not a substitute for checking rulesets/branch protection.
- Production branch and release flags were not modified.

## Connected services

| Service | Resource | Observed state |
|---|---|---|
| Supabase staging | `higoadrzxnhzbbwhdbmh` / `dlice-staging` | `ACTIVE_HEALTHY` |
| Supabase production | `gdjlkrmlsurcdbwnmqgg` / `dlice-production` | `INACTIVE` at audit time; not accessed for mutation |
| Vercel | `dlice-landing-page`, project `prj_A7097nEdgzi54NQRJ9NK2h2fxPLw` | Project found |
| Vercel team | `dlice8888-7332` | Hobby |

## Pull request inventory

| PR | State | Base | Head | Mergeable | Current assessment |
|---|---|---|---|---|---|
| #64 | Open, Draft | staging | `audit/tenant-isolation-inventory-20261028` | false | HOLD: no independent approval; tenant negative runtime evidence and migration/source reconciliation outstanding |
| #71 | Open, Draft | staging | `fix/staging-tenant-fixtures-20261103` | true | HOLD: PR description and checked workflow source disagree; current staging workflow is still legacy single-user |
| #76 | Open, Draft | staging | `feat/erp-command-center-foundation` | true | Partial implementation; authenticated Owner dashboard and KPI reconciliation not proven |
| #77 | Open, Draft | staging | `fix/branch-checklist-audit-atomicity-20261114` | true | Disposable DB/contract evidence reported in PR; authenticated branch-role staging acceptance outstanding |
| #78 | Open, Draft | staging | `fix/atomic-tenant-bootstrap-staging-20261114` | true | Disposable DB/contract evidence reported in PR; authenticated Owner and Tenant A/B acceptance outstanding |

No PR was merged, closed, or retargeted during this audit.

## GitHub workflow discovery

The `staging` branch contains `.github/workflows/staging-auth-tenant-negative.yml`. Its current implementation:

- Runs on push to `staging`; no `workflow_dispatch` trigger is present.
- Uses GitHub Environment `staging`.
- References only legacy `STAGING_TEST_BRANCH_A_USERNAME` and `STAGING_TEST_BRANCH_A_PASSWORD`.
- Hard-codes the staging Supabase URL, publishable key, and Edge Function URL in workflow YAML.
- Does not reference the six tenant fixture variables or canonical independent Tenant A/B credentials.
- Executes `tests/staging/tenant-isolation-existing-identity.mjs`, a single-identity wrong-branch/permission negative test, not the complete P01–P09 two-tenant acceptance suite.

The same workflow path checked on PR #71 head also retains the legacy single-identity implementation. This conflicts with portions of PR #71's description and must be reconciled before treating its workflow as canonical.

## Supabase migration history

- Staging migration history returned 46 entries, ending at `20261027140145`.
- The database migration tracking table contains version `20261022140302`, name `add_missing_fk_supporting_indexes`.
- The expected source path `supabase/migrations/20261022140302_add_missing_fk_supporting_indexes.sql` returned 404 on `staging` and `main`; GitHub code search for the version in this repository returned zero results.
- Therefore database history confirms an applied migration record, but source recovery, original commit, checksum, and parity remain **BLOCKED/UNKNOWN**. Do not synthesize replacement SQL or replay it.
- No migration was applied by this audit.

## Vercel Preview

- Connected project: `dlice-landing-page`.
- Inspected deployment: `dpl_FGzwhm7fn7PowFJHJ2FE4wLRHUoD`, state `READY`.
- Deployment source branch: `fix/tenant-scoped-permissions-qa`.
- Deployment commit: `79f785711f70af51926bca07f7f4cfddbb0f6179`.
- Target was `null` in deployment metadata; it is treated as Preview evidence, not a production release.
- READY proves deployment build/deploy completion only; authenticated browser and tenant-isolation acceptance were not performed.

## Security and release gates

- Preserve `TENANT_ISOLATION_RELEASED=false`.
- Preserve `PUBLIC_TENANT_ROUTING_RELEASED=false`.
- No production database, production environment variable, production deployment, or production data was changed.
- Supabase security advisor returned one warning: leaked-password protection disabled. This is recorded as an advisory; it is not permission to weaken any other control.
- GitHub Environment secret/variable plaintext is not readable through this audit. Presence and runtime validity are not established.
- The currently checked staging workflow does not implement the six-secret/six-variable contract.
- Owner identity, `app_metadata.platform_owner` boolean, and server-side UUID allowlist agreement have not been verified.
- PR #64 has one COMMENTED review from the author, no independent approval in the review list, and no inline review threads.

## Administrator actions required

1. GitHub repository/environment administrator: verify Environment `staging`, canonical secret names and six fixture variables, environment protection/reviewers, deployment branch restrictions, branch rulesets, and required checks. Do not paste secret values into logs.
2. Supabase Auth/project administrator: verify the authorized existing Owner identity, boolean `app_metadata.platform_owner`, and server-side allowlist source without creating or elevating an identity for test convenience.
3. Staging data steward: provide Tenant B's required positive own-branch inventory fixture through an approved auditable operational workflow if still absent; do not seed via ad-hoc SQL.
4. Independent reviewer: review PR #64/#71/#76/#77/#78 diffs and evidence; no self-approval.
5. Migration owner: recover original migration source from historical refs/backups/artifacts and prove checksum parity before any migration action.

## Next safe execution

- Reconcile PR #71's workflow and test contract on its isolated branch; do not merge it or run credentials from unreviewed PR code.
- Recover the missing migration source from Git history/backups; keep migration status blocked until source/checksum are proven.
- Verify Owner and Tenant A/B identity/fixture state using read-only queries and authorized Auth controls.
- Run authenticated P01–P09 only from a trusted, reviewed staging workflow with two independent sessions.
- Continue PR-specific work and disposable DB rehearsals without applying pending migrations to shared staging.
