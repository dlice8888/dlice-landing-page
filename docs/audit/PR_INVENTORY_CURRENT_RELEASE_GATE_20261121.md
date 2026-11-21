# Current PR inventory — 21 November 2026

Repository: `dlice8888/dlice-landing-page`  
Snapshot: 2026-11-21  
Source: live GitHub PR search and per-PR metadata reads.

## Totals

**125 actual PRs = 77 merged + 26 closed without merge + 22 open.**

The previous 20-November inventory recorded 112 PRs and 9 open. Six additional open PRs (#115–#120) were created after that snapshot; this audit adds #121–#127. The 22 open rows below were individually read. No PR is merged or closed by this audit. No PR is merged or closed by this audit.

## Open PRs

| PR | Base | Draft | Mergeable | Scope / disposition |
|---:|---|---|---|---|
| #127 | staging | Yes | Yes | Atomic customer payment-proof RPC + retry key; quality PASS, disposable migration replay IN_PROGRESS; Storage orphan sweeper remains a residual hardening item |
| #126 | staging | Yes | Yes | SaaS tenant direct-client RLS contract: 35 pgTAP assertions PASS; latest head adds default-deny for all admin/ERP routes; latest checks queued/in progress; API tenant A/B remains unproven |
| #125 | staging | Yes | Yes | Unpaid + unproven pending-payment expiry, rejected-payment compensation, stale no-proof payment cleanup and one-minute pg_cron worker; 27 pgTAP assertions; exact-head free quality, KDS and disposable migration replay PASS |
| #124 | staging | Yes | No | Free k-anonymity breached-password guard for official Owner/staff password flows; stacked on #120; quality and disposable replay pass; direct Auth bypass remains a blocker |
| #123 | staging | Yes | Yes | Online checkout idempotency with stable key, fingerprint and atomic replay ledger; quality and disposable migration replay pass (74 pgTAP assertions); browser fault injection/concurrent runtime pending |
| #122 | staging | Yes | Yes | 24 FK covering indexes for 26 warnings; latest head adds safe removal of two zero-scan prefix duplicates; quality/replay in progress; 47 other zero-scan indexes retained pending workload evidence |
| #121 | staging | Yes | Yes | Current 189-feature matrix reconciliation and evidence-based progress scoring; documentation only |
| #120 | staging | Yes | Yes | Atomic permission-change audit; exact-head quality and disposable migration replay pass; independent review and staging runtime acceptance pending |
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
4. #108 is still open and Draft. Its updated 82/98/9 feature matrix is carried into #121 so the current matrix can be reviewed independently of the historical inventory PR.
5. #120 is still Draft and has no independent reviewer. Its green quality and disposable replay checks do not authorize shared-staging deployment.
6. No reviewer is currently requested on these 22 PRs in the metadata returned by GitHub; #122–#127 also have no requested reviewer in their creation metadata.

## Safety and next action

- Do not mass-merge PRs.
- Do not merge #115–#117 while `mergeable=false`.
- Do not self-approve. Independent review must come from a different authorized reviewer.
- Preserve staging mutation confirmation, deployment protection and both release flags as false.
- Reconcile dependency order, changed-file overlap and migration lineage before integrating one PR at a time.
- This inventory authorizes no database mutation, Auth change, Edge Function deployment or production release.
