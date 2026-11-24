# Current PR inventory — 21 November 2026

Repository: `dlice8888/dlice-landing-page`  
Snapshot: 2026-11-21  
Source: live GitHub PR search and per-PR metadata reads.

## Totals

**125 actual PRs = 77 merged + 28 closed without merge + 20 open.**

The previous 20-November inventory recorded 112 PRs and 9 open. This snapshot has 20 open PRs. PR #124 is closed as superseded by #120 and PR #125 is closed as superseded by #127. The 20 open rows below were individually read.

## Open PRs

| PR | Base | Draft | Mergeable | Scope / disposition |
|---:|---|---|---|---|
| #127 | staging | Yes | Yes | Atomic proof submission + expiry + payment-attempt supersession; 16 proof + 14 supersession pgTAP assertions; exact-head quality, disposable migration replay, CORS, KDS and procurement contracts PASS on 5c597c2e; expiry migration/test blobs identical to #125; browser concurrency and global Storage orphan sweeper remain |
| #126 | staging | Yes | Yes | SaaS tenant/member isolation + onboarding + invitation lifecycle; 35 RLS, 17 onboarding and 15 invitation pgTAP assertions; exact head bb008c55 has quality, disposable replay, KDS/CORS/procurement contracts PASS; existing Tenant A/B identities use passwordless Admin magic links; P01-P09 NOT RUN because staging Environment/secret presence and dispatch are unverified |


| #123 | staging | Yes | Yes | Online checkout idempotency with stable key, fingerprint and atomic replay ledger; 7 pgTAP assertions; exact-head quality and disposable replay PASS; browser response-drop/concurrent request runtime NOT RUN |
| #122 | staging | Yes | Yes | 24 FK covering indexes for 26 warnings; latest head adds safe removal of two zero-scan prefix duplicates; exact-head quality + replay PASS; 2 redundant prefix indexes proposed for removal, 47 other zero-scan indexes retained pending workload evidence |
| #121 | staging | Yes | Yes | Current 189-feature matrix reconciliation and evidence-based progress scoring; documentation only |
| #120 | staging | Yes | Yes | Canonical atomic permission/profile/password mutation audit; exact head 471f4a33 has all six workflows PASS. 35 profile-mutation + 11 permission + 11 invite pgTAP plans; 7 SQL test files / 124 total pgTAP assertions PASS; password reset uses durable audit intent/outcome; staging mutation runtime NOT RUN |
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

1. There are 20 open PRs, not 9 as shown in the 20-November snapshot.
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
- Vercel preview for PR #126 is READY only on stale commit 1bd648704172fecb2885b62fb3c51b7720da469c; current head bb008c55 has no matching Preview. PR #120's last preview is READY on older commit `cfa72df3fa8e9147e585f18e02470df1b5c17300`; no preview exists yet for current head `29d6d808c2b56eb9596335805499266de4e1b4ba`. This is a build/deployment result, not runtime feature acceptance. Project SSO protection is enabled for all deployment types except custom domains; password protection and trusted IP restrictions are disabled. Custom-domain staging/production exposure must be verified before treating those domains as protected QA surfaces.

## Fresh GitHub release-protection read — 21 November 2026

GitHub currently returns one active repository ruleset, **#27559290**, applied to `~ALL` branches. It has useful protections (signed commits, linear history, deletion/non-fast-forward prevention, CODEOWNERS approval, last-push approval, review-thread resolution, CodeQL/high-severity scanning and code-quality errors), but it is **not a sufficient release gate**:
- Required approving review count: **0**.
- Required status checks: **empty**.
- Required deployment environments/reviewers: **empty**.
- 11 bypass actors (DeployKey, repository roles and integrations) have `bypass_mode=always`.
- The active connection reports `current_user_can_bypass=always`.
- Branch-protection reads for `main` and `staging` still return 403; staging environment protection settings are not readable through the current connector.

The ruleset currently has zero required status checks and zero required deployment environments, so automated CI and deployment gating are incomplete. It also has `require_code_owner_review=true` and `require_last_push_approval=true` as repository-level settings. These are platform constraints, not feature acceptance criteria; the connected GitHub integration exposes no ruleset-write action. They may still affect merge eligibility. Do not treat the ruleset as a complete release gate until the required checks and deployment protections are configured.


## Supabase existing-identity and latest exact-head verification — 21 November 2026

- Four existing Auth identities were found in Supabase staging. The active Owner identity belongs to `dlice-default`; the active QA Branch A identity belongs to `dlice-qa-isolation-b`. The existing identities are retained; no Auth account, password, membership or app metadata was changed.
- Supabase Auth stores password hashes; the current connected Supabase actions expose no Auth Admin generate-link or session-mint operation. Therefore the existing accounts cannot be used for password login from this connected workflow without a valid credential or an authorized passwordless-session mechanism. No secret values were read.
- Direct-client RLS is intentionally deny-by-default on `branches`, `tenants` and `tenant_memberships`. Authenticated-role SQL probes confirmed zero direct-client rows for both existing identities, as expected under the explicit `deny_direct_client_access` policies. This is a direct-client boundary test only; it is not evidence of successful Tenant A/B isolation through the service-role Edge Function/API.
- PR #126 exact head `bb008c55a4d98afe5264b4ccde4f28f129bc162`: full disposable migration replay PASS; 35 RLS, 17 onboarding and 15 invitation pgTAP suites; quality, CORS, KDS and procurement contracts PASS. Actual Tenant A/B API own-read/write and cross-tenant negative probes remain NOT RUN.
- PR #127 exact head `5c597c2ec37a130501ed19591cfc9383396ba1b6`: full disposable migration replay PASS; quality, CORS, KDS and procurement contracts PASS; 16 proof and 14 supersession assertions included. Browser concurrency and global Storage orphan cleanup remain open.
- Vercel project `dlice-landing-page` is present. PR #126 preview is READY on its exact head. No preview deployment was found for PR #127's current head.
- Supabase staging migration drift remains 52 repository migration files versus 49 applied migrations. The three outstanding source migrations remain `20261120100000`, `20261120110000`, and `20261120120000`. No shared staging migration was applied.
- Security Advisor: native leaked-password protection DISABLED. Performance Advisor: 26 unindexed foreign keys and 49 unused indexes. Health Advisor: no findings.


## Superseding live PR inventory — 21 November 2026, 19:42 WIB

| PR | Current head | State | Exact-head CI / disposable replay | Runtime / test disposition |
|---:|---|---|---|---|
| #126 | `07d7c51c2cbea21b9cd49a480614e004fe7bf417` | OPEN / DRAFT | Quality, CORS, KDS, procurement contracts and full disposable replay PASS; 35 RLS + 17 onboarding + 15 invitation pgTAP plans | P01–P09 NOT RUN; service-role secret presence and staging Environment protection not verified; no dispatch action available |
| #120 | `471f4a330a4da0cb13afe60ddeeb520e28dc0e88` | OPEN / DRAFT | All six applicable CI/disposable replay workflows PASS; profile-mutation pgTAP plan(35), permission plan(11), invitation plan(11); 7 SQL test files / 124 total assertions PASS | Staging mutation-path runtime NOT RUN; password reset now uses durable audit intent/outcome |
| #124 | `a74200d60d6af06df5a5da4ed87a464283f0f9ff` | CLOSED | Superseded by #120; shared password-guard helper, unit test, migration and SQL test have identical blob SHAs | Do not reopen or merge; #120 is canonical |
| #123 | `31976673a9289add4c1bb10d6f29f3ff6c3c15a5` | OPEN / DRAFT | Quality, idempotency contract, CORS, KDS, procurement contracts and disposable replay PASS | Browser retry/drop-response, concurrent duplicate and payment/webhook E2E NOT RUN |

| #127 | `5c597c2ec37a130501ed19591cfc9383396ba1b6` | OPEN / DRAFT | Quality, atomic proof contract, CORS, KDS, procurement contracts and disposable replay PASS | Payment proof retry, expiry and supersession E2E NOT RUN; no current-head Vercel Preview |

### Reconciliation notes

- #120 contains the audited permission/profile/password mutation paths and password guard. PR #124 is CLOSED and superseded; do not reopen or merge it independently. #120 remains the canonical implementation branch.
- #120 and #126 both modify invitation issue/accept paths and `supabase/functions/dlice-orders/index.ts`. Their RPC signatures differ. Rebase/reconcile to one canonical invite flow before merge.
- #123 and #126 still have a hard migration version collision at `20261121130000` with different SQL contents. Resolve through `supabase migration new`/approved rename workflow and rerun combined disposable replay.
- #127 is 30 commits ahead of #125 and contains the exact same `20261121140000_order_expiry_payment_lifecycle.sql` blob. Treat #125 as the earlier dependency slice; do not apply duplicate migration content.
- Merge readiness requires all scoped automated tests, migration replay, runtime probes and explicit staging/release gates to pass; green CI alone is insufficient.

### GitHub ruleset recheck

Active ruleset #27559290 applies to `~ALL` branches, but requires 0 approvals, 0 status checks and 0 deployment environments. Eleven bypass actors have `always` bypass; the connected identity can bypass. The ruleset is not a sufficient release gate. No mutation was made because the connected GitHub integration does not expose ruleset administration.

## Current execution delta — 21 November 2026

- PR #124 is CLOSED as superseded by #120; #125 is CLOSED as superseded by #127. PR #120 remains OPEN/Draft and is the canonical permission/profile/password-guard implementation.
- PR #123 uses migration version 20261121135000; PR #126 uses 20261121130000. There is no version collision. Their invitation migration/test/RPC path is shared; only the replayed response field needs alignment.
- PR #123 exact-head quality run 44909182929 PASS; CORS, KDS and procurement contract jobs PASS. Disposable replay 44909182869 was still in progress at snapshot time.
- PR #126 exact-head disposable replay 44903918177 PASS: all 52 migration files applied on disposable DB; 7 pgTAP files / 134 assertions PASS. Invitation suite declares 15 assertions and its file passed.
- P01–P09 have not been dispatched. The workflow requires the protected staging Environment and `STAGING_SUPABASE_SERVICE_ROLE_KEY`; current GitHub integration exposes neither Environment protection/secret metadata nor a workflow-dispatch action. The secret value was not read or printed.
- The two existing Auth identities are distinct and have active memberships. Tenant A has active QA-DLICE-A and DLC-B001 assignments; Tenant B has QA-TENANT-B. Both last signed in 2026-10-25; current magic-link sessions and cross-tenant probes remain NOT RUN.
- No staging migration or Edge Function deployment was performed. Tenant-isolation and public-tenant-routing release flags remain false.


## Latest verified execution update — 21 November 2026

- Open PRs: **20**; merged: **77**; closed without merge: **28**. PR #124 is closed/superseded by #120. Remaining open execution PRs: #120, #123, #126 and #127.
- PR #120 exact head `471f4a330a4da0cb13afe60ddeeb520e28dc0e88`: six of six applicable workflows PASS, including disposable migration replay and exact-head quality. The new profile-mutation suite has 35 assertions; permission mutation suite 11; invitation suite 11. No staging mutation or Edge Function deployment occurred.
- PR #123 exact head `6788c4d7da34144d279da06edea84f6d0763b796`: six of six applicable workflows PASS; online checkout pgTAP plan is 7. Parallel browser/runtime duplicate-submission test remains NOT RUN.
- PR #125 is CLOSED as superseded by #127; its expiry migration, pgTAP test and release documentation are byte-identical to the copies retained in #127.
- PR #126 exact head `bb008c55a4d98afe5264b4ccde4f28f129bc162`: quality, KDS, CORS, procurement and disposable replay PASS; replay reports 7 pgTAP files / 134 assertions. P01–P09 remains NOT RUN; the two Auth users were read-only mapped.
- PR #127 exact head `5c597c2ec37a130501ed19591cfc9383396ba1b6`: six of six applicable workflows PASS; proof upload suite plan 16 and supersession suite plan 14. Browser concurrency and global Storage orphan cleanup remain NOT RUN.
- Staging: 49 applied migrations; staging source: 52 files; three source-only migrations remain. PR #125 is closed as superseded by #127, which retains the one canonical expiry migration blob. No staging migration was applied.
- Secret presence and Environment protection: **NOT VERIFIED**. Secret value was not read or exposed. No workflow dispatch was performed because no dispatch action is available in the connected GitHub tools.
- Test-only PR acceptance is now the project standard. Active GitHub ruleset #27559290 still has CODEOWNERS and last-push approval controls enabled, 0 required status checks, 0 required deployment environments and 11 always-bypass actors. This repository-level policy cannot be edited through the connected integration.

- Vercel exact-head Preview: PR #123 READY at https://dlice-landing-page-loho5y7oz-dlice8888-7332.vercel.app; PR #125 READY at https://dlice-landing-page-96j5eiu7k-dlice8888-7332.vercel.app. No exact-head deployment record exists for #120, #126 or #127. Preview READY does not establish runtime feature acceptance; production remains unchanged.


## Current test-only execution delta — 21 November 2026

- PR #124 CLOSED / superseded by #120 after byte-identical permission-audit migration and password-guard source/test evidence was confirmed in #120. PR #125 CLOSED / superseded by #127 after the expiry migration, test and release documentation blobs were confirmed byte-identical.
- Current open PR count is 20 (77 merged, 28 closed without merge). Canonical active execution PRs: #120, #123, #126 and #127.
- PR #120 exact head 471f4a330a4da0cb13afe60ddeeb520e28dc0e88: exact-head quality, disposable replay, KDS, CORS and procurement contracts PASS; replay 7 pgTAP files / 124 assertions. Staging permission mutation E2E NOT RUN.
- PR #123 exact head 6788c4d7da34144d279da06edea84f6d0763b796: quality, disposable replay, KDS, CORS and procurement contracts PASS. Browser response-drop, retry, concurrency and late-webhook E2E NOT RUN.
- PR #126 exact head bb008c55a4d98afe5264b4ccde4f28f129bc162: quality, disposable replay, KDS, CORS and procurement contracts PASS; replay 7 pgTAP files / 134 assertions including 35 RLS, 17 onboarding and 15 invitation assertions. P01–P09 NOT RUN.
- PR #127 exact head 5c597c2ec37a130501ed19591cfc9383396ba1b6: quality, disposable replay, KDS, CORS and procurement contracts PASS. Payment proof retry/concurrency, expiry worker, compensation, supersession and global Storage orphan cleanup E2E NOT RUN.
- No #123/#126 migration version collision: #123=20261121135000 and #126=20261121130000. The #120/#126 invitation migration/test/RPC path is shared; align the replayed response field before integration.
- The latest PR #126 Vercel deployment is READY on stale commit 1bd648704172fecb2885b62fb3c51b7720da469c; no deployment matches current head bb008c55. SSO is enabled on Preview deployments; a READY stale Preview is not runtime acceptance.
- P01–P09 cannot be dispatched with the connected GitHub integration. Staging Environment protection and STAGING_SUPABASE_SERVICE_ROLE_KEY presence remain NOT VERIFIED; the secret value was not read or exposed.


## Invitation RPC consolidation — 21 November 2026

PR #120 and #126 share byte-identical migration 20261121130000_atomic_tenant_invite_lifecycle.sql (SHA b9dab9b7027e51bd5a4069b854b65a14563df6eb) and pgTAP test tenant_invite_atomic.test.sql (SHA 9c778834a0eb5e6f0a12769f1e6a214c71130688). Both Edge Function candidates call dlice_create_tenant_invite_atomic and dlice_accept_tenant_invite_atomic with matching argument contracts. The only response difference is that #120 includes replayed in the success payload while #126 omits it. Align that field before final integration; there is no migration-version collision and no competing invite RPC overload to remove.

## Current PR and test status addendum — 21 November 2026, 20:58 WIB

| PR | Current state | Exact-head evidence | Disposition |
|---:|---|---|---|
| #120 | OPEN / Draft | Latest head f37b581f: quality, CORS, KDS, procurement requisition and receiving PASS; disposable replay still IN PROGRESS. Previous head 735e4295 had 154 pgTAP assertions and replay PASS. | Canonical permission/profile/password mutation audit; #124 superseded |
| #123 | OPEN / Draft | Head 9024f2ce: 74 assertions / 5 pgTAP files; all six applicable workflows PASS | Online checkout idempotency; browser retry/concurrency E2E remains |
| #126 | OPEN / Draft | Head 4a6aa8cc: 139 assertions / 7 pgTAP files; all six applicable workflows PASS | Tenant RLS/onboarding/invitation; passwordless P01–P09 NOT RUN |
| #127 | OPEN / Draft | Head e52ea75a: 124 assertions / 7 pgTAP files; all six applicable workflows PASS | Canonical payment proof + expiry + supersession; live Storage/payment E2E remains |
| #124 | CLOSED / unmerged | Same password-guard source consolidated into #120 | Superseded by #120 |
| #125 | CLOSED / unmerged | Expiry migration/test blob is identical to #127 | Superseded by #127 |

Combined disposable migration candidate 700c2edf: 60 migrations, 14 pgTAP files, 270 assertions PASS. Run: https://github.com/dlice8888/dlice-landing-page/actions/runs/44911080939.

Project feature acceptance is test-evidence-only. PR reviewer identity/approval is not a feature acceptance criterion. Protected staging Environment, secret handling, explicit mutation authorization and backup/rollback remain separate safety controls.

No staging/production mutation was performed. P01–P09 and business E2E remain NOT RUN.


## PR consolidation and exact-head test snapshot — 21 November 2026, 14:00 UTC

| PR | State | Latest exact-head evidence | Disposition |
|---:|---|---|---|
| #111 | OPEN / DRAFT | OIDC claim tests, quality and disposable migration replay PASS at `016715bfa00d6c400d8320cbd0d2001ff3335ee8` | Passwordless broker code ready for authorized Supabase Function Secrets setup and staging deployment; P01–P09 NOT RUN |
| #120 | OPEN / DRAFT | Previous candidate `735e429517655809899a4e942368b39eb96898a5` passed 8 files / 154 pgTAP assertions; latest head `f4438a023ba23ded8dc200c3f1a9173c2e0e386e` is being revalidated; migration job was cancelled during subsequent pushes | Do not mark complete until one stable exact head has every required job PASS |
| #123 | OPEN / DRAFT | Exact head `9024f2ce6067fe4252f5110942017e27ac1ed7b5`: 5 files / 74 pgTAP tests PASS; quality, CORS, KDS and procurement contracts PASS | Contract/database evidence PASS; real browser retry/concurrency E2E still NOT RUN |
| #124 | CLOSED / UNMERGED | Same password guard and permission migration/test blobs as #120 | Superseded by #120; do not apply separately |
| #125 | CLOSED / UNMERGED | Expiry lifecycle migration/test blobs are carried by #127 | Superseded by #127; do not apply separately |
| #126 | OPEN / DRAFT | Exact head `4a6aa8ccf07e25981579a805477dffc65a13a376`: 7 files / 139 pgTAP tests PASS; invitation suite 20/20 PASS; quality, CORS, KDS and procurement contracts PASS | Disposable tests PASS; actual A/B login and cross-tenant runtime P01–P09 NOT RUN |
| #127 | OPEN / DRAFT | Exact head `e52ea75a218eedecc513ec52311adaee25f241ba`: 7 files / 124 pgTAP tests PASS; proof and supersession suites PASS; quality, CORS, KDS and procurement contracts PASS | Disposable tests PASS; Storage/browser retry, compensation and combined live reconciliation NOT RUN |

No PR in this table has been merged to staging. CI and disposable replay do not authorize shared staging migration or Edge Function deployment.

## PR #120 latest exact-head completion — 21 November 2026, 21:03 WIB

PR #120 current head is `223e0ad22e1eac15394ec9b2025ba4aaaa153108`. All six applicable workflows PASS, including disposable migration replay with 10 pgTAP files / 206 assertions. Replay: https://github.com/dlice8888/dlice-landing-page/actions/runs/44911690345. No live staging mutation was executed.

## Deployed runtime contract inspection — 21 November 2026, 21:06 WIB

Supabase reports `dlice-orders` ACTIVE at version 70 (source SHA-256 `597a371d2c05cbfa7b0e04a749e422bf826667b4539ce2b44ffe0a2efb0ff9f6`). The deployed source still hard-codes both `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.

Runtime source inspection (not an HTTP execution) confirms:
- `erp-list-inventory` requires `branchAccess(branch_id)` before reading `branch_inventory`; item metadata is limited to inventory item IDs already present in the authorized branch's balances.
- `erp-create-stock-transfer` requires active access to both source and destination branches, validates an idempotency key, and calls the server-only stock-transfer RPC.
- `erp-transition-stock-transfer` checks same-tenant source/destination for approval unless the actor is the platform owner; other transitions require branch access.
- `admin-set-permissions`, `admin-create-staff` and `admin-reset-staff-password` remain in the uncertified-action denylist and return 423 to non-platform-owner users while tenant isolation remains unreleased.
- Deployed v70 still has the legacy multi-step invitation handler. The atomic invitation route in PR #120/#126 is candidate code and has not been deployed.

Both existing QA branch assignments satisfy the deployed helper's active/date predicates. These source and fixture checks do not replace actual HTTP probes; P01–P09 remain NOT RUN.

Vercel exact-head Preview is NOT FOUND for PR #120/#123/#126/#127. Therefore browser UI E2E on the exact candidate heads cannot be claimed from a Preview deployment. The latest audit-only Preview is READY, not a substitute for candidate Preview.

## Passwordless workflow staging integration boundary — 21 November 2026, 21:10 WIB

The workflow versions are not yet aligned:
- `main` workflow file: workflow_dispatch exists, but it still reads the legacy Tenant A/B username/password secrets.
- `staging` workflow file: manual dispatch only, but it still reads the legacy Tenant A/B username/password secrets.
- PR #126 candidate workflow: uses the two existing Auth email identities and `STAGING_SUPABASE_SERVICE_ROLE_KEY` to issue one-time magic links. Its job guard requires `github.ref == refs/heads/staging`, so it cannot execute from the PR branch.

Therefore the passwordless implementation is not yet runnable on trusted staging. Do not merge PR #126 wholesale solely to install this workflow: PR #126 also contains tenant/RLS and invitation implementation plus a migration. After the protected Environment and secret presence are verified, the safe integration is a test-only staging change containing only the workflow, runtime probe script and fixture-discovery helper.

The GitHub Environment endpoint and GitHub Secrets endpoints are not exposed by the connected integration. No secret values were read. No staging workflow was dispatched.

PR #126 candidate head `8d811f6e5856ddc2034abcc2f0cc5f49b36e09a9` has quality, CORS, KDS and Procurement checks PASS; disposable migration replay remains IN PROGRESS. Its preceding tested head `4a6aa8ccf07e25981579a805477dffc65a13a376` passed 139 assertions / 7 pgTAP files. P01–P09 remain NOT RUN.

## GitHub ruleset policy mismatch — 21 November 2026, 21:15 WIB

Read-only GitHub API inspection found active repository ruleset `27559290` (`Ruleset`) still enforces reviewer-related settings:
- `required_approving_review_count=0`, `required_reviewers=[]`
- `require_code_owner_review=true`
- `require_last_push_approval=true`
- `require_review_thread_resolution=true`
- `require_extra_approval_for_unattributed_changes=true`
- Copilot code review: `review_on_push=true`, `review_draft_pull_requests=true`

At the same time, the ruleset has **zero required status checks** and **zero required deployment environments**. This is the opposite of the requested test-only governance: reviewer controls are active while automated test gates are not required by the ruleset.

The D’Lice project instructions and all currently open PR descriptions have been changed to remove the separate independent PR-review prerequisite. The repository-level ruleset has **not** been modified: the connected GitHub integration exposes no ruleset write action, and branch-protection reads return 403. Do not claim the review settings are disabled.

Target settings for a GitHub repository administrator:
1. Disable `require_code_owner_review`, `require_last_push_approval`, `require_review_thread_resolution`, `require_extra_approval_for_unattributed_changes`, and the Copilot review rule.
2. Keep `required_approving_review_count=0` and `required_reviewers=[]`.
3. Require the six exact-head CI checks: Free quality checks, disposable migration replay, runtime CORS probes, KDS contract, Procurement receiving contract and Procurement requisition contract. Add P01–P09 only after the passwordless workflow is safely integrated to trusted staging.
4. Keep required signatures, linear history, deletion/force-push protections, high-severity code scanning and code-quality errors.
5. Configure the staging deployment environment separately; do not use reviewer approval as a substitute for test evidence.

No ruleset setting was changed.

## PR #126 exact-head test completion — 21 November 2026, 21:18 WIB

PR #126 exact head `8d811f6e5856ddc2034abcc2f0cc5f49b36e09a9` has completed all six applicable workflows successfully. Disposable migration replay: 7 pgTAP files / 139 assertions PASS. [Run](https://github.com/dlice8888/dlice-landing-page/actions/runs/44912882844).

This exact head includes:
- Correct P01/P02 fixture-scope labels.
- P08/P09 postcondition query requiring zero persisted `stock_transfers` rows after a cross-tenant 403.
- Supabase API key header compatibility: new `sb_secret_` keys are sent on `apikey` only; legacy service-role JWTs also use `Authorization: Bearer`.

P01–P09 remain NOT RUN. The passwordless workflow is still only on the PR branch; the current staging branch workflow still uses legacy username/password secrets. Staging Environment protection and secret presence remain NOT VERIFIED.

## Vercel exact-head verification — 21 November 2026, 21:20 WIB

Vercel deployment lookup by exact Git commit SHA returned zero deployments for:
- PR #120: `223e0ad22e1eac15394ec9b2025ba4aaaa153108`
- PR #123: `9024f2ce6067fe4252f5110942017e27ac1ed7b5`
- PR #126: `8d811f6e5856ddc2034abcc2f0cc5f49b36e09a9`
- PR #127: `e52ea75a218eedecc513ec52311adaee25f241ba`
- Latest audit branch head: `4743fc1b34ea14eabe8eb6be5131d3b558e42ce5`

The most recent READY audit preview found is commit `30beb0824ce22b123e9d782be272661c58ca6308`, which is stale and not the latest audit branch head. It is not a valid browser E2E target for current candidate code. Therefore no exact-head browser E2E or visual QA is claimed.

## Superseding CI-only gate update — 22 November 2026

- The repository rulesets API currently returns **zero rulesets**. PR #120 has no requested reviews. Commit signatures and independent review are not acceptance gates; exact-head CI is the engineering gate.
- PR #120 head `4c12e4b2371ba11525a4e2c0c8bd5177259a2f6f` passed all applicable GitHub Actions and Vercel checks, then merged to `staging` at `5f6fa00c7335247684f7d88410a0c506de49a5a9`.
- PR #121 head `1daeb32af34cd08ac798dd984d47edee5df80f15`: matrix row-count/score/weight contract is in the quality workflow; exact-head quality and Vercel checks PASS.
- The `staging` Environment exists with no protection rules or deployment-branch policy. Classic branch-protection settings and Environment secret names are not readable through the connected integration (HTTP 403); no secret values were read.
- Staging run `45017642887`: P01/P02 PASS, P03 FAIL on HTTP 503 from both membership lookups, P04–P09 BLOCKED; six supplemental probes BLOCKED. Temporary sessions were revoked (HTTP 204); no account/password change, migration, Edge Function deployment or production change was performed. Acceptance remains failed pending a fix and full rerun.
- Historical ruleset observations below describe the 21 November snapshot only and are superseded for current policy state by this update.



## Superseding live audit delta — 23 November 2026, 18:47 WIB

- PR #121 matrix snapshot counts **95 PARTIAL + 88 NOT VERIFIED + 6 BLOCKED + 0 DONE = 189**. Its exact-head commit `726a680b956496d8492c852577d573f4995b7ef9` has a READY Vercel Preview, but its Free quality checks failed because `tests/contracts/feature-matrix-contract.test.mjs` still expected 92/91/6 while the matrix contains 95/88/6. This is a metadata contract failure, not an application code failure.
- On the existing audit branch, the contract assertion was updated to 95/88/6 and the remediation register was appended with the superseding snapshot. These are documentation/test-metadata changes only; no PR was merged.
- PR #123, #126, #127 and #122 currently show successful exact-head quality/disposable replay and relevant contract workflows in the latest inspected run summaries. This does not prove live business E2E or staging acceptance.
- Live staging still has 49 applied migrations and 52 source migration files; three source-only versions remain as documented in the migration reconciliation.
- No merge, shared staging mutation, production deployment, or release-flag change was performed.


## Superseding staging migration and PR inventory — 24 November 2026

- PR #120 and PR #121 are now merged to staging. PR #129 is also merged; current staging SHA is `b59432f5fadae6eb20811bd411a85431455ee227` after the documentation-only PR #121 merge.
- Current open PR inventory from GitHub: 18 PRs — #127, #126, #123, #122, #119, #118, #117, #116, #115, #114, #113, #112, #111, #109, #108, #107, #104 and #71.
- Exact source/database migration parity has been re-counted: 56 source SQL files, 49 applied versions, 7 source-only migrations, 0 DB-only versions, 0 duplicate source versions. This supersedes older 52/49/3 notes.
- The seven source-only migrations are listed in `FNB_OS_MIGRATION_RECONCILIATION.md`. PR #120 contributes four of them (`20261121100000`, `20261121130000`, `20261121160000`, `20261121170000`); the earlier three are Owner/Tenant bootstrap, Command Center summary and branch checklist audit.
- PR #120's exact-head quality and disposable migration replay passed before it was merged; its migrations remain unapplied in the shared staging database. Do not conflate PR merge with migration application.
- Current staging tenant acceptance on SHA `02c32c31315725c7639f249978efc4b8d486cab5`: P01–P09 9/9 PASS, supplemental RLS/RPC 6/6 PASS, auth action probes 230/230 PASS; run `45230589775`. PR #121 docs merge to `b59432f5fadae6eb20811bd411a85431455ee227` passed quality run `45232921718`.
- Both release flags remain false. No production changes or shared staging migrations were performed by the PR #121 documentation merge.


## Current staging head and open PR checkpoint — 24 November 2026

- Current staging head: `666f2a432e236f15161cef8d2d9905279d0f5144`.
- PR #120, #121, #129, #130, #131 and #132 are merged to staging.
- Current open PRs (18): #127, #126, #123, #122, #119, #118, #117, #116, #115, #114, #113, #112, #111, #109, #108, #107, #104 and #71.
- Exact-head Free quality: [run 45236931620](https://github.com/dlice8888/dlice-landing-page/actions/runs/45236931620), PASS.
- Latest tenant acceptance: [run 45236931758](https://github.com/dlice8888/dlice-landing-page/actions/runs/45236931758), P01–P09 9/9 PASS, supplemental 6/6 PASS, auth action probes 230/230 PASS, both session cleanups PASS.
- Supabase staging migration parity: 56 source SQL files, 49 applied, 7 source-only, 0 DB-only, 0 duplicate versions. Seven pending files are listed in `FNB_OS_MIGRATION_RECONCILIATION.md`; none was applied by the above merges.
- Vercel Preview deployment `dpl_WA4PNxDM97qGxzT4Mva9sWG9xkQq` is READY for the exact staging SHA; no Production target.
- PR #130 removes the missing password-secret dependency for positive business E2E by using one-time magic links for existing identities. Both workflows remain manual and require explicit QA mutation confirmation. Do not mark issue #45 complete until both business workflows are actually run and their database reconciliation artifacts pass.
- Preserve `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.


---

## Live PR reconciliation refresh — 24 November 2026, 07:12 WIB

This section supersedes the 21-November open-PR table where it conflicts with live GitHub metadata. Current staging head: `6b26298fab0341166413de08a01c850fd1636d29`. There are **18 open PRs**. Every PR targeting `staging` below has a base SHA older than the current staging head; all require exact-head ancestry/rebase/mergeability review and fresh quality + disposable replay before integration. The historical PR-head CI result is not transferable to the new base.

### Current open PRs and disposition

| PR | Target | Head SHA (short) | Live base SHA (short) | Disposition |
|---:|---|---|---|---|
| #127 payment-proof atomicity | staging | `e52ea75` | `78f929d` | Highest transaction integrity priority after #123/#126 reconciliation; overlaps `dlice-orders/index.ts`, `quality-checks.yml`, `disposable-migration-replay.yml`, `index.html`; 3-way migration/test review required |
| #126 direct-client tenant RLS | staging | `1b0b952` | `5f6fa00` | Security P0; overlaps #123/#127/#109/#71 on `dlice-orders/index.ts`; must revalidate against P01-P09 baseline |
| #123 online-order idempotency | staging | `9024f2c` | `78f929d` | Order integrity P0; overlaps #127 on workflow/index files and #126/#109/#71 on Edge Function |
| #122 FK covering indexes | staging | `5aff3ee` | `78f929d` | Performance P1; inspect EXPLAIN/workload and disposable replay; do not drop unused indexes without evidence |
| #119 scheduled policy audit | main | `c58f122` | `2964ae7` | Main-only security change; review against #118/#113; do not merge into staging as a substitute |
| #118 manual staging mutation confirmation | staging | `5929426` | `78f929d` | Policy overlap with #130; compare exact workflow semantics, preserve explicit confirmation and no scheduled mutation |
| #114 cross-module tenant acceptance | staging | `0cb3bee` | `78f929d` | Overlaps #111/#71 on tenant probe scripts and #112/#123/#127 on quality workflow; rebase and prove coverage not duplicate |
| #113 scheduled mutation bypass prevention | main | `259eb59` | `de9c0fb` | Main-only security; compare with #119 and verify no scheduled mutation remains |
| #112 boolean platform_owner hardening | staging | `82edeeb` | `78f929d` | Security P0; exact-head SQL/ACL replay and runtime admin-bootstrap probe required |
| #111 OIDC tenant session broker | staging | `016715b` | `78f929d` | Stacked security change; overlaps #114/#71 on runtime tenant probe, #112/#123/#127 on quality workflow; needs secret-free OIDC and live session proof |
| #109 same-tenant stock transfers | staging | `9cfe616` | `39a9c96` | Security P0; overlaps #123/#126/#127/#71 on Edge Function; preserve current P01-P09 denial semantics |
| #108 historical PR/file overlap inventory | staging | `cd6649d` | `39a9c96` | Documentation; reconcile with this current inventory and close/supersede only after complete history verified |
| #107 frontend runtime config | staging | `db6c5fe` | `39a9c96` | Runtime config; verify only staging environment variable names/presence without printing values; no production changes |
| #104 production CORS contract | main | `a510f34` | `2bb254b` | Main-only source parity; no production deploy; compare against staging CORS proof separately |
| #71 tenant fixture validation | staging | `d8bc78d` | `010fd39` | Historical tenant test PR; overlaps #109/#123/#126/#127 on Edge Function and #111/#114 on probe scripts; likely carry-forward/supersession candidate after full diff audit |
| #117 OIDC session broker rebase | main | `748445e` | `2964ae7` | Merge conflict reported; resolve only after #111/#114 dependency decision |
| #116 OIDC backup branch | main | `67af978` | `2964ae7` | Merge conflict reported; backup/reference only unless dependency audit proves otherwise |
| #115 staging branch PR into main | main | `6b26298` | `2964ae7` | Do not merge as-is: it proposes promoting the entire staging head into main, bypassing per-PR production release gates |

### Verified changed-file overlap

- #126 ↔ #123/#127/#109/#71: `supabase/functions/dlice-orders/index.ts`.
- #127 ↔ #123: `quality-checks.yml`, `disposable-migration-replay.yml`, `index.html`, Edge Function.
- #114 ↔ #111: tenant probe contract and runtime probe scripts.
- #111 ↔ #112/#123/#127: shared `quality-checks.yml`.
- #118 is a workflow-policy predecessor/overlap to the explicit-confirmation behavior now integrated in #130; compare behavior before disposition.
- #109/#71 and #123/#127 share the Edge Function file; no mass merge or blind cherry-pick.

### Integration order and safety gates

1. Reconcile #126 and #109 security/tenant changes against current P01-P09 acceptance; do not weaken fail-closed routes or release flags.
2. Reconcile #123 order idempotency with #127 payment-proof/expiry; review the shared Edge Function and migrations as one dependency graph, but integrate/test in controlled PR-sized steps.
3. Reconcile #112 owner metadata boolean hardening with current admin-bootstrap 403 probe contract.
4. Resolve #111/#114/#71 tenant-session/probe overlap; avoid duplicate or stale workflow coverage.
5. Review #118 against #130 and #119/#113 for scheduled mutation policy.
6. Review #122 with EXPLAIN and representative workload; preserve 49 unused-index suggestions unless measured evidence justifies a change.
7. Keep #115 out of production promotion; #116/#117 remain conflicted until the OIDC stack is reconciled.
8. For each selected PR: rebase/merge conflict resolution → exact-head quality → disposable migration replay → targeted runtime tests → DB reconciliation → only then staging integration. No mass merge.

No PR is merged by this inventory refresh. No migrations, Auth metadata, Edge Function, shared staging data, Vercel production target or release flags are changed.
