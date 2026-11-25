# D’Lice feature progress scoring standard — 21 November 2026

## Why percentages are not copied from the old estimates

A feature marked PARTIAL only means that some implementation evidence exists. It does not mean that the feature is 50%, 70%, or any other fixed percentage complete. Historical domain estimates in the original PRD register are not current acceptance scores.

## Weighted evidence model

| Acceptance dimension | Weight |
|---|---:|
| Code and UI implementation | 20% |
| Database integrity and migrations | 20% |
| Authorization and tenant/branch scope | 15% |
| Automated contract and unit tests | 15% |
| End-to-end browser or API workflow | 20% |
| Operational reconciliation and observability | 10% |
| **Total** | **100%** |

For each feature, each dimension is split into explicit pass/fail acceptance criteria. A dimension earns its weight only when a current evidence artifact (commit/PR, migration/test, CI run, runtime trace, screenshot, or reconciled database query) demonstrates that criterion. A BLOCKED or SKIPPED test earns zero for that criterion.

## Status transitions

- NOT VERIFIED → PARTIAL: a concrete implementation task/PR has started and evidence is linked; this is not acceptance.
- PARTIAL → DONE: 100% weighted score, every required workflow passes, code and database checks pass, no BLOCKED/SKIPPED, and all defined automated and runtime test gates pass and deployment authorization gates are satisfied.
- BLOCKED remains visible while an external prerequisite prevents execution. Track its work status separately (e.g. IN_PROGRESS or EXTERNAL_ACTION_REQUIRED).

## Current snapshot — live audit 21 November 2026

- 189 PRD features across 18 domains.
- **92 PARTIAL, 91 NOT VERIFIED, 6 BLOCKED.** The 18 domain rows supplied in the latest request originally sum to 82/98/9; the total-row value 93 NOT VERIFIED is incorrect. Two SaaS features began concrete implementation in PR #126, and five more features were reclassified after live schema/function evidence confirmed existing foundations. Current count is 92/91/6.
- Tenant/member isolation = **38%** (3 code/UI + 15 database + 5 authorization + 15 automated tests; 0 browser/API E2E; 0 operational reconciliation).
- Tenant directory/onboarding = **30%** (5 code/UI + 10 database + 5 authorization + 10 automated tests; 0 browser/API E2E; 0 operational reconciliation).
- The other **90 PARTIAL features are not yet assigned a defensible numeric score**. Their foundations are evidenced, but each must be decomposed into the six weighted dimensions above before percentages are published. Do not substitute a domain-level estimate or invent 0%/50%/100%.
- PR #126 exact-head disposable migration replay and quality suite pass; invitation lifecycle adds 15 pgTAP assertions. Real Tenant A/B runtime remains unproven.
- PR #120 exact head 471f4a330a4da0cb13afe60ddeeb520e28dc0e88 now passes exact-head quality and disposable replay. The profile-mutation suite declares 35 pgTAP assertions, permission suite 11 and invite suite 11. Password reset uses a durable audit intent/outcome saga.
- PR #124 application-layer breached-password guard passes CI, but native Supabase leaked-password protection remains disabled and direct Auth bypass remains unresolved.
- Two staging positive-path E2E workflows (Procurement and KDS/POS/Stock/Offline) are BLOCKED at credential preflight; missing Owner username/password and Branch A username prevented business steps from executing.

## Non-negotiable reporting rule

Never count a code artifact, schema/table, green build, preview deployment, negative-only authorization test, or an unexecuted/blocked/skipped workflow as feature completion. Every DONE claim must point to the passing evidence for all required dimensions.


## Current scoring evidence delta — 21 November 2026, 19:42 WIB

- Feature counts remain 189 total: 92 PARTIAL, 91 NOT VERIFIED, 6 BLOCKED, 0 DONE.
- Tenant/member isolation remains 38%; Tenant directory/onboarding remains 30%. The exact-head PR #126 disposable replay and invitation suite PASS, but live P01–P09 and invitation browser/API E2E have not run, so no additional E2E or reconciliation weight is earned.
- PR #120 permission mutation contract and disposable replay PASS, but live positive/negative mutation-path tests are absent. Password reset's Auth update and audit insert remain separate; do not mark permission/security features DONE.
- PR #123/#125/#127 exact-head contract and disposable replay PASS. Browser fault-injection, concurrent retry, expiry worker, Storage compensation, payment reconciliation and order/payment/reservation E2E are NOT RUN; no completion weight is earned for those dimensions.
- PR #124's five password-guard artifacts are identical to PR #120's and the guard is included in #120's Edge Function. Do not double-count #124 as separate implementation progress.
- No numeric score is added for the other 90 PARTIAL features; their criteria still need evidence decomposition. BLOCKED/SKIPPED/NOT RUN remain zero for the affected acceptance dimension.


## Test-only acceptance policy — effective 21 November 2026

Feature acceptance is based only on reproducible, machine-verifiable evidence:

1. **Build and static checks:** every required workflow for the exact head SHA completes successfully; lint, typecheck, formatting, security/static analysis and build have zero failures.
2. **Changed-code coverage:** line and branch coverage is at least 80% for changed production code and at least 90% for changed authorization, tenant-boundary, payment and mutation-critical code. Any uncovered security decision branch must have an explicit negative/positive test or remains NOT VERIFIED.
3. **Database:** replay all candidate migrations from an empty disposable database; every migration and pgTAP test passes; schema/RPC grants, RLS and indexes match expected state; zero migration-version collisions and zero applied/source drift in the candidate set.
4. **Authorization:** run positive and negative tests for each role and tenant. Every cross-tenant read/write attempt must be rejected; every permitted same-tenant action must succeed; audit mutation and business mutation must commit or roll back atomically.
5. **P01–P09:** execute all nine probes against the two existing Supabase Auth identities. Required result is 9/9 executed, 9/9 expected outcomes, 0 BLOCKED, 0 SKIPPED, 0 inconclusive. Capture status, actor, tenant, branch, request correlation ID and assertion result; never log secrets or magic-link tokens.
6. **Business E2E:** execute the exact scenario matrix for checkout retries/concurrency, pending and late payment, expiry, proof upload/retry, compensation, supersession, reservation lifecycle, KDS, recipe consumption, stock movement/transfer/opname and procurement PR→PO→GRN. Each scenario records setup, action, expected result, actual result and persisted DB evidence.
7. **Reconciliation:** verify order/payment/reservation, stock ledger/on-hand, recipe consumption, procurement/GRN/AP, shift/cash and finance totals. Invariants must match exactly; unexplained variance is a failure.
8. **Reliability and performance:** inject timeout, duplicate delivery, retry, concurrent requests and worker restart where applicable. Record p50/p95/p99, error rate and recovery behavior against the approved workload baseline; missing measurements remain NOT VERIFIED.
9. **Completion rule:** all applicable checks PASS on the exact candidate SHA; no BLOCKED/SKIPPED/NOT RUN acceptance cases; database and runtime state reconciles; evidence links and timestamps are stored. Only then may a feature become DONE/100%.

**Release controls remain mandatory:** protected staging Environment, secret handling, authorized workflow dispatch, backup/rollback and explicit staging/production mutation authorization remain mandatory. This policy does not disable those controls, weaken branch/deployment protection, or authorize automatic merge/deploy.


## Current scoring delta — 21 November 2026

Three previously BLOCKED features are now PARTIAL after concrete code and exact-head test evidence: order idempotency/payment lifecycle, staff permission/profile/password audit, and application-layer leaked-password mitigation. Current distribution is 92 PARTIAL, 91 NOT VERIFIED, 6 BLOCKED, 0 DONE. Two PARTIAL features are scored (30%, 38%); 90 remain unscored. No feature reaches DONE until its applicable runtime, authorization, E2E and reconciliation tests pass on the exact candidate SHA.


## Superseding staging evidence delta — 24 November 2026

The current feature-level matrix was recounted directly from all 189 requirement rows: **95 PARTIAL, 88 NOT VERIFIED, 6 BLOCKED, 0 DONE**. This supersedes earlier narrative snapshots in this document that stated 92/91/6. The domain table in the matrix is the authoritative source for the distribution.

- Staging head `02c32c31315725c7639f249978efc4b8d486cab5`; PR #129 integrated after exact-head CI passed.
- Tenant acceptance [run 45230589775](https://github.com/dlice8888/dlice-landing-page/actions/runs/45230589775): P01–P09 9/9 PASS; supplemental RLS/RPC 6/6 PASS; 230/230 auth action probes PASS; temporary session cleanup PASS. No FAIL/BLOCKED/SKIPPED/executed:false in this run.
- The 230 auth probes cover missing and invalid credentials for 115 admin/ERP actions; default expected status 401, bootstrap-owner 403. No response bodies or secret values were logged.
- This runtime evidence is for tenant isolation/authentication boundaries. It does not prove KDS/POS/Stock/Offline or Procurement/Receiving positive business E2E and does not complete the entire SaaS tenant-management domain.
- Two PARTIAL feature scores remain currently defensible: tenant/member isolation 38% and tenant directory/onboarding 30%. Re-score the isolation feature against the new runtime evidence only after the six weighted dimensions and each criterion are updated; do not award unverified Storage/cache/job or reconciliation weight.
- **93 PARTIAL features remain unscored** pending feature-level decomposition across the six dimensions. No score is inferred from domain-level percentages.
- Supabase staging remains ACTIVE_HEALTHY; 64/64 public tables have RLS; 49 migrations are applied (latest `20261119182606`); 3 staging source migrations remain unapplied. Security Advisor still reports leaked-password protection disabled; Performance Advisor reports 26 unindexed FKs and 49 unused indexes; Health Advisor has zero findings.
- Live `dlice-orders` is ACTIVE v71 with custom `getAdmin(req)` authorization; `verify_jwt=false` remains a separate platform setting. Both release flags remain false.
- Vercel staging Preview is READY on the exact staging commit. Preview readiness is not business acceptance or production release.

**Still required:** execute KDS/POS/Stock/Offline and Procurement/Receiving positive E2E with database reconciliation; finish remaining candidate PRs individually with exact-head CI and disposable migration replay; close source/database migration drift; implement and verify all remaining NOT VERIFIED vertical slices; and run full 18-domain regression, 150-branch load/concurrency, backup/restore and release gates.


## Latest current-head runtime acceptance — 24 November 2026

The staging acceptance workflow was extended by PR #132 so it reruns when the `dlice-orders` Edge Function, migrations, and positive E2E auth harness change. After PR #132 merged, the workflow ran on the latest staging SHA:

- Staging SHA: `666f2a432e236f15161cef8d2d9905279d0f5144`.
- Tenant acceptance: [run 45236931758](https://github.com/dlice8888/dlice-landing-page/actions/runs/45236931758), **P01–P09 9/9 PASS**.
- Admin/ERP auth probes: **230/230 PASS** across 115 actions; default expected HTTP 401, `admin-bootstrap-owner` expected HTTP 403; no response bodies or secret values logged.
- Supplemental direct RLS/RPC checks: **6/6 PASS**.
- Tenant A/B existing-account magic-link login, membership and branch fixtures: PASS.
- Cross-tenant read/write denial and zero write side effects: PASS.
- Both temporary Auth sessions revoked with HTTP 204.
- Same-head Free quality checks: [run 45236931620](https://github.com/dlice8888/dlice-landing-page/actions/runs/45236931620), PASS.
- Vercel Preview for the exact staging SHA: READY; no Production target.
- Supabase `dlice-orders`: ACTIVE v71; custom `getAdmin(req)` present; both release flags remain false.

This is a stronger current-head tenant-isolation/auth boundary result. It does not prove the positive KDS/POS/Stock/Offline or Procurement/Receiving business workflows. PR #130 makes those workflows passwordless with existing Auth identities and explicit manual staging mutation confirmation; they still require manual dispatch and persisted-data reconciliation.

The weighted score for tenant/member isolation is intentionally not changed automatically. Re-score the six dimensions only after mapping this new run to each criterion and accounting for any still-unverified storage/cache/job or broad 150-branch requirements. The matrix remains 95 PARTIAL / 88 NOT VERIFIED / 6 BLOCKED / 0 DONE; 93 PARTIAL features are still unscored. Do not infer a new percentage from a single acceptance workflow.


## Tenant isolation re-score — 24 November 2026

The prior 38% score is superseded by the latest live staging acceptance on commit `666f2a432e236f15161cef8d2d9905279d0f5144` (run [45236931758](https://github.com/dlice8888/dlice-landing-page/actions/runs/45236931758)). The updated weighted score is **58% provisional**:

| Dimension | Weight | Earned | Evidence / remaining gap |
|---|---:|---:|---|
| Code/UI | 20 | 3 | Server-side branch-scope foundation exists; full tenant-aware UI and all route coverage remain unverified |
| Database/integrity | 20 | 15 | 64/64 public tables have RLS; 35 pgTAP assertions across 17 sensitive tables; cross-tenant denied-write postconditions prove zero transfer/item/stock-movement rows; Storage/cache/job coverage remains |
| Authorization/scope | 15 | 10 | P01-P09 own-scope and cross-tenant read/write probes pass; supplemental RLS/RPC 6/6 and missing/invalid auth 230/230 pass; not all mutation routes/storage/jobs are covered |
| Automated tests | 15 | 15 | Exact-head quality, tenant policy tests and 230 auth action probes pass |
| Workflow E2E | 20 | 10 | P01-P09 live staging API acceptance 9/9 passes; this is not full browser workflow or positive commerce E2E |
| Reconciliation/observability | 10 | 5 | Denied-write DB postconditions and session cleanup pass; Storage/cache/job and 150-branch operational reconciliation remain |
| **Total** | **100** | **58** | **Provisional implementation progress, not release readiness** |

Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`. Remaining acceptance: complete API mutation-route matrix, Storage/cache/background-job isolation, tenant invitation lifecycle, multi-branch/150-branch concurrency, browser E2E and full reconciliation.


## Latest staging evidence — 24 November 2026, 07:25 WIB

- Current staging head: `abea9ffd4d7b198e88d0a19d906d912fa45bc35a`.
- Tenant isolation acceptance: [run 45296840751](https://github.com/dlice8888/dlice-landing-page/actions/runs/45296840751), P01–P09 9/9 PASS, 0 FAIL/BLOCKED/SKIPPED; supplemental RLS/RPC 6/6 PASS; 115 actions × missing/invalid credentials = 230/230 PASS; Tenant A/B temporary sessions revoked HTTP 204.
- Quality [run 45296840721](https://github.com/dlice8888/dlice-landing-page/actions/runs/45296840721) and KDS contract [run 45296840724](https://github.com/dlice8888/dlice-landing-page/actions/runs/45296840724) PASS. Vercel exact-head Preview READY (deployment `dpl_D9NVHeXQ9tBx1f37h6t6kMf6wcHV`).
- PR #136 merged 24 FK covering indexes for 26 constraints; exact-head disposable replay applied all 58 source migrations and passed 11 pgTAP files / 234 tests. Shared Supabase staging still has 49 applied versions and 9 source-only migrations; no shared DB migration was applied.
- Feature counts: 189 total, 95 PARTIAL, 88 NOT VERIFIED, 6 BLOCKED, 0 DONE. Two PARTIAL scores remain 58% and 30%; 93 PARTIAL features remain unscored. Domain partial-coverage ratios are published in the remediation register but are not weighted completion scores.
- Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.

## Superseding audit — 25 November 2026

Current row-level distribution: **189 total / 140 PARTIAL / 44 NOT VERIFIED / 5 BLOCKED / 0 DONE**. The 45 new PARTIAL classifications are implementation-start evidence linked to Draft PRs #145/#146; they do not mean deployed, database-replayed, E2E accepted, or complete. PR #145 and #146 remain OPEN Draft.

Current partial coverage = 140/189 = **74.1%**. This is a count of features with implementation started, not the weighted progress of PARTIAL features. Feature weighted percentages are awarded only when the six acceptance dimensions have evidence-backed criteria. Keep unscored partials explicitly unscored; do not substitute a generic percent. Existing defensible scores remain tenant/member isolation 58% provisional and tenant directory/onboarding 30% pending criterion-level rescore.

Live evidence snapshot 25-Nov: Supabase staging 63 applied migrations, 67/67 public tables with RLS, dlice-orders ACTIVE v73 with verify_jwt=false (custom auth guard required), Security Advisor 1 WARN (leaked-password protection disabled), Performance Advisor 83 INFO unused-index suggestions, Health Advisor 0. Vercel Hobby staging Preview READY at commit aed9353; PR #146 Preview READY at stale commit 4406c31, behind current PR head 23e4b6c; Production READY at cca72d3 and was only inspected read-only. PR #146 exact-head quality passed; disposable replay and provider/bank E2E remain open.

### Additional feature starts mapped from PR #145 — 25 November

HR schema and Edge command inventory now include employee listing, attendance events, timesheets, shift schedules, leave requests and branch-scoped payroll; these moved the corresponding five HR features into PARTIAL/IN_PROGRESS, with remaining employee lifecycle, overtime policy, training and recruitment still open. Franchise draft schema includes applications, site/due-diligence reviews, agreement versions, royalty statements and opening gates. CRM adds reward/voucher issuance/redemption/void contracts. Procurement adds supplier invoice and PO/receipt matching contracts. Finance adds AP evidence and payroll journal paths. Executive adds operational alert events. BI adds metric definitions, source watermarks and reconciliation runs. SaaS adds entitlement, usage, invoice and offboarding contracts. These are source implementation starts only; SQL replay, RLS/ACL and positive runtime workflows remain required.

Current weighted progress remains intentionally unscored for these newly-started feature slices until the six dimensions are decomposed and proven. Do not treat a Draft PR, schema draft or contract test as DB/runtime acceptance.
### POS lifecycle scoring delta — PR #143

Four NOT VERIFIED POS requirements (modifier flow, split tender, hold/resume, offline replay) and one BLOCKED digital receipt requirement now have concrete implementation in PR #143. The five are PARTIAL/IN_PROGRESS, not DONE. The digital receipt is immutable and retrievable, but physical printer/device acceptance remains open. POS now has 12 PARTIAL, 1 NOT VERIFIED (discount/coupon rule engine), 0 BLOCKED. Exact-head disposable replay passed 14 pgTAP files / 375 assertions; staging E2E remains BLOCKED before mutation because the existing Owner Auth app_metadata.platform_owner claim is missing/null. No QA sale was created.

Current total 139 PARTIAL / 45 NOT VERIFIED / 5 BLOCKED / 0 DONE. Of the 44 newly-started features, 43 moved from NOT VERIFIED and one (digital receipt) moved from BLOCKED. The 137 PARTIAL features without a defensible six-dimension numeric score remain explicitly unscored; do not invent percentages.
### Backup/restore rehearsal progress — PR #148

PR #148 starts one Quality/Compliance/Security feature with a local PostgreSQL 17 dump/restore rehearsal. It verifies committed pre-snapshot data parity, checksum, restored RLS, Tenant A/B isolation and an intentional post-snapshot record boundary using a free GitHub runner. Its workflow is pending; no numeric weighted score is awarded until exact-head CI completes and the criteria are mapped. This does not certify Supabase managed backup/PITR, Auth/Storage recovery or platform RPO/RTO.