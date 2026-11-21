# Current PR inventory — 21 November 2026

Repository: `dlice8888/dlice-landing-page`  
Snapshot: 2026-11-21  
Source: live GitHub PR search and per-PR metadata reads.

## Totals

**125 actual PRs = 77 merged + 27 closed without merge + 21 open.**

The previous 20-November inventory recorded 112 PRs and 9 open. Six additional open PRs (#115–#120) were created after that snapshot; this audit adds #121–#127. PR #124 is now closed as superseded by #120. The 21 open rows below were individually read; no other PR state was changed by this audit.

## Open PRs

| PR | Base | Draft | Mergeable | Scope / disposition |
|---:|---|---|---|---|
| #127 | staging | Yes | Yes | Atomic proof submission + expiry + payment-attempt supersession; 16 proof + 14 supersession pgTAP assertions; exact-head quality, disposable migration replay, CORS, KDS and procurement contracts PASS on 5c597c2e; expiry migration/test blobs identical to #125; browser concurrency and global Storage orphan sweeper remain |
| #126 | staging | Yes | Yes | SaaS tenant/member isolation + onboarding + invitation lifecycle; 35 RLS, 17 onboarding and 15 invitation pgTAP assertions; exact head 07d7c51c has quality, disposable replay, KDS/CORS/procurement contracts PASS; existing Tenant A/B identities use passwordless Admin magic links; P01-P09 NOT RUN because staging Environment/secret presence and dispatch are unverified |
| #125 | staging | Yes | Yes | Unpaid + unproven pending-payment expiry, rejected-payment compensation, stale no-proof payment cleanup and one-minute pg_cron worker; 27 pgTAP assertions; exact-head free quality, KDS and disposable migration replay PASS; live expiry worker NOT RUN |

| #123 | staging | Yes | Yes | Online checkout idempotency with stable key, fingerprint and atomic replay ledger; 7 pgTAP assertions; exact-head quality and disposable replay PASS; browser response-drop/concurrent request runtime NOT RUN |
| #122 | staging | Yes | Yes | 24 FK covering indexes for 26 warnings; latest head adds safe removal of two zero-scan prefix duplicates; exact-head quality + replay PASS; 2 redundant prefix indexes proposed for removal, 47 other zero-scan indexes retained pending workload evidence |
| #121 | staging | Yes | Yes | Current 189-feature matrix reconciliation and evidence-based progress scoring; documentation only |
| #120 | staging | Yes | Yes | Canonical atomic permission/profile/password mutation audit; exact head 471f4a33 has all six workflows PASS. 35 profile-mutation + 11 permission + 11 invite pgTAP assertions; password reset uses durable audit intent/outcome; staging mutation runtime NOT RUN |
| #119 | main | No | Yes | Remove scheduled staging mutations and add read-only policy audit; verify exact workflow policy before merge |
| #118 | staging | Yes | Yes | Explicit manual confirmation for staging mutation workflows; overlap with #119 requires PR-by-PR reconciliation |
| #117 | main | No | No | OIDC session broker rebase; merge conflict / base reconciliation required |
| #116 | main | No | No | Backup/OIDC stacked branch; merge conflict / disposition required |
| #115 | main | No | No | PR titled “Staging”, head branch `staging`; merge conflict / intent and branch ancestry require explicit test/ancestry disposition |
| #108 | staging | Yes | Yes | Historical PR inventory and feature matrix audit; matrix content carried forward into #121 |
| #114 | staging | Yes | Yes | PR #31 cross-module tenant acceptance carry-forward; static checks pass, runtime dispatch not done |
| #113 | main | Yes | Yes | Remove scheduled staging E2E mutation bypass; exact-head contract passed |
| #112 | staging | Yes | Yes | Owner metadata boolean and service-role RPC hardening; rollout remains gated |
| #111 | staging | Yes | Yes | OIDC tenant session broker; broker secrets/deployment/runtime validation pending |
| #109 | staging | No | Yes | Same-tenant stock transfer enforcement; P01–P09 and rollout gates pending |
| #107 | staging | Yes | Yes | Environment-validated Supabase frontend runtime config; integration and exact-head validation pending |
| #71 | staging | Yes | No | Staging tenant fixture validation; merge conflict and real fixture/runtime acceptance pending |
| #104 | main | Yes | Yes | Production Edge Function source parity and fail-closed CORS contract; production runtime proof pending |

## Governance observations

1. There are 21 open PRs, not 9 as shown in the 20-November snapshot.
2. PRs #115, #116, #117 and #71 currently report `mergeable=false`; these require explicit conflict/ancestry disposition, not a blind merge.
3. #118 and #119 overlap on staging workflow mutation policy but target different branches. Reconcile file overlap and exact behavior before integrating either.
4. #108 is still open and Draft. The current feature-level matrix in #121 is 92/91/6. The originally supplied domain rows summed to 82/98/9; 93 was an arithmetic typo. Seven earlier features moved to PARTIAL from implementation/schema evidence; three additional blocked features now move to PARTIAL after exact-head tests passed.
5. #120 remains Draft. Exact-head quality, disposable migration replay and contract jobs now PASS; staging runtime acceptance remains mandatory.

## Safety and next action

- Do not mass-merge PRs.
- Do not merge #115–#117 while `mergeable=false`.
- Preserve staging mutation confirmation, deployment protection and both release flags as false.
- Reconcile dependency order, changed-file overlap and migration lineage before integrating one PR at a time.
- This inventory authorizes no database mutation, Auth change, Edge Function deployment or production release.


## Live platform audit delta — 21 November 2026

- Supabase staging contains **49 applied migrations**.
- The staging Git branch contains **52 migration SQL files**. The three source migrations not yet applied are:
  - `20261120100000_atomic_owner_and_tenant_bootstrap.sql`
  - `20261120110000_command_center_summary.sql`
  - `20261120120000_atomic_branch_checklist_audit.sql`
- No shared-staging migration was applied during this audit.
- Supabase Security Advisor reports `auth_leaked_password_protection` WARN: native leaked-password protection is DISABLED.
- Supabase Performance Advisor reports 26 unindexed foreign keys and 49 unused indexes. Do not drop unused indexes until representative query-plan and workload evidence exists.
- Staging Procurement E2E run #44892019085 and KDS/POS/Stock/Offline E2E run #44891634215 are BLOCKED before business execution because `STAGING_TEST_OWNER_USERNAME`, `STAGING_TEST_OWNER_PASSWORD` and `STAGING_TEST_BRANCH_A_USERNAME` are absent. Secret values were not read or exposed.
- Vercel preview for PR #126 (`a36636974a625e4a56e84e6c61fcce3d2b7a95d8`) is READY on its current head. PR #120's last preview is READY on older commit `cfa72df3fa8e9147e585f18e02470df1b5c17300`; no preview exists yet for current head `29d6d808c2b56eb9596335805499266de4e1b4ba`. This is a build/deployment result, not runtime feature acceptance. Project SSO protection is enabled for all deployment types except custom domains; password protection and trusted IP restrictions are disabled. Custom-domain staging/production exposure must be verified before treating those domains as protected QA surfaces.

## Fresh GitHub release-protection read — 21 November 2026

GitHub currently returns one active repository ruleset, **#27559290**, applied to `~ALL` branches. It has useful protections (signed commits, linear history, deletion/non-fast-forward prevention, CODEOWNERS approval, last-push approval, review-thread resolution, CodeQL/high-severity scanning and code-quality errors), but it is **not a sufficient release gate**:
- Required approving review count: **0**.
- Required status checks: **empty**.
- Required deployment environments/reviewers: **empty**.
- 11 bypass actors (DeployKey, repository roles and integrations) have `bypass_mode=always`.
- The active connection reports `current_user_can_bypass=always`.
- Branch-protection reads for `main` and `staging` still return 403; staging environment protection settings are not readable through the current connector.

The ruleset currently has zero required status checks and zero required deployment environments, so automated CI and deployment gating are incomplete. It also has `require_code_owner_review=true` and `require_last_push_approval=true`; the project has removed these as acceptance criteria, but the active repository ruleset still enforces them. The connected GitHub integration exposes no ruleset-write action, so repository-admin action is needed to disable those two settings. No ruleset/branch-protection write action is exposed in the connected GitHub tools. Do not treat the ruleset as a complete release gate until the required checks and deployment protections are configured.


## Supabase existing-identity and latest exact-head verification — 21 November 2026

- Four existing Auth identities were found in Supabase staging. The active Owner identity belongs to `dlice-default`; the active QA Branch A identity belongs to `dlice-qa-isolation-b`. The existing identities are retained; no Auth account, password, membership or app metadata was changed.
- Supabase Auth stores password hashes; the current connected Supabase actions expose no Auth Admin generate-link or session-mint operation. Therefore the existing accounts cannot be used for password login from this connected workflow without a valid credential or an authorized passwordless-session mechanism. No secret values were read.
- Direct-client RLS is intentionally deny-by-default on `branches`, `tenants` and `tenant_memberships`. Authenticated-role SQL probes confirmed zero direct-client rows for both existing identities, as expected under the explicit `deny_direct_client_access` policies. This is a direct-client boundary test only; it is not evidence of successful Tenant A/B isolation through the service-role Edge Function/API.
- PR #126 exact head `07d7c51c2cbea21b9cd49a480614e004fe7bf417`: full disposable migration replay PASS; 35 RLS, 17 onboarding and 15 invitation pgTAP suites; quality, CORS, KDS and procurement contracts PASS. Actual Tenant A/B API own-read/write and cross-tenant negative probes remain NOT RUN.
- PR #127 exact head `5c597c2ec37a130501ed19591cfc9383396ba1b6`: full disposable migration replay PASS; quality, CORS, KDS and procurement contracts PASS; 16 proof and 14 supersession assertions included. Browser concurrency and global Storage orphan cleanup remain open.
- Vercel project `dlice-landing-page` is present. PR #126 preview is READY on its exact head. No preview deployment was found for PR #127's current head.
- Supabase staging migration drift remains 52 repository migration files versus 49 applied migrations. The three outstanding source migrations remain `20261120100000`, `20261120110000`, and `20261120120000`. No shared staging migration was applied.
- Security Advisor: native leaked-password protection DISABLED. Performance Advisor: 26 unindexed foreign keys and 49 unused indexes. Health Advisor: no findings.


## Superseding live PR inventory — 21 November 2026, 19:42 WIB

| PR | Current head | State | Exact-head CI / disposable replay | Runtime / test disposition |
|---:|---|---|---|---|
| #126 | `07d7c51c2cbea21b9cd49a480614e004fe7bf417` | OPEN / DRAFT | Quality, CORS, KDS, procurement contracts and full disposable replay PASS; 35 RLS + 17 onboarding + 15 invitation pgTAP plans | P01–P09 NOT RUN; service-role secret presence and staging Environment protection not verified; no dispatch action available |
| #120 | `471f4a330a4da0cb13afe60ddeeb520e28dc0e88` | OPEN / DRAFT | All six applicable CI/disposable replay workflows PASS; profile-mutation pgTAP suite plan(35), permission suite plan(11), invitation suite plan(11) | Staging mutation-path runtime NOT RUN; password reset now uses durable audit intent/outcome |
| #124 | `a74200d60d6af06df5a5da4ed87a464283f0f9ff` | CLOSED | Superseded by #120; shared password-guard helper, unit test, migration and SQL test have identical blob SHAs | Do not reopen or merge; #120 is canonical |
| #123 | `31976673a9289add4c1bb10d6f29f3ff6c3c15a5` | OPEN / DRAFT | Quality, idempotency contract, CORS, KDS, procurement contracts and disposable replay PASS | Browser retry/drop-response, concurrent duplicate and payment/webhook E2E NOT RUN |
| #125 | `1c97dd74ac3e17bf1cfdfa926cd6ab5f5a40156d` | OPEN / DRAFT | Quality, KDS contract and disposable replay PASS | Expiry worker not installed; live expiry/compensation/reconciliation E2E NOT RUN |
| #127 | `5c597c2ec37a130501ed19591cfc9383396ba1b6` | OPEN / DRAFT | Quality, atomic proof contract, CORS, KDS, procurement contracts and disposable replay PASS | Payment proof retry, expiry and supersession E2E NOT RUN; Vercel preview blocked by daily deployment limit; no review |

### Reconciliation notes

- #120 contains the audited permission/profile/password mutation paths and password guard. PR #124 is CLOSED and superseded; do not reopen or merge it independently. #120 remains the canonical implementation branch.
- #120 and #126 both modify invitation issue/accept paths and `supabase/functions/dlice-orders/index.ts`. Their RPC signatures differ. Rebase/reconcile to one canonical invite flow before merge.
- #123 and #126 still have a hard migration version collision at `20261121130000` with different SQL contents. Resolve through `supabase migration new`/approved rename workflow and rerun combined disposable replay.
- #127 is 30 commits ahead of #125 and contains the exact same `20261121140000_order_expiry_payment_lifecycle.sql` blob. Treat #125 as the earlier dependency slice; do not apply duplicate migration content.
- Merge readiness requires all scoped automated tests, migration replay, runtime probes and explicit staging/release gates to pass; green CI alone is insufficient.

### GitHub ruleset recheck

Active ruleset #27559290 applies to `~ALL` branches, but requires 0 approvals, 0 status checks and 0 deployment environments. Eleven bypass actors have `always` bypass; the connected identity can bypass. The ruleset is not a sufficient release gate. No mutation was made because the connected GitHub integration does not expose ruleset administration.

## Current execution delta — 21 November 2026

- PR #124 is CLOSED as superseded by #120; #120 remains OPEN/Draft and is the canonical permission/profile/password-guard implementation.
- PR #123/#126 migration collision remains unresolved: both source branches use version `20261121130000` with different SQL. Do not integrate both until one migration is re-versioned and combined disposable replay passes.
- PR #123 exact-head quality run 44909182929 PASS; CORS, KDS and procurement contract jobs PASS. Disposable replay 44909182869 was still in progress at snapshot time.
- PR #126 exact-head disposable replay 44903918177 PASS: all 52 migration files applied on disposable DB; 7 pgTAP files / 134 assertions PASS. Invitation suite declares 15 assertions and its file passed.
- P01–P09 have not been dispatched. The workflow requires the protected staging Environment and `STAGING_SUPABASE_SERVICE_ROLE_KEY`; current GitHub integration exposes neither Environment protection/secret metadata nor a workflow-dispatch action. The secret value was not read or printed.
- The two existing Auth identities are distinct and have active memberships. Tenant A has active QA-DLICE-A and DLC-B001 assignments; Tenant B has QA-TENANT-B. Both last signed in 2026-10-25; current magic-link sessions and cross-tenant probes remain NOT RUN.
- No staging migration or Edge Function deployment was performed. Tenant-isolation and public-tenant-routing release flags remain false.


## Latest verified execution update — 21 November 2026

- Open PRs: **21**; merged: **77**; closed without merge: **27**. PR #124 is closed/superseded by #120. Remaining open execution PRs: #120, #123, #125, #126 and #127.
- PR #120 exact head `471f4a330a4da0cb13afe60ddeeb520e28dc0e88`: six of six applicable workflows PASS, including disposable migration replay and exact-head quality. The new profile-mutation suite has 35 assertions; permission mutation suite 11; invitation suite 11. No staging mutation or Edge Function deployment occurred.
- PR #123 exact head `31976673a9289add4c1bb10d6f29f3ff6c3c15a5`: six of six applicable workflows PASS; online checkout pgTAP plan is 7. Parallel browser/runtime duplicate-submission test remains NOT RUN.
- PR #125 exact head `1c97dd74ac3e17bf1cfdfa926cd6ab5f5a40156d`: all three applicable workflows PASS; expiry suite plan is 27. Live scheduler/expiry-worker test remains NOT RUN.
- PR #126 exact head `07d7c51c2cbea21b9cd49a480614e004fe7bf417`: six of six applicable workflows PASS. P01–P09 remains NOT RUN; the two Auth users were only read-only mapped, with last sign-in 2026-10-25.
- PR #127 exact head `5c597c2ec37a130501ed19591cfc9383396ba1b6`: six of six applicable workflows PASS; proof upload suite plan 16 and supersession suite plan 14. Browser concurrency and global Storage orphan cleanup remain NOT RUN.
- Staging: 49 applied migrations; `staging` source: 52 files; three source-only migrations remain. Candidate PR migrations have a conflicting version `20261121130000` between #123 and #126; #125/#127 share the exact same expiry migration blob. No staging migration was applied.
- Secret presence and Environment protection: **NOT VERIFIED**. Secret value was not read or exposed. No workflow dispatch was performed because no dispatch action is available in the connected GitHub tools.
- Test-only PR acceptance is now the project standard. Active GitHub ruleset #27559290 still has CODEOWNERS and last-push approval controls enabled, 0 required status checks, 0 required deployment environments and 11 always-bypass actors. This repository-level policy cannot be edited through the connected integration.
