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
- Repository is public. Direct branch metadata for both `main` and `staging` reports `protected=false`, protection disabled, and required status checks enforcement `off`. Repository rulesets API returned an empty list. This is a verified P0 release-protection gap.
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
| #71 | Open, Draft | staging | `fix/staging-tenant-fixtures-20261103` | true | HOLD: PR #71 improves credential contract on its head, but staging still has fallbacks/hard-coded IDs; full P01–P09 coverage and runtime proof are outstanding |
| #76 | Open, Draft | staging | `feat/erp-command-center-foundation` | true | Partial implementation; authenticated Owner dashboard and KPI reconciliation not proven |
| #77 | Open, Draft | staging | `fix/branch-checklist-audit-atomicity-20261114` | true | Disposable DB/contract evidence reported in PR; authenticated branch-role staging acceptance outstanding |
| #78 | Open, Draft | staging | `fix/atomic-tenant-bootstrap-staging-20261114` | true | Disposable DB/contract evidence reported in PR; authenticated Owner and Tenant A/B acceptance outstanding |

No PR was merged, closed, or retargeted during this audit.

## GitHub workflow discovery

Two different workflows exist on `staging` and must not be conflated:

1. `.github/workflows/staging-auth-tenant-negative.yml` is a legacy single-identity negative probe. It runs on push only, references legacy Branch A username/password secrets, and hard-codes the staging URL, publishable key, and Edge Function URL.
2. `.github/workflows/staging-runtime-tenant-isolation.yml` is the authenticated nine-probe workflow. It has `workflow_dispatch` and trusted staging push triggers. On `staging`, it uses legacy credential fallbacks and hard-codes tenant, branch, and user fixture IDs.

On PR #71 head, the runtime workflow removes the credential fallbacks and moves branch/user IDs to Environment variables, but still does not externalize tenant IDs. The PR #71 runner requires staging URL/key, four canonical Tenant A/B credentials, and branch/user identifiers. The earlier prompt's Tenant A candidate user and PR #71's Tenant A candidate are both active Auth users with active membership in Tenant A; they are different identities, so the authorized test-account owner must select the canonical QA identity rather than silently substituting one. It emits nine independent records (login A/B, identity distinct, own-branch reads A/B, cross-branch reads A/B, cross-branch writes A/B), with explicit BLOCKED results on failed preflight.

Those nine assertions do not cover the full requested P01–P09 domains: full tenant/membership relational preflight, broad branch isolation across all relevant paths, offline queue/idempotency, and broad module regression are not included as separate acceptance domains. No authenticated P01–P09 final run was executed.

## Supabase migration history

- Staging migration history returned 46 entries, ending at `20261027140145`.
- The database migration tracking table contains version `20261022140302`, name `add_missing_fk_supporting_indexes`.
- Recursive Git tree inspection of the `staging` commit did not contain a path with version `20261022140302`; the expected source path returned 404 on `staging` and `main`; GitHub code search for the version in this repository returned zero results. A check of the historical branch `audit/migration-reconciliation-runtime-tests-20261027` at the expected path also returned 404.
- Therefore database history confirms an applied migration record, but source recovery, original commit, checksum, and parity remain **BLOCKED/UNKNOWN**. Do not synthesize replacement SQL or replay it.
- No migration was applied by this audit.

## Vercel Preview

- Connected project: `dlice-landing-page`.
- Inspected deployment: `dpl_FGzwhm7fn7PowFJHJ2FE4wLRHUoD`, state `READY`.
- Deployment source branch: `fix/tenant-scoped-permissions-qa`.
- Deployment commit: `79f785711f70af51926bca07f7f4cfddbb0f6179`.
- Target was `null` in deployment metadata; it is treated as Preview evidence, not a production release.
- READY proves deployment build/deploy completion only; authenticated browser and tenant-isolation acceptance were not performed.

## Staging data snapshot (read-only)

- 2 tenant rows, 1 active tenant.
- 155 branch rows, 5 active branches.
- 3 tenant membership rows, all 3 active. Tenant `dlice-default` has 2 active memberships; `dlice-qa-isolation-b` has 1.
- 1 active Owner profile.
- Tenant `dlice-default`: 154 branches and 2 inventory balance rows (total on-hand 1,240).
- Tenant `dlice-qa-isolation-b`: 1 branch and 2 inventory balance rows (total on-hand 800). This supersedes the older PR #71 description stating Tenant B had zero inventory.
- Auth metadata aggregate: 0 JSON boolean `platform_owner=true`; 0 string `platform_owner='true'` among non-deleted Auth users.
- The active Owner profile joins to one non-deleted Auth user, but that user has neither boolean nor string `platform_owner=true` metadata. The linked identity is not disclosed in this report. This does not prove allowlist membership; do not infer which account should be elevated.

## Security and release gates

- GitHub release protection is currently absent on both `main` and `staging`: both branch metadata responses show `protected=false`; rulesets API returns `[]`. Branch-protection mutation is not available through the connected GitHub tools. A repository administrator must configure required independent PR review, required checks, no force-push/delete, and staging deployment protection. Do not merge or release until this is fixed.

- Preserve `TENANT_ISOLATION_RELEASED=false`.
- Preserve `PUBLIC_TENANT_ROUTING_RELEASED=false`.
- No production database, production environment variable, production deployment, or production data was changed.
- Supabase security advisor returned one warning: leaked-password protection disabled. This is recorded as an advisory; it is not permission to weaken any other control.
- GitHub Environment secret/variable plaintext is not readable through this audit. Presence and runtime validity are not established.
- The staging runtime workflow does not implement the requested six-secret/six-variable contract: it has legacy credential fallbacks and hard-coded fixture IDs. PR #71's head removes the credential fallbacks and externalizes four branch/user variables, but still omits tenant ID variables and has not been independently reviewed or merged.
- Read-only aggregate query found 1 active Owner profile, but 0 non-deleted Auth users with `raw_app_meta_data.platform_owner` as JSON boolean true and 0 with it as string `true`. The matching Owner identity/UUID and server-side allowlist agreement have not been established. No metadata was changed.
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
