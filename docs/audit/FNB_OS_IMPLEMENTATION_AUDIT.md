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
| Vercel | Project `dlice-landing-page`; PR #83 Preview READY | Preview is not staging runtime acceptance |
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
- Worker A has 2 active branch assignments in its own tenant; Worker B has 1 active branch assignment in its own tenant. There are 0 cross-tenant assignment rows. The canonical P03 runner requires exactly one visible branch for each user, so Worker A currently fails that fixture assertion.
- Each designated QA branch has 2 inventory balance rows, but no authenticated request has proved that either worker can read those rows.
- The active Owner profile is linked to an Auth user. Its `app_metadata.platform_owner` claim is absent; count of Auth users with boolean `true` is 0. The UUID allowlist cannot be independently inspected through the available integration.
- The Edge Function explicitly requires both the platform-owner UUID allowlist and boolean Auth app metadata; see `supabase/functions/dlice-orders/index.ts:52-55,92-100`.
- The tenant runtime workflow is `.github/workflows/staging-tenant-isolation-acceptance.yml`; its runner is `tests/runtime/dlice-tenant-jwt-isolation.mjs`. P01–P09 remain BLOCKED / NOT RUN; no probe is to be relabeled PASS or SKIPPED.

## PR #83 execution

PR #83 remains Draft/HOLD, targets staging, and has not been merged. The branch fixes the `branchB` temporal-dead-zone path, sources the publishable key from the staging Environment secret, and now rejects blank/whitespace key, username, password, and malformed/missing Tenant B branch UUID before network access. Login failure logging is sanitized to a constant error code. A table-driven no-network regression test covers eight missing/invalid input variants.

Latest exact-head Free quality workflow run: [44303062590](https://github.com/dlice8888/dlice-landing-page/actions/runs/44303062590) — SUCCESS. This is static/quality CI, not P01–P09. Vercel Preview is READY. P01–P09 are still BLOCKED because the protected staging inputs cannot be independently verified and Worker A's branch fixture is not exact-one.

## Required next sequence

1. Resolve the extra active Worker A branch assignment through the authorized HR/branch-assignment admin path; do not directly mutate the database to satisfy a test.
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
