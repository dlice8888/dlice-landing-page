# Current PR inventory — 21 November 2026

Repository: `dlice8888/dlice-landing-page`  
Snapshot: 2026-11-21  
Source: live GitHub PR search and per-PR metadata reads.

## Totals

**125 actual PRs = 77 merged + 26 closed without merge + 22 open.**

The previous 20-November inventory recorded 112 PRs and 9 open. Six additional open PRs (#115–#120) were created after that snapshot; this audit adds #121–#127. The 22 open rows below were individually read. No PR is merged or closed by this audit.

## Open PRs

| PR | Base | Draft | Mergeable | Scope / disposition |
|---:|---|---|---|---|
| #127 | staging | Yes | Yes | Atomic proof submission + expiry + payment-attempt supersession; 14 pgTAP assertions; exact-head quality, disposable migration replay, CORS, KDS and procurement contracts PASS on 5c597c2e; proof-bearing sibling attempts preserved; browser concurrency and global Storage orphan sweeper remain |
| #126 | staging | Yes | Yes | SaaS tenant/member isolation + onboarding + invitation lifecycle; 35 RLS, 17 onboarding and 15 invitation pgTAP assertions; exact-head quality + full disposable replay + KDS/CORS/procurement contracts PASS on cf9d6781; existing Tenant A/B Auth users now use passwordless Admin magic links; live P01-P09 awaits staging Environment protection and one service-role secret |
| #125 | staging | Yes | Yes | Unpaid + unproven pending-payment expiry, rejected-payment compensation, stale no-proof payment cleanup and one-minute pg_cron worker; 27 pgTAP assertions; exact-head free quality, KDS and disposable migration replay PASS |
| #124 | staging | Yes | Yes | Free application-layer k-anonymity breached-password guard; quality and disposable replay PASS; Supabase native leaked-password protection remains DISABLED and direct Auth bypass remains unresolved |
| #123 | staging | Yes | Yes | Online checkout idempotency with stable key, fingerprint and atomic replay ledger; quality and disposable migration replay pass (74 pgTAP assertions); browser fault injection/concurrent runtime pending |
| #122 | staging | Yes | Yes | 24 FK covering indexes for 26 warnings; latest head adds safe removal of two zero-scan prefix duplicates; exact-head quality + replay PASS; 2 redundant prefix indexes proposed for removal, 47 other zero-scan indexes retained pending workload evidence |
| #121 | staging | Yes | Yes | Current 189-feature matrix reconciliation and evidence-based progress scoring; documentation only |
| #120 | staging | Yes | Yes | Atomic permission/profile mutation audit; removed 22,067 orphan SQL characters after COMMIT; added 11 audited-invite pgTAP assertions; exact-head quality, disposable migration replay, KDS, CORS and procurement contracts PASS on 29d6d808; 7 pgTAP files / 107 assertions PASS; staging runtime acceptance remains |
| #119 | main | No | Yes | Remove scheduled staging mutations and add read-only policy audit; verify exact workflow policy before merge |
| #118 | staging | Yes | Yes | Explicit manual confirmation for staging mutation workflows; overlap with #119 requires PR-by-PR reconciliation |
| #117 | main | No | No | OIDC session broker rebase; merge conflict / base reconciliation required |
| #116 | main | No | No | Backup/OIDC stacked branch; merge conflict / disposition required |
| #115 | main | No | No | PR titled “Staging”, head branch `staging`; merge conflict / intent and branch ancestry require review |
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

1. There are 22 open PRs, not 9 as shown in the 20-November snapshot.
2. PRs #115, #116, #117 and #71 currently report `mergeable=false`; these require explicit conflict/ancestry disposition, not a blind merge.
3. #118 and #119 overlap on staging workflow mutation policy but target different branches. Reconcile file overlap and exact behavior before integrating either.
4. #108 is still open and Draft. The current feature-level matrix in #121 is 89/91/9. The originally supplied domain rows summed to 82/98/9; 93 was an arithmetic typo. Two SaaS and five additional features moved to PARTIAL based on concrete implementation/schema evidence.
5. #120 remains Draft; PR reviewer assignment is not an acceptance criterion. Exact-head quality, disposable migration replay and contract jobs now PASS; staging runtime acceptance remains mandatory.
6. No reviewer is currently requested on these 22 PRs in the metadata returned by GitHub; #122–#127 also have no requested reviewer in their creation metadata.

## Safety and next action

- Do not mass-merge PRs.
- Do not merge #115–#117 while `mergeable=false`.
- Do not use reviewer identity or approval count as a completion metric. Use only the defined test, migration, runtime and release-gate evidence.
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

GitHub currently returns one active repository ruleset, **#27559290**, applied to `~ALL` branches. It has useful protections (signed commits, linear history, deletion/non-fast-forward prevention, CODEOWNERS review, last-push approval, review-thread resolution, CodeQL/high-severity scanning and code-quality errors), but it is **not a sufficient release gate**:
- Required approving review count: **0**.
- Required status checks: **empty**.
- Required deployment environments/reviewers: **empty**.
- 11 bypass actors (DeployKey, repository roles and integrations) have `bypass_mode=always`.
- The active connection reports `current_user_can_bypass=always`.
- Branch-protection reads for `main` and `staging` still return 403; staging environment protection settings are not readable through the current connector.

The ruleset currently has zero required status checks and zero required deployment environments, so automated CI and deployment gating are incomplete. No ruleset/branch-protection write action is exposed in the connected GitHub tools. Do not treat the ruleset as a complete release gate until the required checks and deployment protections are configured.


## Supabase existing-identity and latest exact-head verification — 21 November 2026

- Four existing Auth identities were found in Supabase staging. The active Owner identity belongs to `dlice-default`; the active QA Branch A identity belongs to `dlice-qa-isolation-b`. The existing identities are retained; no Auth account, password, membership or app metadata was changed.
- Supabase Auth stores password hashes; the current connected Supabase actions expose no Auth Admin generate-link or session-mint operation. Therefore the existing accounts cannot be used for password login from this connected workflow without a valid credential or an authorized passwordless-session mechanism. No secret values were read.
- Direct-client RLS is intentionally deny-by-default on `branches`, `tenants` and `tenant_memberships`. Authenticated-role SQL probes confirmed zero direct-client rows for both existing identities, as expected under the explicit `deny_direct_client_access` policies. This is a direct-client boundary test only; it is not evidence of successful Tenant A/B isolation through the service-role Edge Function/API.
- PR #126 exact head `a36636974a625e4a56e84e6c61fcce3d2b7a95d8`: full disposable migration replay PASS; 15 invitation pgTAP assertions PASS; quality, CORS, KDS and procurement contracts PASS. Actual Tenant A/B API own-read/write and cross-tenant negative probes remain NOT RUN.
- PR #127 exact head `5c597c2ec37a130501ed19591cfc9383396ba1b6`: full disposable migration replay PASS; quality, CORS, KDS and procurement contracts PASS; 14 payment-attempt supersession assertions included. Browser concurrency and global Storage orphan cleanup remain open.
- Vercel project `dlice-landing-page` is present. PR #126 preview is READY on its exact head. No preview deployment was found for PR #127's current head.
- Supabase staging migration drift remains 52 repository migration files versus 49 applied migrations. The three outstanding source migrations remain `20261120100000`, `20261120110000`, and `20261120120000`. No shared staging migration was applied.
- Security Advisor: native leaked-password protection DISABLED. Performance Advisor: 26 unindexed foreign keys and 49 unused indexes. Health Advisor: no findings.


## Superseding live PR inventory — 21 November 2026, 19:42 WIB

| PR | Current head | State | Exact-head CI / disposable replay | Runtime / review disposition |
|---:|---|---|---|---|
| #126 | `07d7c51c2cbea21b9cd49a480614e004fe7bf417` | OPEN / DRAFT | Quality, CORS, KDS, procurement contracts and full disposable replay PASS; invitation suite passes (15 pgTAP assertions; full replay reports 134 tests across 7 files) | P01–P09 NOT RUN; no review; protected staging service-role secret and staging dispatch still required |
| #120 | `d9aa2fbc813da48abcae38769be90de1e981c13d` | OPEN / DRAFT | Quality, permission/password contracts, CORS, KDS, procurement contracts and disposable replay PASS | No review; mutation-path live tests and complete password-path disposition remain |
| #124 | `a74200d60d6af06df5a5da4ed87a464283f0f9ff` | OPEN / DRAFT | Quality, password guard unit/contract tests, CORS, KDS, procurement contracts and disposable replay PASS | No review; guard files are byte-identical to #120 and its behavior is included in #120; treat as superseded/overlap, do not merge separately |
| #123 | `31976673a9289add4c1bb10d6f29f3ff6c3c15a5` | OPEN / DRAFT | Quality, idempotency contract, CORS, KDS, procurement contracts and disposable replay PASS | Browser retry/drop-response, concurrent duplicate and payment/webhook E2E NOT RUN |
| #125 | `1c97dd74ac3e17bf1cfdfa926cd6ab5f5a40156d` | OPEN / DRAFT | Quality, KDS contract and disposable replay PASS | Expiry worker not installed; live expiry/compensation/reconciliation E2E NOT RUN |
| #127 | `5c597c2ec37a130501ed19591cfc9383396ba1b6` | OPEN / DRAFT | Quality, atomic proof contract, CORS, KDS, procurement contracts and disposable replay PASS | Payment proof retry, expiry and supersession E2E NOT RUN; Vercel preview blocked by daily deployment limit; no review |

### Reconciliation notes

- #120 and #124 are overlapping/diverged branches. The password guard module, Deno test, Node contract test, documentation and quality workflow are byte-identical across both. #120 also contains those guard calls plus the atomic permission/profile RPCs; #124 adds no unique guard artifact. Keep #124 from being merged independently; close as superseded after #120's review disposition is accepted.
- #120 and #126 both modify invitation issue/accept paths and `supabase/functions/dlice-orders/index.ts`. Their RPC signatures differ. Rebase/reconcile to one canonical invite flow before merge.
- #123 and #126 have a hard migration version collision at `20261121130000` with different SQL contents. Resolve through the Supabase migration generator and rerun combined disposable replay.
- #127 is 30 commits ahead of #125 and contains the exact same `20261121140000_order_expiry_payment_lifecycle.sql` blob. Treat #125 as the earlier dependency slice; do not apply duplicate migration content.
- PR review submissions are not a completion metric. Merge readiness requires all scoped automated tests, migration replay, runtime probes and explicit staging/release gates to pass; green CI alone is insufficient.

### GitHub ruleset recheck

Active ruleset #27559290 applies to `~ALL` branches, but requires 0 approvals, 0 status checks and 0 deployment environments. Eleven bypass actors have `always` bypass; the connected identity can bypass. The ruleset is not a sufficient release gate. No mutation was made because the connected GitHub integration does not expose ruleset administration.
