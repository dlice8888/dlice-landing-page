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
| #127 | staging | Yes | Yes | Atomic customer payment-proof RPC + retry key; exact-head quality, disposable replay, KDS, CORS and procurement contracts PASS; browser concurrency and global Storage orphan sweeper remain pending |
| #126 | staging | Yes | Yes | SaaS tenant/member isolation + onboarding + invitation lifecycle; 35 RLS, 17 onboarding and 15 invitation pgTAP assertions; exact-head quality, disposable replay, KDS, CORS and procurement contracts PASS; real Tenant A/B runtime remains unproven |
| #125 | staging | Yes | Yes | Unpaid + unproven pending-payment expiry, rejected-payment compensation, stale no-proof payment cleanup and one-minute pg_cron worker; 27 pgTAP assertions; exact-head free quality, KDS and disposable migration replay PASS |
| #124 | staging | Yes | Yes | Free application-layer k-anonymity breached-password guard; quality and disposable replay PASS; Supabase native leaked-password protection remains DISABLED and direct Auth bypass remains unresolved |
| #123 | staging | Yes | Yes | Online checkout idempotency with stable key, fingerprint and atomic replay ledger; quality and disposable migration replay pass (74 pgTAP assertions); browser fault injection/concurrent runtime pending |
| #122 | staging | Yes | Yes | 24 FK covering indexes for 26 warnings; latest head adds safe removal of two zero-scan prefix duplicates; exact-head quality + replay PASS; 2 redundant prefix indexes proposed for removal, 47 other zero-scan indexes retained pending workload evidence |
| #121 | staging | Yes | Yes | Current 189-feature matrix reconciliation and evidence-based progress scoring; documentation only |
| #120 | staging | Yes | Yes | Atomic permission/profile mutation audit; ERP authorization coverage contract passes on 03a1029; invite email regex failed replay on 4894 and was rewritten to explicit NOT (email ~ regex) on cfa72df; latest exact-head quality and disposable replay IN_PROGRESS; no staging mutation |
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
| #109 | staging | No | Yes | Same-tenant stock transfer enforcement; independent review and rollout gates pending |
| #107 | staging | Yes | Yes | Environment-validated Supabase frontend runtime config; integration and exact-head validation pending |
| #71 | staging | Yes | No | Staging tenant fixture validation; merge conflict and real fixture/runtime acceptance pending |
| #104 | main | Yes | Yes | Production Edge Function source parity and fail-closed CORS contract; production runtime proof pending |

## Governance observations

1. There are 22 open PRs, not 9 as shown in the 20-November snapshot.
2. PRs #115, #116, #117 and #71 currently report `mergeable=false`; these require explicit conflict/ancestry disposition, not a blind merge.
3. #118 and #119 overlap on staging workflow mutation policy but target different branches. Reconcile file overlap and exact behavior before integrating either.
4. #108 is still open and Draft. The current feature-level matrix in #121 is 84/96/9 after two SaaS features moved to PARTIAL when PR #126 began concrete implementation. The pre-PR126 domain rows sum to 82/98/9; 93 is an arithmetic typo in the supplied total row.
5. #120 is still Draft and has no independent reviewer. Its latest fixes are awaiting exact-head CI; earlier green checks on other commits do not authorize shared-staging deployment.
6. No reviewer is currently requested on these 22 PRs in the metadata returned by GitHub; #122–#127 also have no requested reviewer in their creation metadata.

## Safety and next action

- Do not mass-merge PRs.
- Do not merge #115–#117 while `mergeable=false`.
- Do not self-approve. Independent review must come from a different authorized reviewer.
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
- Vercel preview for PR #126 is now READY on exact head `a36636974a625e4a56e84e6c61fcce3d2b7a95d8`. This supersedes the earlier stale-preview note for #126; it remains a build/deployment result, not runtime feature acceptance.

## Fresh GitHub release-protection read — 21 November 2026

GitHub currently returns one active repository ruleset, **#27559290**, applied to `~ALL` branches. It has useful protections (signed commits, linear history, deletion/non-fast-forward prevention, CODEOWNERS review, last-push approval, review-thread resolution, CodeQL/high-severity scanning and code-quality errors), but it is **not a sufficient release gate**:
- Required approving review count: **0**.
- Required status checks: **empty**.
- Required deployment environments/reviewers: **empty**.
- 11 bypass actors (DeployKey, repository roles and integrations) have `bypass_mode=always`.
- The active connection reports `current_user_can_bypass=always`.
- Branch-protection reads for `main` and `staging` still return 403; staging environment protection settings are not readable through the current connector.

Therefore independent human review and required CI/deployment checks are not enforced by this ruleset. No ruleset/branch-protection write action is exposed in the connected GitHub tools. Do not merge release PRs or treat this ruleset as a PASS until a repository administrator fixes the policy and an independent reviewer approves.
