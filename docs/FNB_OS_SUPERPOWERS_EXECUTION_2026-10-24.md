# Superpowers Execution — Kitchen, Offline POS, Branch Operations and SaaS Platform

**Branch:** `feat/staging-kds-offline-tenant-20261024`  
**Target:** staging only. Production, `main`, and production Supabase are explicitly out of scope.  
**Method:** Specify → Plan → Tests First → Implement → Verify → Review → Deploy Staging → Accept.

## Scope in this slice

### Implemented in source (not yet staging-accepted)
- KDS ticket schema and dispatch triggers for paid POS sales and paid, confirmed online orders.
- Branch-scoped KDS list/transition API and ERP queue UI.
- Modifier catalog with sale-time modifier snapshots and price adjustments in the idempotent POS RPC.
- Recipe substitution approvals with same-unit guard and quantity factor.
- Opt-in product recipe stock tracking; POS stock issue and paid/confirmed online-order stock issue occur atomically with the sale/order transition. Insufficient stock or missing active recipe rolls back the transaction.
- POS idempotency key, payload fingerprint, replay result, and offline operation receipts.
- Browser IndexedDB queue for POS submissions; queued sales are explicitly labelled unconfirmed until server acceptance and replay uses the same operation key.
- Tenant records, memberships, invitations, branch tenant mapping, branch settings, warehouse mapping, integration metadata/outbox, backup/restore run metadata.
- Branch waste event RPC with idempotent stock deduction, opening/closing checklist remains in place, and shift handover record/acknowledgement UI/API.
- Static contract tests for schema/API/UI and a PR-triggered workflow.

### Not yet proven or complete
- Migration has not been applied to Supabase staging from this branch, and Edge Function has not been deployed from this branch.
- Positive E2E is not run: POS → payment → KDS → recipe stock → waste/shift reconciliation → reports.
- Online checkout modifier selection is not yet wired through the customer checkout UI.
- Tenant foundations are additive but **do not yet constitute complete tenant isolation**. Several legacy global catalogs, finance actions, audit queries, job-position templates, and permission checks still need tenant-aware scoping. Do not onboard a second live tenant until the isolation suite is implemented and accepted.
- Tenant invitation token is manually delivered; email delivery and token acceptance are not verified end-to-end.
- Integration connections/outbox and backup/restore tables are metadata foundations. They do not run provider delivery workers or execute/verify database backup and restore.
- Branch-specific configuration has a versioned API and form, but effective-dated resolution is not yet wired into every POS, tax, pricing, menu and fulfillment decision.
- Modifier-required groups and recipe substitution are implemented at schema/API level; full customer checkout modifier UI and substitution UI-to-order snapshots still need complete E2E validation.
- KDS UI visual/accessibility review is blocked until the authenticated staging preview can be opened.
- 150-branch load/recovery test has not run. No synthetic load should be sent to production.

## Proposed acceptance thresholds (Owner must approve before production use)

| Area | Acceptance threshold |
|---|---|
| Idempotency | Same actor + branch + key + payload creates exactly one sale, one KDS ticket, and one set of stock movements; same key with changed payload is rejected |
| Inventory | No negative on-hand; each issue/waste movement has source type and source ID; calculated balance equals ledger balance exactly to 0.001 unit |
| KDS | Paid/confirmed order reaches KDS once; ticket transition is versioned and audit logged; order fulfillment status matches ticket state |
| Offline recovery | Local operation remains labelled unconfirmed; after network recovery, each accepted operation is replayed once; conflicts are surfaced rather than silently overwritten |
| Branch controls | Checklist critical failures block completion; handover is acknowledged by a different user; cash variance and waste remain auditable |
| Tenant isolation | 100% cross-tenant read/write denial tests pass for every tenant-scoped API and data table; no fallback global Owner bypass |
| Performance (provisional) | At approved synthetic load: API p95 ≤ 500 ms, POS create p95 ≤ 800 ms, KDS dispatch p95 ≤ 2 s, error rate < 1% |
| Scale stages | Synthetic progression at 1, 10, 50 and 150 branches, with concurrent-user and transaction rates explicitly documented before the 150-branch stage |
| Recovery (provisional) | Backup integrity/checksum verified; restore drill achieves Owner-approved RPO/RTO; suggested initial target RPO ≤ 15 min and RTO ≤ 4 hours |
| Audit | 100% of approval, stock, shift, waste, tenant and integration state changes include actor, timestamp, entity and source reference |

Performance/RPO/RTO values are proposed test targets, not observed results or agreed production SLOs.

## Execution order / gates

1. **Schema and contract CI:** run the new KDS/offline contract suite; correct SQL/TypeScript/HTML failures before database changes.
2. **Staging migration review:** check migration ordering, schema advisor findings, RLS on every new table, no direct anon/authenticated grants, and function execute ACL.
3. **Staging deploy:** apply migrations to `higoadrzxnhzbbwhdbmh`, then deploy `dlice-orders` to staging only. Preserve `verify_jwt=false` only with all custom per-action authorization tests passing.
4. **Authenticated role E2E:** Owner, Branch Manager, Cashier, Production, Inventory and Finance; include cross-branch and cross-tenant negative tests.
5. **Reconciliation:** run one synthetic order and one POS sale through payment, KDS, recipe stock, waste, shift close/handover and reporting. Reconcile order/sale, ticket, stock movement, on-hand, cash and audit rows.
6. **Offline fault injection:** timeout after commit, duplicate submit, same key/different payload, lost connection, recovery, and stale/closed shift.
7. **Tenant isolation:** do not declare complete until every global catalog, report, audit, finance and branch action is scoped to active tenant membership and the negative test matrix passes.
8. **Backup/integration proof:** execute a real staging backup/restore drill and a provider sandbox retry/dead-letter test; metadata rows alone do not count.
9. **150-branch load:** run synthetic load in isolated staging with quotas reviewed; record p50/p95/p99, error rate, database saturation and recovery evidence.
10. **Accept:** publish sanitized evidence and mark each feature PASS/PARTIAL/BLOCKED/FAIL. Production promotion remains a separate explicit Owner decision.

## Safety notes
- Never store provider credentials in `integration_connections.config`; use a secret manager reference.
- Do not mark offline sales as paid/accepted locally.
- Do not enable `stock_tracking_enabled` until the active recipe, units, opening balance and stock ledger have been reviewed.
- Tenant migration assigns existing branches and existing admin profiles to the single default D’Lice tenant. Creating another tenant is not proof that all old data is isolated from it.
