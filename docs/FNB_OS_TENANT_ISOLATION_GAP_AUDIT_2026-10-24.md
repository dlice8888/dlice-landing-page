# Tenant Isolation Gap Audit — 2026-10-24

**Repository:** `dlice8888/dlice-landing-page`  
**Branch:** `feat/staging-kds-offline-tenant-20261024`  
**Scope:** source-level review of `supabase/functions/dlice-orders/index.ts`; no production access or mutation.  
**Status:** audit findings only; this document is not evidence that tenant isolation passes.

## Summary

The new tenant membership and branch platform foundation is not yet sufficient to certify SaaS tenant isolation. Several newer branch actions call `branchAccess` or scope list queries through `branchIdsForActor`, but a number of legacy ERP/admin actions still operate on global catalogs or global finance/audit/staff data. The service-role Edge Function bypasses table RLS, so every action must enforce authorization and tenant/branch scope itself.

**Hard gate:** do not onboard a second live tenant and do not mark P5 complete until all action groups below are explicitly scoped and negative cross-tenant tests pass.

## Priority 0 — Tenant-boundary gaps

| Area / actions observed | Source-level risk | Required remediation |
|---|---|---|
| Legacy admin catalog: `admin-list-products`, `admin-save-product`, `admin-configure-product`, `admin-upload-product-photo` | Catalog operations do not visibly use tenant membership or tenant scope in the action handler. | Decide whether catalog is platform-global or tenant-owned. For tenant-owned catalogs, add tenant ownership to products/media/capacity and enforce scope in reads, writes, and storage object access. |
| Recipe and menu configuration: `erp-list-recipes`, `erp-save-recipe`, `erp-activate-recipe`, `erp-list-product-modifiers`, `erp-save-product-modifier`, `erp-list-recipe-substitutions`, `erp-save-recipe-substitution`, `erp-set-product-stock-tracking` | These actions operate on product/recipe identifiers without an obvious tenant membership check in the action block. | Resolve product → tenant, authorize the actor for that tenant, and reject cross-tenant product/recipe IDs on every read and write. Add composite tenant foreign keys where appropriate. |
| Finance: `erp-list-settlements`, `erp-create-settlement`, `erp-match-settlement`, `erp-list-fiscal-periods`, `erp-create-fiscal-period`, `erp-list-tax-settings`, `erp-save-tax-setting` | Several actions use Head Office permission checks but no visible tenant filter in their query/insert. Head Office permission alone is not a tenant boundary. | Add tenant ownership to settlement, fiscal-period and tax-setting records (or an explicitly approved platform-global model), then require active tenant membership and tenant-scoped queries for all actions. |
| Refund processing: `erp-process-refund` | The handler loads a refund by ID before its branch authorization check. It checks branch access only if the row has a branch ID; a null-branch record can avoid that check. | Fail closed on missing tenant/branch scope; load the tenant context first, then include tenant/branch scope in the update predicate as well as authorization checks. |
| Branch configuration: `erp-save-branch`, `erp-save-assignment`, `erp-list-assignments` | These are platform Owner-oriented operations; tenant-admin lifecycle and target-user tenant consistency are not demonstrated by a passing negative test. | Validate branch tenant, target user's active tenant membership, and role boundaries atomically before writing assignments. Separate platform Owner from tenant Owner explicitly. |
| Legacy order/admin surfaces: `admin-list-orders`, `admin-update-status`, `admin-verify-payment`, `admin-proof-url`, `admin-list-staff`, `admin-set-permissions`, `admin-set-active`, `admin-reset-staff-password` | These predate tenant membership and may use platform-wide identity or order scope. | Map each record to a tenant through its branch/order; require tenant membership and role-specific permission; prohibit tenant admins from managing users or orders in other tenants. |
| Reports and audit | New POS reports have branch scope, but a full audit/report action inventory and cross-tenant test evidence are still missing. | Enumerate every report, reconciliation, export, audit, and background action; require tenant scope at query construction and test identifier substitution. |
| Public catalog and checkout | Public catalog/order flows are intentionally unauthenticated, but tenant ownership and branch-to-product consistency must be enforced server-side. | Keep public discovery public only for published active data; validate every order line's product belongs to the selected branch's tenant and reject cross-tenant IDs. |

## Priority 1 — Branch-scoped actions to preserve

The current source includes tenant membership checks in `branchAccess`, and the following operational areas visibly call it or scope list queries through `branchIdsForActor`: KDS tickets/transitions, POS sale creation/reconciliation, sales/expenses, stock counts/transfers, shifts, purchase requisitions/orders/receipts, waste, handovers, warehouses, production batches and branch capacity. This is a source-level observation, **not** runtime proof; each write path still needs negative tests for a branch from another tenant.

Checklist actions call `checklistContext`, which itself checks `branchAccess`; preserve that guard.

## Required automated negative matrix

For each sensitive action and data class, test at least:

1. Tenant A member reads Tenant A record → allowed only with permission.
2. Tenant A member reads Tenant B record by substituting UUID → denied or returns no data.
3. Tenant A member updates/deletes Tenant B record by substituting UUID → denied and no state change.
4. Tenant A branch assignment cannot be used to access another branch in Tenant A unless explicitly authorized.
5. Tenant Owner/Admin cannot manage platform Owner accounts, another tenant's memberships, or platform-global settings.
6. Unauthenticated requests cannot reach service-role operations.
7. Missing, inactive, revoked, or ambiguous tenant membership fails closed.
8. Query, count, report, nested relation, export, and reconciliation paths obey the same tenant boundary as direct record reads.
9. Storage/media URLs and background/outbox jobs cannot cross tenant boundaries.
10. All denied writes leave no partial records and produce safe audit/security evidence.

## Acceptance gate

- [ ] Tenant ownership model decided for each catalog, finance, HR, audit, and report domain.
- [ ] Schema constraints prevent tenant/branch foreign-key mismatches.
- [ ] All Edge Function actions inventoried and classified as public, platform-only, tenant-scoped, or branch-scoped.
- [ ] Automated cross-tenant read/write tests pass against staging with separate Tenant A and Tenant B identities.
- [ ] POS → KDS → stock E2E passes and its artifact reports `PASS` with empty `cleanup_errors`.
- [ ] Runtime CORS, backup/restore drill, and load test gates pass separately.

Until these checks are evidenced, SaaS isolation remains **Partial / Not Accepted**.
