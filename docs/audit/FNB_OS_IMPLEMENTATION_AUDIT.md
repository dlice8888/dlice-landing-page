# D’Lice FnB OS — Implementation Audit

**Snapshot:** 18 November 2026  
**Repository:** `dlice8888/dlice-landing-page`  
**Target:** `staging` only  
**Baseline staging SHA:** `c1498fd42d97e067eff4bd822fa3a9541c2636d9`  
**Decision:** **NO-GO** for tenant/public routing release. Both flags remain false.

## Evidence boundary

This audit combines the checked-in PRD feature register and traceability documents, current GitHub PR/branch metadata, read-only Supabase staging schema/migration/advisor queries, and Vercel Preview/project metadata. It does not infer runtime behavior from schema presence, static contracts, a green quality workflow, or a READY Preview.

No production branch, production Supabase project, production deployment, shared staging data, staging schema, Auth metadata, assignment, GitHub Environment secret/variable, or release flag was mutated.

## Current verified platform snapshot

| Area | Evidence | Result |
|---|---|---|
| GitHub staging | `staging` at `c1498fd42d97e067eff4bd822fa3a9541c2636d9` | Current target |
| Branch protection | Branch API reports `protected=false`; rulesets API returns `[]`; protection endpoint read returned 403 | **P0 BLOCKED**; protection was not changed |
| Supabase staging | `higoadrzxnhzbbwhdbmh`, ACTIVE_HEALTHY | Read-only inspection succeeded |
| Database | 64 public tables, 64 RLS-enabled, 0 without RLS, 64 policies, 29 public functions, 5 SECURITY DEFINER | Configuration inventory only; policy correctness still needs adversarial tests |
| Migration parity | 46 applied migration rows vs 45 source migration files | One source mismatch: `20261022140302` |
| Vercel | Project `dlice-landing-page`; SSO protection enabled for all deployments except custom domains; PR previews READY | Preview is not staging runtime acceptance |
| Security Advisor | Leaked-password protection disabled | WARN |
| Performance Advisor | 26 unindexed foreign keys; 49 unused-index suggestions | Remediation must be query-plan/workload based; no bulk index deletion |

## 18-domain implementation status

The historical feature-register estimates are shown for traceability only; they are not current completion percentages. No domain is certified COMPLETE. Every domain remains PARTIAL or NOT VERIFIED until all required UI/API/database/authorization/runtime/operational criteria have evidence.

| # | Domain | Historical estimate | Current status | Primary missing acceptance |
|---:|---|---:|---|---|
| 1 | Executive Command Center | 20% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 2 | POS & Checkout | 45% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 3 | Order Management | 55% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 4 | Kitchen & Production | 35% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 5 | Menu, Recipe & Product Engineering | 45% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 6 | Inventory & Warehouse | 55% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 7 | Procurement & Supplier | 40% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 8 | Branch Operations | 50% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 9 | Delivery & Fulfillment | 20% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 10 | CRM, Loyalty & Marketing | 10% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 11 | Finance & Accounting | 35% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 12 | HR & Workforce | 15% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 13 | Franchise & Expansion | 5% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 14 | BI & Analytics | 20% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 15 | Admin, Identity & Access Control | 55% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 16 | SaaS Tenant Management | 5% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 17 | Integrations & Automation | 20% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |
| 18 | Quality, Compliance & Security | 35% | PARTIAL | Complete row-level acceptance, live positive/negative tests and source-to-ledger reconciliation |

Detailed feature-level requirements, historical evidence notes, and source line references are in `FNB_OS_IMPLEMENTATION_MATRIX.json`.

## P0 tenant identity and authorization

- Staging has 2 tenants, 155 branches, 3 active tenant memberships, and 4 active Auth users.
- Two worker memberships are distinct users in distinct tenants; both have role `branch_manager` and the same permission set: orders, branches, inventory, pos, procurement, reports.
- Worker A has 2 active branch assignments in its own tenant; Worker B has 1. There are 0 cross-tenant assignment rows. Multiple same-tenant assignments satisfy the stated acceptance requirement. PR #87 removes the previous over-strict exact-one-visible-branch assertion and instead requires the configured branch to be present and the other tenant's branch to remain invisible.
- Each designated QA branch has 2 inventory balance rows, but no authenticated request has proved that either worker can read those rows.
- The active Owner profile is linked to an Auth user. Its `app_metadata.platform_owner` claim is absent; count of Auth users with boolean `true` is 0. The UUID allowlist cannot be queried through the available integration.
- The Edge Function explicitly requires both the platform-owner UUID allowlist and boolean Auth app metadata; see `supabase/functions/dlice-orders/index.ts:52-55,92-100`.
- The tenant runtime workflow is `.github/workflows/staging-tenant-isolation-acceptance.yml`; its runner is `tests/runtime/dlice-tenant-jwt-isolation.mjs`. P01–P09 remain NOT RUN; no probe is to be relabeled PASS or SKIPPED.

## PR #83 execution

PR #83 remains Draft/HOLD, targets staging, and has not been merged. The branch fixes the `branchB` temporal-dead-zone path, sources the publishable key from the staging Environment secret, and now rejects blank/whitespace key, username, password, and malformed/missing Tenant B branch UUID before network access. Login failure logging is sanitized to a constant error code. A table-driven no-network regression test covers eight missing/invalid input variants.

Latest exact-head Free quality workflow run: [44303062590](https://github.com/dlice8888/dlice-landing-page/actions/runs/44303062590) — SUCCESS. This is static/quality CI, not P01–P09. Vercel Preview is READY. P01–P09 remain BLOCKED because protected staging inputs cannot be independently verified, the current P01–P09 contract expects sales_admin global profile role and branch_manager tenant role; both existing fixtures satisfy the DB-side role prerequisites, and deployed Edge Function v69 still denies the own-branch inventory action.

## Additional P0 inventory authorization finding

The deployed staging `dlice-orders` is version 69 (`verify_jwt=false`; custom token validation remains inside the handler). Its early tenant denylist included `erp-list-inventory`, so non-Owner users were rejected with HTTP 423 before the branch-level authorization handler. This made positive own-branch probes P04/P06 impossible. The old handler also selected the global `inventory_items` catalog, not only the items associated with the requested branch.

A separate Draft PR [#85](https://github.com/dlice8888/dlice-landing-page/pull/85) now removes only the list action from the global denylist, requires the `inventory` permission and a non-empty branch, checks active tenant membership plus an active assignment to the exact branch before any data query, and returns items only through the requested branch's `branch_inventory` FK relation. Global `erp-save-inventory` remains gated. Exact-head quality CI [44304941471](https://github.com/dlice8888/dlice-landing-page/actions/runs/44304941471) passed; this candidate is not deployed to staging and P04/P06 remain NOT RUN.

## Required next sequence

1. Merge the reviewed P03 probe correction in PR #87; no branch assignment change is required because the extra assignment is within Tenant A and there are no cross-tenant assignment rows.
2. Verify all 14 protected staging workflow inputs by name/availability only, without reading or printing values.
3. Verify two real worker logins, tenant membership, exact branch assignment, and non-Owner/non-Admin role; then run P01–P09 on trusted staging.
4. Complete Owner Auth Admin metadata and UUID allowlist verification using the official authorized route; do not bootstrap by bypass.
5. Reconcile the missing migration source file and all PR migration overlaps before any schema change.
6. Finish operational positive E2E and the complete automated adversarial security regression.
7. Use exact-head CI and disposable migration replay as the engineering gate; run staging acceptance through the trusted staging CI workflow. Do not add independent-review or commit-signature prerequisites.

## Status definitions

- **COMPLETE:** every relevant acceptance criterion is implemented and evidenced, including runtime and reconciliation.
- **PARTIAL:** implementation exists but acceptance or end-to-end behavior remains incomplete.
- **GAP:** requirement has no implementation found after source inspection.
- **BLOCKED:** an external dependency or permission prevents execution.
- **NOT VERIFIED:** evidence is insufficient to determine behavior safely.

## Release decision

**NO-GO.** Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`. Keep PR #64 Draft/HOLD. Do not apply its migration, merge it, promote staging to main, or deploy production.

## Additional identity and inventory findings — 18 November 2026

A fresh read-only staging query confirms the two active non-owner memberships are in separate tenants, both have tenant role `branch_manager`, identical permission sets (`orders, branches, inventory, pos, procurement, reports`), active Auth users and active profiles. However, both corresponding `admin_profiles.role` values are `sales_admin`. The live check constraint `admin_profiles_role_check` permits only `sales_admin` and `owner`; therefore staging cannot currently represent an ordinary non-admin worker profile. Do not mark P03 compliant. Worker A has 2 active same-tenant assignments and Worker B has 1; there are 0 cross-tenant assignment rows.

PR [#86](https://github.com/dlice8888/dlice-landing-page/pull/86) adds a source-only `branch_worker` identity classification, Owner-only role conversion guarded by active membership and branch assignment, and Owner UI. It is not merged, its migration is not applied, and no staging profile was changed. Its exact-head quality CI 44306779658 passed 4/4 role contract tests; disposable migration replay 44306779612 passed. Vercel Preview is READY. PR #87's P03 correction passed quality CI 44307838730 (7/7 tenant runtime contract tests), but P01–P09 have not run against staging.

The deployed staging Edge Function remains v69. PR #85's scoped inventory handler is not deployed; the current deployed guard still denies `erp-list-inventory` for non-Owner users (HTTP 423). P04/P06 remain blocked until reviewed code is on staging and the trusted runtime workflow runs.

## Staging CORS runtime verification

Workflow run [44307838539](https://github.com/dlice8888/dlice-landing-page/actions/runs/44307838539) executed three real OPTIONS requests against staging `dlice-orders`: registered origin returned HTTP 200 with exact ACAO, foreign origin returned HTTP 403 with no ACAO, and no-Origin request returned HTTP 200 with no fallback ACAO. All three runtime CORS probes passed. This does not execute or replace P01–P09.

## Production deployment exception and restoration

A documentation-only matrix write was accidentally sent to the repository default branch because one GitHub file-update call omitted its explicit branch argument. Vercel created production-target deployments `dpl_FV4dAmvTdERXQupSkcvqvReXqqXP` (commit `eddc1cf31f8e64e7afa23011a31cea4f2c45c9f1`) and, after immediate file deletion from `main`, `dpl_4Fvtp6RvMwukCWFndERhgNh4Zv3e` (commit `ab47e1ba5c5201e8ad2553c8552fcfd3dcac33a4`). The custom domain alias `dlice.vercel.app` currently points to the latter restoration deployment. Critically, the restored `main` tree SHA `427d9413b4e6fe070ba76a93baab533ccb528570` exactly matches the pre-incident parent tree `8d74dbda81eb483a26d779b782fd4b37e12af770`; the accidental matrix file is absent from `main`. No application code, database, Auth metadata or production data was changed, but production deployments did occur and are recorded as an exception.

A fresh read-only `pg_indexes` query confirmed all nine recovered indexes currently exist in staging with the expected table/column definitions. This validates the applied index objects independently of the migration-history row; source parity remains open until PR #88 is merged and disposable replay passes.

## PR #83 exact-head verification — 2026-11-18

- PR #83 head: `b3121406d00fa395ff5073e4b67997f05d81ad0f`; draft, open, mergeable; Vercel Preview `dpl_EANn7yD2SrmKRodsqYZppJajqZAw` READY.
- Free quality run [44303062590](https://github.com/dlice8888/dlice-landing-page/actions/runs/44303062590) SUCCESS. The workflow includes staging secret workflow, tenant-isolation runtime evidence and public-routing gate checks. The log contains passing test groups of 5/5, 4/4, 11/11, 5/5 and 1/1.
- `branchB` is declared before the fail-closed preflight in `tests/staging/tenant-isolation-existing-identity.mjs`, eliminating the previously observed temporal-dead-zone path.
- Added subprocess regression cases for empty public key, Tenant A username, Tenant A password, Tenant B branch ID, whitespace-only public key/username/password and malformed branch UUID. Each expects exit code 2, BLOCKED, no stdout/network output, no credential/token disclosure and no ReferenceError.
- The workflow now references `secrets.STAGING_SUPABASE_PUBLIC_KEY` rather than a literal public key. The GitHub Environment secret availability cannot be queried through the connected integration; PR #83's quality run is not a tenant-isolation runtime proof.
- **P01–P09 remain BLOCKED / NOT RUN**; no claim of tenant isolation PASS is made.


## Continuation evidence update — 2026-11-20

The current staging implementation has advanced since the 18 Nov snapshot, but the overall release posture remains NO-GO.

- Migration source/history parity is now 52 source files versus 48 live applied versions, with zero applied versions missing from source and four pending source migrations. The exact staging-head clean replay passed 52 migrations and 67 pgTAP assertions.
- The Owner Command Center is a source-level foundation with a service-role-only summary RPC, an Owner-gated Edge action, date/branch filters and branch summary KPIs. It is not a complete consolidated finance/region dashboard: region rollups and margin/COGS reconciliation are not yet evidenced.
- Branch checklist mutations now use an atomic database RPC with same-transaction audit writes, optimistic version checks and 27 pgTAP assertions in the disposable migration replay. The migration remains pending on live staging.
- The broad public RPC ACL hardening migration passes disposable catalog-privilege tests. It remains pending on live staging; live function privileges have not yet been changed by that migration.
- Latest P01–P09 remains BLOCKED before authentication: all nine probes have executed:false, 0 skipped. Positive KDS/POS/Stock E2E and Owner bootstrap also stop at credential preflight.
- Supabase Advisor reports 26 unindexed foreign keys, 49 unused-index suggestions, and leaked-password protection disabled. These are follow-up performance/security work items, not proof that the database is unhealthy; no Advisor-driven DDL was applied.

The implementation matrix should continue to mark runtime-dependent requirements PARTIAL/BLOCKED until authenticated tenant tests, transaction-level E2E reconciliation, backup/restore, and 150-branch load evidence exist. Keep both release flags false.


## Superseding implementation audit — 21 November 2026, 19:42 WIB

### Current platform facts

| Area | Current evidence | Result |
|---|---|---|
| GitHub staging | `78f929dac2b05f436aaa7f50005310166f8a4779` | Target branch head verified |
| Supabase staging | `higoadrzxnhzbbwhdbmh`, ACTIVE_HEALTHY, PostgreSQL 17.11 | Read-only checks succeeded |
| Migration history/source | 49 applied / 52 source files; 3 source-only; 0 applied versions missing from source | No migration applied |
| Auth fixtures | Existing Owner + Tenant A + Tenant B + inactive QA identity | A/B mapping and membership/branch assignments verified; no Auth mutation |
| GitHub release protection | Ruleset #27559290, 0 required approvals, 0 checks, 0 deployments, 11 always-bypass actors | P0 BLOCKED |
| Vercel | Latest deployment READY; SSO protection enabled | Preview only; PR #127 hit daily deployment limit; no production change |

### Feature inventory (189 total)

| Domain | Features | PARTIAL | NOT VERIFIED | BLOCKED |
|---|---:|---:|---:|---:|
| Executive Command Center | 10 | 4 | 5 | 1 |
| POS & Checkout | 13 | 7 | 5 | 1 |
| Order Management | 10 | 7 | 2 | 1 |
| Kitchen & Production | 10 | 7 | 2 | 1 |
| Menu, Recipe & Product Engineering | 11 | 7 | 3 | 1 |
| Inventory & Warehouse | 12 | 10 | 2 | 0 |
| Procurement & Supplier | 10 | 5 | 5 | 0 |
| Branch Operations | 10 | 4 | 5 | 1 |
| Delivery & Fulfillment | 8 | 2 | 6 | 0 |
| CRM, Loyalty & Marketing | 9 | 1 | 8 | 0 |
| Finance & Accounting | 12 | 7 | 4 | 1 |
| HR & Workforce | 9 | 1 | 8 | 0 |
| Franchise & Expansion | 8 | 2 | 6 | 0 |
| BI & Analytics | 10 | 3 | 7 | 0 |
| Admin, Identity & Access Control | 10 | 5 | 4 | 1 |
| SaaS Tenant Management | 8 | 2 | 6 | 0 |
| Integrations & Automation | 9 | 5 | 4 | 0 |
| Quality, Compliance & Security | 20 | 10 | 9 | 1 |
| **TOTAL** | **189** | **89** | **91** | **9** |

No feature is DONE. Two PARTIAL SaaS features have current weighted scores (38% and 30%); the other 90 PARTIAL features remain unscored until evidence decomposition. Do not turn successful CI into a runtime completion claim.

### Latest PR and runtime disposition

| PR | Current head | State | Exact-head CI / disposable replay | Runtime / review disposition |
|---:|---|---|---|---|
| #126 | `07d7c51c2cbea21b9cd49a480614e004fe7bf417` | OPEN / DRAFT | Six workflows PASS; RLS/onboarding/invitation pgTAP plans 35/17/15 | P01–P09 NOT RUN; service-role secret presence and staging Environment protection unverified |
| #120 | `471f4a330a4da0cb13afe60ddeeb520e28dc0e88` | OPEN / DRAFT | Six of six exact-head workflows PASS; 35 profile-mutation, 11 permission and 11 invitation pgTAP assertions | Staging mutation-path runtime NOT RUN; password reset intent/outcome implemented |
| #124 | `a74200d60d6af06df5a5da4ed87a464283f0f9ff` | CLOSED / SUPERSEDED | Password guard source/tests/migration consolidated into #120 with identical shared blob SHAs | Do not reopen or merge separately |
| #123 | `31976673a9289add4c1bb10d6f29f3ff6c3c15a5` | OPEN / DRAFT | Quality, idempotency contract, CORS, KDS, procurement contracts and disposable replay PASS | Browser retry/drop-response, concurrent duplicate and payment/webhook E2E NOT RUN |

| #127 | `5c597c2ec37a130501ed19591cfc9383396ba1b6` | OPEN / DRAFT | Six workflows PASS; proof/supersession pgTAP plans 16/14 | Browser proof concurrency, Storage orphan sweep and payment reconciliation NOT RUN; no exact-head Vercel deployment |

Four canonical execution PRs (#120, #123, #126, #127) remain Draft/open/unmerged; #124 is closed as superseded by #120 and #125 is closed as superseded by #127. P01–P09, order/payment E2E and cross-domain transaction reconciliation remain NOT RUN. No feature is DONE. Both release flags remain false.


## Latest implementation delta — 21 November 2026

- Three blocked features moved to PARTIAL after implementation and exact-head tests: duplicate/delayed order handling (#123/#125/#127), permission/profile/password mutation audit (#120), and application-layer leaked-password mitigation (#120). They are not DONE because runtime and external Auth gaps remain.
- PR #120 exact head 471f4a330a4da0cb13afe60ddeeb520e28dc0e88 passes all six workflows, including full disposable migration replay. The profile mutation pgTAP suite has 35 assertions; audit failure injection proves rollback for staff creation, role and active-state mutation. Password reset now writes a durable intent before Auth Admin mutation and records the outcome; a failed finalization leaves a pending event for reconciliation.
- PR #124 is CLOSED as superseded by #120.
- Current distribution: 92 PARTIAL, 91 NOT VERIFIED, 6 BLOCKED, 0 DONE. Two SaaS partial scores remain 30% and 38%; 90 other PARTIAL features are unscored pending evidence decomposition.
- PR #123 uses migration version 20261121135000 and #126 uses 20261121130000; no version collision exists. PR #125 is closed as superseded by #127, which retains the canonical identical expiry migration blob. No shared staging migration was applied.


## Current execution and evidence correction — 21 November 2026

The current feature-level source of truth is **92 PARTIAL, 91 NOT VERIFIED, 6 BLOCKED, 0 DONE**. The three additional PARTIAL classifications are duplicate/delayed/failed order handling (PR #123), audited permission changes (PR #120), and application-layer leaked-password mitigation (consolidated from #124 into #120). These are not completed features.

### Canonical PR status and test evidence

| PR | Exact head | State | Automated evidence | Runtime evidence |
|---|---|---|---|---|
| #120 | 471f4a330a4da0cb13afe60ddeeb520e28dc0e88 | OPEN / DRAFT | Quality, disposable replay, KDS, CORS and procurement contracts PASS; 7 pgTAP files / 124 assertions | Staging permission/profile/password mutation E2E NOT RUN |
| #123 | 6788c4d7da34144d279da06edea84f6d0763b796 | OPEN / DRAFT | Quality, disposable replay, KDS, CORS and procurement contracts PASS | Response-drop retry, concurrent duplicate, pending/late payment and reservation E2E NOT RUN |
| #126 | bb008c55a4d98afe5264b4ccde4f28f129bc162 | OPEN / DRAFT | Quality, disposable replay, KDS, CORS and procurement contracts PASS; 7 pgTAP files / 134 assertions including 35 RLS, 17 onboarding and 15 invitation | P01–P09 NOT RUN |
| #127 | 5c597c2ec37a130501ed19591cfc9383396ba1b6 | OPEN / DRAFT | Quality, disposable replay, KDS, CORS and procurement contracts PASS | Payment-proof retry, expiry, compensation, supersession and Storage orphan recovery E2E NOT RUN |

PR #124 is CLOSED as superseded by #120. PR #125 is CLOSED as superseded by #127. The #123/#126 migration-version collision previously reported was a transcription error: #123 is 20261121135000 and #126 is 20261121130000. The #120/#126 invitation RPC overlap remains a code-level integration gap and must be consolidated into one canonical create/accept contract before merging.

### Tenant A/B identity and P01–P09

Read-only Supabase inspection confirms two existing Auth users, two distinct active tenant memberships, active sales_admin profiles, branch_manager tenant roles and correct tenant-scoped QA branch assignments. Tenant A uses QA-DLICE-A; Tenant B uses QA-TENANT-B. No password, Auth metadata, membership or branch assignment was changed. PR #126's passwordless workflow uses Auth Admin generate_link/verify for these existing accounts and revokes temporary sessions after probes. A test-evidence defect that mislabeled blocked preflight probes as executed was fixed in the PR #126 test script and contract suite; exact-head quality checks pass.

P01–P09 remain NOT RUN. The workflow is manual-dispatch-only on trusted staging. The connected GitHub integration does not expose workflow dispatch or Environment settings. Presence of STAGING_SUPABASE_SERVICE_ROLE_KEY is NOT VERIFIED; the secret value was not read or exposed. The latest PR #126 Vercel Preview is READY only on stale SHA 1bd648704172fecb2885b62fb3c51b7720da469c; current head bb008c55 has no matching Preview.

### Migration and release boundary

Supabase staging remains at 49 applied migrations versus 52 source files, with exactly three source-only candidates (20261120100000, 20261120110000, 20261120120000), zero DB-only versions and no duplicate version in the staging source tree. No migration or Edge Function was applied to shared staging or production. Both release flags remain false.

The active GitHub ruleset #27559290 has zero required approving reviews, zero required status checks and zero required deployment environments, while CODEOWNERS and last-push approval controls remain enabled. The project acceptance policy does not require a separate independent PR review; the connected integration has no ruleset-write action to change repository-level settings. Staging Environment protection remains NOT VERIFIED. Vercel Preview SSO is enabled, but Preview readiness is not runtime acceptance.

### Superseding CI-only gate update — 22 November 2026

The current repository rulesets API returns zero rulesets. PR #120 has no requested reviews; exact-head checks on `4c12e4b2371ba11525a4e2c0c8bd5177259a2f6f` pass. Signature verification is informational, not a release gate. The `staging` Environment exists with no protection rules or deployment-branch policy. Classic branch-protection settings and Environment secret names return HTTP 403 to the connected integration, so their state is not inferred. Staging run `45017642887` produced P01/P02 PASS, P03 FAIL (HTTP 503 membership lookups), P04–P09 BLOCKED, and six supplemental BLOCKED probes. No migration, Edge Function deployment, account/password change or production mutation occurred.


## Live continuation — 23 November 2026

### P0 tenant-isolation acceptance

The latest shared-staging run is [45017642887](https://github.com/dlice8888/dlice-landing-page/actions/runs/45017642887), against staging commit `5f6fa00c7335247684f7d88410a0c506de49a5a9`.

| Probe | Result |
|---|---|
| P01 | PASS |
| P02 | PASS |
| P03 | FAIL — membership HTTP 503 for Tenant A and Tenant B |
| P04–P09 | BLOCKED |
| SKIPPED | 0 |

The root cause was isolated by comparing the deployed staging source with PR #126. Staging's `erp-list-tenant-memberships` query embeds `admin_profiles` from `tenant_memberships`, but no corresponding foreign-key relationship exists. PostgREST therefore returns a relationship/schema-cache error and the handler responds HTTP 503.

PR #126 contains the safer correction: query active `tenant_memberships` independently, query `admin_profiles` by the authenticated actor's `user_id`, and join the response in application code. Membership remains the authorization source. Preserve this implementation when reconciling PR #126; do not invent a foreign key.

### Integration constraints

- PR #120 is already merged to staging. PR #124 is closed and superseded by #120.
- PR #126 remains draft and based on stale staging SHA `78f929dac2b05f436aaa7f50005310166f8a4779`; it must be reconciled against current staging SHA `5f6fa00c7335247684f7d88410a0c506de49a5a9`.
- PR #126's invitation migration differs from the staging/#120 candidate. Do not replace the canonical migration with the stale candidate without blob comparison and exact-head replay.
- The existing staging P01–P09 workflow completed P01/P02 but failed P03; the passwordless PR #126 workflow and protected Environment prerequisite are not yet accepted as a replacement.
- Active Edge Function is version 70 with `verify_jwt=false` and custom handler authentication. SDK `2.57.4` compatibility with new `sb_secret_` API keys remains a separate release blocker.
- Supabase staging remains at 49 applied migrations; 52 source files were last inventoried, with three source-only migrations. No migration or Edge Function deployment was performed.

### Current evidence and release posture

The 189-feature matrix remains 92 PARTIAL, 91 NOT VERIFIED, 6 BLOCKED, 0 DONE. Two PARTIAL features have defensible weighted scores (38% and 30%); 90 PARTIAL features remain unscored until their six weighted evidence dimensions are decomposed. Do not invent percentages.

Supabase read-only recheck: 64/64 public tables have RLS, 64 policies, 29 public functions, and no anon/authenticated EXECUTE grants on those public functions. Security Advisor reports one leaked-password warning; Performance Advisor reports 26 unindexed foreign keys and 49 unused-index suggestions; Health Advisor has no findings.

Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`. No staging migration, Edge Function deployment, Auth mutation, Vercel setting change, production change, or merge was performed during this audit update.


## Feature-status reclassification — 23 November 2026

A row-by-row review found three NOT VERIFIED requirements with concrete implementation/test evidence already available. They are now correctly classified as PARTIAL, not DONE:

| Domain | Feature | Evidence | Remaining acceptance gap |
|---|---|---|---|
| Admin, Identity & Access Control | Owner/manager/no-permission/inactive identity probes | Existing negative/role suite: 21 PASS / 0 FAIL | Positive business E2E and full live role/inactive-user matrix |
| Admin, Identity & Access Control | Cross-tenant isolation | PR #126: 35 pgTAP RLS assertions across 17 sensitive tables and tenant-scoped Edge Function checks | Live Tenant A/B P03-P09 acceptance; current P03 fails and P04-P09 are blocked |
| Quality, Compliance & Security | Exact-origin CORS | Run [44307838539](https://github.com/dlice8888/dlice-landing-page/actions/runs/44307838539): registered origin 200/exact ACAO, foreign origin 403/no ACAO, no-Origin 200/no ACAO | POST/authenticated action coverage and full endpoint regression |

Updated feature distribution:

| Status | Count |
|---|---:|
| PARTIAL | 95 |
| NOT VERIFIED | 88 |
| BLOCKED | 6 |
| DONE | 0 |
| **TOTAL** | **189** |

Domain table changes:
- Admin, Identity & Access Control: 8 PARTIAL / 2 NOT VERIFIED / 0 BLOCKED (80% partial coverage).
- Quality, Compliance & Security: 12 PARTIAL / 8 NOT VERIFIED / 0 BLOCKED (60% partial coverage).

Only two PARTIAL features currently have weighted numeric scores (38% and 30%). The other 93 PARTIAL features remain unscored until their six evidence dimensions are decomposed. These reclassifications do not imply runtime acceptance or DONE.


## P0 implementation progress — 23 November 2026, 07:20 WIB

### PR #126 reconciled against current staging

A merge commit was created on the existing PR branch with parents:
- Previous PR head: `8fe807b08fa7a25d53d2dee2f7890f151baff544`
- Current staging head: `5f6fa00c7335247684f7d88410a0c506de49a5a9`

Reconciliation commit: `cbe593c5e9f8c19a859551e538e94b4b9f02a383`.

The resulting PR diff is limited to the P03 membership handler. The broken PostgREST embed `admin_profiles(...)` through `tenant_memberships` was replaced with:
1. Active membership query scoped to `actor.user.id`.
2. Separate `admin_profiles` lookup scoped to the same authenticated actor.
3. Fail-closed handling for membership/profile errors and inactive profiles.
4. Response composition preserving the existing `admin_profiles` response shape.

No tenant authorization decision is derived from global profile permissions.

The stale source-contract assertion that required the invalid embed was corrected in commit `1b0b95211a881a67f9df690073efc15c081453da`. It now asserts separate membership/profile queries, actor self-scope, active membership filter, and absence of the invalid embed.

### Exact-head validation

- Latest quality checks: PASS on `1b0b95211a881a67f9df690073efc15c081453da`.
- Vercel Preview: READY on the same commit.
- CORS probes: PASS.
- Kitchen KDS offline contract: PASS.
- Procurement requisition and receiving contracts: PASS.
- Disposable migration replay: still IN_PROGRESS on `cbe593c5e9f8c19a859551e538e94b4b9f02a383`; do not treat as passed yet.

### Existing staging Environment and fixture validation

Run `45017642887` confirms P01 and P02 passwordless authentication for the two existing Supabase Auth identities. Preflight PASS was recorded for staging URL, public key, service-role key, both existing user IDs and both branch codes; secret values were not printed. No user was created or password changed.

Read-only Supabase SQL confirms:
- Two distinct active tenant memberships in two distinct tenants.
- Both identities have active `branch_manager` memberships and active `sales_admin` profiles.
- Both have six permissions and identical permission sets.
- Tenant A has two active branch assignments; Tenant B has one.
- `admin_profiles.user_id` has its own FK; no `tenant_memberships` → `admin_profiles` embed relationship is relied upon.

### Runtime gate remains open

The P01/P02 success and P03 failure in run `45017642887` are pre-fix runtime evidence. P03-P09 have NOT been re-run against the updated Edge Function. The staging Edge Function has NOT been deployed by this change. PR #126 remains draft/open pending disposable replay and independent review/integration approval. Do not merge, bypass review, or enable either release flag.

No production change, shared staging schema migration, Auth mutation, or release flag change occurred.


## Superseding feature status — 23 November 2026, 00:05 WIB

Use the machine-readable matrix and the superseding remediation-register section as the current count source: **95 PARTIAL, 88 NOT VERIFIED, 6 BLOCKED, 0 DONE (189 total / 18 domains)**. Earlier 92/91/6 distributions in this document are historical snapshots, not the latest totals. Only two PARTIAL features have evidence-backed progress scores (38% and 30%); 93 remain unscored pending six-dimension evidence decomposition. No feature is DONE until code, database, authorization, automated tests, live workflow E2E, and reconciliation all pass.
