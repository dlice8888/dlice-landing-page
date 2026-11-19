# Open PR Reconciliation — 18 November 2026

**Repository:** `dlice8888/dlice-landing-page`  
**Current open PR count:** 18  
**Scope:** Current GitHub search result, not the historical 14-PR inventory from 17 November.

No PR was merged or closed during this audit. No branch was deleted. Mergeability is not equivalent to approval or acceptance.

| PR | Scope | Base → head | Draft | Mergeable | Files / commits | Disposition |
|---:|---|---|---:|---:|---:|---|
| [#83](https://github.com/dlice8888/dlice-landing-page/pull/83) | Tenant probe fail-closed preflight | staging → fix/p0-tenant-isolation-preflight-20261118 | Yes | Yes | 4 / 3 | Keep Draft/HOLD; CI quality PASS; P01–P09 not run; preview READY |
| [#84](https://github.com/dlice8888/dlice-landing-page/pull/84) | Ten-file FnB OS audit documentation | staging → audit/fnb-os-continuation-20261118 | Yes | Yes | 10 / 11 | Keep Draft; quality run 44304082511 PASS; evidence-only documentation |
| [#85](https://github.com/dlice8888/dlice-landing-page/pull/85) | Branch-scoped inventory read authorization | staging → fix/tenant-scoped-inventory-read-20261118 | Yes | Yes | 3 / 7 | Keep Draft/HOLD; quality run 44304941471 PASS; P04/P06 require trusted staging runtime after reviewed staging merge |
| [#86](https://github.com/dlice8888/dlice-landing-page/pull/86) | Distinct ordinary branch-worker profile role | staging → fix/tenant-worker-profile-role-20261118 | Yes | Yes | 6 / 6 | Keep Draft/HOLD; quality CI 44306779658 PASS; disposable migration replay 44306779612 PASS; not applied to staging |
| [#87](https://github.com/dlice8888/dlice-landing-page/pull/87) | P03 worker identity/permission assertions and masked evidence | staging → test/tenant-p03-worker-identity-evidence-20261118 | Yes | Yes | 4 / 6 | Keep Draft/HOLD; exact-head quality CI 44307838730 PASS (7/7 runtime contract tests); Vercel Preview READY; no staging runtime execution |
| [#88](https://github.com/dlice8888/dlice-landing-page/pull/88) | Recover exact source for applied migration 20261022140302 | staging → fix/recover-migration-source-20261022140302-20261118 | Yes | Yes | 4 / 4 | Keep Draft/HOLD; quality 44309825502 PASS (1/1); disposable replay 44309825526 PASS (46 migrations); staging objects verified; source not yet merged |
| [#82](https://github.com/dlice8888/dlice-landing-page/pull/82) | Staging evidence whitespace normalization | staging → docs/reconcile-tenant-evidence-20261118 | Yes | No | 2 / 1 | Refresh/reconcile base and diff; preserve NO-GO flags |
| [#74](https://github.com/dlice8888/dlice-landing-page/pull/74) | Staging → main promotion | main → staging | Yes | No | 139 / 355 | NOT SAFE; broad promotion, stale release gates, conflicts and failed auth-negative history |
| [#71](https://github.com/dlice8888/dlice-landing-page/pull/71) | Canonical tenant fixture workflow | staging → fix/staging-tenant-fixtures-20261103 | Yes | No | 8 / 44 | HOLD; trusted credentials/fixture exactness not verified; auth-negative failed historically |
| [#78](https://github.com/dlice8888/dlice-landing-page/pull/78) | Atomic tenant bootstrap | staging → fix/atomic-tenant-bootstrap-staging-20261114 | Yes | Yes | 7 / 8 | HOLD; Owner/Auth Admin authorization and disposable DB rollback/replay need evidence |
| [#77](https://github.com/dlice8888/dlice-landing-page/pull/77) | Atomic branch checklist audit | staging → fix/branch-checklist-audit-atomicity-20261114 | Yes | No | 8 / 9 | HOLD; migration replay and runtime branch authorization not independently verified |
| [#76](https://github.com/dlice8888/dlice-landing-page/pull/76) | Executive Command Center summary | staging → feat/erp-command-center-foundation | Yes | No | 9 / 15 | HOLD; Owner-only RPC/UI and authenticated Owner browser acceptance missing |
| [#80](https://github.com/dlice8888/dlice-landing-page/pull/80) | Staging baseline evidence | staging → docs/staging-execution-baseline-20261117 | Yes | Yes | 6 / 14 | Superseded in part by this current read-only snapshot; reconcile stale values before merging |
| [#62](https://github.com/dlice8888/dlice-landing-page/pull/62) | Trigger-only RPC ACL | staging → security/revoke-trigger-rpc-execute-20261027 | Yes | No | 11 / 15 | Reconcile source migration and applied history; current staging already records version 20261027140145 |
| [#63](https://github.com/dlice8888/dlice-landing-page/pull/63) | Production CORS fail-closed source | main → security/production-cors-fail-closed-20261027 | Yes | Yes | 1 / 1 | Keep separate; production-targeted; no production action authorized |
| [#64](https://github.com/dlice8888/dlice-landing-page/pull/64) | Tenant isolation + same-tenant stock transfer migration | staging → audit/tenant-isolation-inventory-20261028 | Yes | No | 12 / 49 | STRICT HOLD; migration not applied; P01–P09 and security review incomplete |
| [#31](https://github.com/dlice8888/dlice-landing-page/pull/31) | Next workflow acceptance gate | staging → feat/staging-next-workflow-acceptance-20261023 | Yes | Yes | 2 / 2 | HOLD; historical role-negative test does not prove current operational positive E2E |
| [#22](https://github.com/dlice8888/dlice-landing-page/pull/22) | ERP order/fulfillment/production/finance API/UI | feat/staging-order-receipt-gates → feat/staging-erp-workflows-api | Yes | Yes | 17 / 41 | HOLD; overlaps migration ownership with #79 history and #21; no full E2E |

## Key reconciliation findings

- Current open PR count is 18 after opening documentation PR #84, scoped inventory-read PR #85, branch-worker identity PR #86, P03 evidence correction PR #87, and migration source recovery PR #88; PR #21 and #79 are not in the current open search result. Do not use the previous 14-PR inventory as current.
- All 17 PRs are Draft. No requested reviewers were returned in current PR metadata. A green check or `mergeable=true` is not an approval.
- PR #84 contains the ten requested audit artifacts; exact-head quality run 44304082511 passed. PR #85 fixes the scoped own-branch inventory read path; exact-head quality run 44304941471 passed. PR #86 adds a non-admin branch_worker profile classification and Owner-only conversion path; quality run 44306779658 passed and disposable migration replay 44306779612 passed. PR #87 corrects P03 worker/permission assertions and masks identifiers; quality run 44307838730 passed 7/7 contract tests. PR #88 restores the exact missing migration SQL from staging history; normalized source SQL matches the recorded applied statement, all nine indexes exist in staging, quality 44309825502 and disposable replay 44309825526 both passed. None of these PRs is merged.
- PR #83 latest head is `b3121406d00fa395ff5073e4b67997f05d81ad0f`. Exact-head quality run 44303062590 passed; Preview is READY. This does not satisfy staging tenant acceptance.
- PR #64 remains Draft/HOLD. Its migration `20261028120000_enforce_same_tenant_stock_transfers.sql` is not in staging migration history.
- PR #74 must not be merged as a bulk staging-to-main promotion.
- PR #62's migration is already represented in staging history as `20261027140145`; verify byte-for-byte source and history before deciding whether its PR is redundant.
- #76/#77/#78 are useful bounded slices but still require independent review and their respective runtime/disposable-database evidence.
- #82/#80 are documentation-only snapshots; stale evidence should be reconciled rather than duplicated.
- #22 has unresolved shared migration ownership and operational E2E gaps.

## Dependency order

1. #83 and #71 trusted fixture/preflight correctness.
2. #88 migration source recovery (no staging DDL); #86 branch_worker identity classification; #87 corrected P03 evidence; #85 scoped inventory read path; then trusted P01–P09 runtime proof.
3. #84 audit evidence and matrix reconciliation.
2. Owner Auth/RBAC and tenant identity verification.
3. #64 tenant isolation acceptance and migration review.
4. #78 tenant bootstrap disposable rollback tests.
5. #77 checklist atomicity migration replay/runtime authorization.
6. #76 Owner Command Center RPC authorization and browser acceptance.
7. #21/#22/#79 migration ownership and domain splitting; do not merge duplicates.
8. #31 operational acceptance after the actual business slices are integrated.
9. #63 production-targeted CORS only through a separately approved production review; no action in this task.
10. #74 remains NOT SAFE as a bulk promotion.

## Actions deliberately not taken

No PR was merged, closed, or converted from Draft. No migration was applied. No workflow was dispatched because the connected GitHub action surface available here does not expose a workflow-dispatch operation. No production resource was modified.

## Superseding integration snapshot — 2026-11-19

This section supersedes the 18 Nov PR counts, mergeability and migration-source findings above where they differ.

- Current open PR count at the 19 Nov inventory was 17. PR #96 has since been merged to main; 16 PRs remain open. The remaining open PRs are #95, #94, #93, #84, #82, #80, #78, #77, #76, #74, #71, #64, #63, #62, #31, #22; all remain Draft.
- main...staging is diverged: staging is 360 commits ahead, main is 19 commits ahead; PR #74 touches 145 files and is dirty. Do not use #74 as a bulk promotion.
- Already-merged staging work includes #92/#91/#90/#89/#88/#81/#75/#72/#70/#69/#68/#67/#66/#65/#61/#60/#59/#58/#56/#55/#54/#53/#52/#51/#50/#49/#48/#47/#46/#42/#40/#39/#37/#36/#35/#33/#32/#30/#28/#27/#26/#25/#24/#23/#20. Reconcile by ancestry/diff, not by recreating duplicate PRs.
- Overlap clusters: tenant identity/probes #64/#71/#95; stock RPC/trigger ACL #62/#94; ERP Edge Function/migration replay #76/#77/#78; release evidence #80/#82/#84. #63 is a separate main-targeted production CORS change; #96 was merged to main as a CI-only P01-P09 dispatch entrypoint (merge commit 2bb254bfb06baa8a3847b9112552f9413420b9f0), guarded to run only on staging. This exposes the manual trigger but does not prove runtime acceptance.
- Supabase staging has 47 applied migration rows and staging has 47 SQL files, but the sets differ: applied DB version 20261118165519 (20261118193000_revoke_public_stock_workflow_rpc_execute) is absent from staging source; exact SQL is in PR #94. Conversely, staging contains 20261118190000_add_branch_worker_profile_role.sql, which is not applied.
- Main contains only two migration source files (20261018000000 and 20261018001000); staging/database baseline begins 20261017183506 and 20261017183509. Do not bulk rename or replay staging history into production.
- Only Supabase projects exposed are dlice-staging (ACTIVE_HEALTHY) and dlice-production (INACTIVE). Production migration history cannot currently be queried.
- Staging security checks: 64/64 public tables have RLS; 64/64 have policies; five stock SECURITY DEFINER RPCs deny anon/authenticated and allow service_role. Security Advisor warns leaked-password protection is disabled; Performance Advisor reports 26 unindexed foreign keys.
- PR #95 corrects P03 to the observed model: global admin_profiles.role=sales_admin and tenant_memberships.role=branch_manager. Exact-head quality run 44541119025 passed static/contract checks, not P01-P09 runtime.
- Latest E2E reruns: KDS/POS/Stock run 44505286727 attempt 2 and Procurement run 44506173400 attempt 2 both stopped at preflight; Owner username/password and Branch A username resolved empty. No business transaction was created. P01-P09 run 44326099475 reported nine BLOCKED/not-executed probes.
- Owner Auth app_metadata.platform_owner remains absent. No connected Auth Admin mutation action is available; do not use direct SQL.
- Release flags remain false; no merge, migration apply, deployment or production mutation occurred in this snapshot.

## Current PR reconciliation — 2026-11-20

The latest repository query returned **four open PRs**:

| PR | Base | Disposition |
|---:|---|---|
| #104 | main | CORS contract/Deno check pass, but the 239-line Edge Function source is not verified as the exact production export and omits the 2,271-line staging tenant/ERP implementation. Draft/HOLD; do not deploy or treat as full FnB OS source. Main merge also triggers production deployment. |
| #84 | staging | Refreshed audit documentation candidate with current evidence. |
| #71 | staging | HOLD. Contains useful atomic warehouse/PO audit candidates, but also an out-of-order migration timestamp (20261108090000) that predates already-applied staging versions and a one-time Tenant B bootstrap path that is no longer the current fixture setup. Do not merge as-is. |
| #64 | staging | Security/tenant-isolation HOLD; do not merge or apply its migration until runtime acceptance and independent review pass. |

Closed/merged reconciliation:
- #96 merged to main (trusted P01–P09 dispatch workflow is present on default branch). Its merge triggered Vercel production deployment dpl_6wzdyEyDiyif7KRRWsdhDoRAUH6Q; main also reintroduced a documentation-only implementation matrix from the PR branch's older base snapshot. This deployment exception is recorded in FNB_OS_RELEASE_READINESS.md. No application source or database migration changed.
- #97 merged to staging (tenant P03 role model and E2E config corrections).
- #102 merged to staging (Owner bootstrap migration timestamp normalization).
- #103 merged to staging (Owner Command Center summary foundation).
- #95 closed as superseded by #97; its validated changes were carried forward there.
- #101 closed without merge because the recovered applied migration source was already present on staging.
- #74 closed without merge because it was a large, conflicting bulk promotion; no staging-to-main mass merge was performed.
- #80 closed as a stale 17 Nov evidence snapshot, superseded by the refreshed 20 Nov audit in this PR.
- #82 closed as formatting-only cleanup with no functional change.
- #76/#77 were superseded/closed; their reviewed feature slices are tracked separately rather than merging stale branch histories.

Do not equate a merged-to-staging PR with main integration or production deployment. Do not merge #104 or #64 while the release gates remain NO-GO.
