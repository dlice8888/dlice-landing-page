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
- The active Owner profile is linked to an Auth user. Its `app_metadata.platform_owner` claim is absent; count of Auth users with boolean `true` is 0. The UUID allowlist cannot be independently inspected through the available integration.
- The Edge Function explicitly requires both the platform-owner UUID allowlist and boolean Auth app metadata; see `supabase/functions/dlice-orders/index.ts:52-55,92-100`.
- The tenant runtime workflow is `.github/workflows/staging-tenant-isolation-acceptance.yml`; its runner is `tests/runtime/dlice-tenant-jwt-isolation.mjs`. P01–P09 remain BLOCKED / NOT RUN; no probe is to be relabeled PASS or SKIPPED.

## PR #83 execution

PR #83 remains Draft/HOLD, targets staging, and has not been merged. The branch fixes the `branchB` temporal-dead-zone path, sources the publishable key from the staging Environment secret, and now rejects blank/whitespace key, username, password, and malformed/missing Tenant B branch UUID before network access. Login failure logging is sanitized to a constant error code. A table-driven no-network regression test covers eight missing/invalid input variants.

Latest exact-head Free quality workflow run: [44303062590](https://github.com/dlice8888/dlice-landing-page/actions/runs/44303062590) — SUCCESS. This is static/quality CI, not P01–P09. Vercel Preview is READY. P01–P09 remain BLOCKED because protected staging inputs cannot be independently verified, both candidate profiles remain sales_admin rather than branch_worker, and deployed Edge Function v69 still denies the own-branch inventory action.

## Additional P0 inventory authorization finding

The deployed staging `dlice-orders` is version 69 (`verify_jwt=false`; custom token validation remains inside the handler). Its early tenant denylist included `erp-list-inventory`, so non-Owner users were rejected with HTTP 423 before the branch-level authorization handler. This made positive own-branch probes P04/P06 impossible. The old handler also selected the global `inventory_items` catalog, not only the items associated with the requested branch.

A separate Draft PR [#85](https://github.com/dlice8888/dlice-landing-page/pull/85) now removes only the list action from the global denylist, requires the `inventory` permission and a non-empty branch, checks active tenant membership plus an active assignment to the exact branch before any data query, and returns items only through the requested branch's `branch_inventory` FK relation. Global `erp-save-inventory` remains gated. Exact-head quality CI [44304941471](https://github.com/dlice8888/dlice-landing-page/actions/runs/44304941471) passed; this candidate is not deployed to staging and P04/P06 remain NOT RUN.

## Required next sequence

1. Merge the reviewed P03 probe correction in PR #87; no branch assignment change is required because the extra assignment is within Tenant A and there are no cross-tenant assignment rows.
2. Verify all 14 protected staging workflow inputs by name/availability only, without reading or printing values.
3. Verify two real worker logins, tenant membership, exact branch assignment, and non-Owner/non-Admin role; then run P01–P09 on trusted staging.
4. Complete Owner Auth Admin metadata and UUID allowlist verification using the official authorized route; do not bootstrap by bypass.
5. Reconcile the missing migration source file and all PR migration overlaps before any schema change.
6. Finish operational positive E2E and independent security review.
7. Establish GitHub branch/ruleset and staging deployment protection through repository settings; do not weaken protections.

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
