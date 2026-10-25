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
- Staging deployment has since been completed: the KDS/platform migrations are applied and `dlice-orders` v58 is active; tenant creation/invitation is fail-closed until isolation acceptance. Source and staging runtime are not considered accepted until the positive-path E2E workflow and tenant isolation checks pass.
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

## Legacy branch authorization hardening — 2026-10-24

- Static review found legacy helpers `actorCanAccessBranch` and `actorBranchIds` used branch assignments without checking active tenant membership.
- Tests First: a contract assertion was added, the first CI run failed because the test regex was over-escaped (not because the authorization change failed), then the regex was corrected. The latest PR CI run passed the KDS/offline contract, Free Quality Checks, both procurement contracts, and CORS probes.
- Both legacy helpers now fail closed unless the actor has an active membership in the branch's tenant; tenant owners/admins are scoped to branches belonging to their own tenant. Platform Owner retains the existing platform-wide bypass.
- Deployed the reviewed feature-branch Edge Function to staging as **v58 ACTIVE**. Runtime CORS probes passed after deployment. The manual positive-path business E2E and authenticated negative cross-tenant tests remain required; static contracts are not substitutes for them.

## Tenant onboarding safety gate — 2026-10-24

- The staging audit found 154 branch rows with non-null tenant IDs but only one tenant. This proves data mapping completeness for current rows, not cross-tenant isolation.
- A fail-closed release gate is now present in the feature branch: `erp-create-tenant` and `erp-invite-tenant-member` return HTTP 423 until cross-tenant negative tests cover legacy catalog, finance, reporting, audit, permissions, and branch-scoped operations.
- Contract test added first, then implementation added. The PR-triggered `Staging Kitchen KDS Offline Contract Tests` run for commit `b02d62fccb2991331838cd0c41db4e9914dad152` completed successfully.
- Keep the gate disabled until isolation is proven end-to-end; do not create or onboard a second tenant meanwhile. This is a safety containment, not a claim that SaaS multi-tenancy is complete.
- The PR-triggered contract suite now asserts that the staging E2E script checks both create-tenant and invite-member actions return HTTP 423 using malformed payloads, so a broken gate cannot create test tenant data. Static CI, KDS/offline contract, procurement contracts, and CORS probes passed for commit `16976e9f454388f18229df6c3d86ee7e0bd04f2f`; authenticated runtime assertions still await the manual staging workflow.

## Staging deployment checkpoint — 2026-10-24 17:56 UTC

- Applied `kitchen_kds_idempotency_modifiers` to staging project `higoadrzxnhzbbwhdbmh` (remote migration version `20261023175347`).
- Applied `tenant_branch_platform_foundation` to staging (remote migration version `20261023175514`).
- Applied `tenant_branch_integrity_constraints` to staging; composite foreign keys now enforce tenant↔branch consistency for warehouses, branch settings, shift handovers, waste events, integration outbox, and branch inventory↔warehouse mapping.
- Deployed `dlice-orders` Edge Function **v58** to staging after the fail-closed tenant onboarding guard was added. `verify_jwt=false` is preserved; custom per-action auth remains required. `verify_jwt=false` is preserved; custom per-action auth remains required.
- Added `erp-list-waste-events` so waste events can be reconciled to stock movements and audit records.
- Applied `kds_pos_deferred_dispatch` (remote migration version `20261023180455`). POS KDS dispatch now runs as a deferred constraint trigger so the ticket snapshots sale lines after the POS transaction writes items/modifiers/substitutions.
- Added `erp-reconcile-pos-sale`, a branch-scoped reconciliation response joining sale lines, KDS ticket/items, stock movements, current balances, and audit events.
- Added manual workflow `.github/workflows/staging-kds-pos-stock-positive-e2e.yml` and script `tests/staging/kds-pos-stock-positive.mjs`. It covers POS paid sale, same-key replay, changed-payload rejection, offline replay after commit, KDS lifecycle, exact recipe stock consumption, report presence, reconciliation and QA fixture cleanup. **It has not been dispatched yet** because it requires an explicit manual staging-mutation confirmation and environment credentials.
- Staging SQL verification: 10 tenant/platform tables present; all 17 new KDS/platform tables have RLS enabled; zero direct table grants to `anon` or `authenticated`; all 4 expected dispatch/stock/versioning triggers exist; product stock tracking and online order snapshot columns exist.
- Contract/quality/CORS workflows passed on the pre-deployment commit. Re-run runtime CORS and CI against the post-deployment source commit; business E2E is still not accepted.
- Supabase Security Advisor reports 17 `rls_enabled_no_policy` informational findings for the new internal tables. Direct client grants are zero by design; access is currently through the authenticated Edge Function using service-role access. These findings are not a substitute for the required cross-tenant authorization tests.
- The tenant migration initially failed validation before any schema changes from that migration were applied; the malformed fingerprint constraint and orphaned duplicate fragment were corrected, then the migration applied successfully. Keep the migration contract guard in CI to prevent recurrence.

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


## Follow-up: KDS E2E fixture cleanup hardening — 2026-10-24

- Live read-only preflight confirmed the fixed QA branch/product/recipe/ingredient IDs exist; the QA product is inactive and the recipe starts in `draft`.
- Review found that the E2E script activated the recipe but did not restore that temporary state. Added a guarded `erp-retire-recipe` action for Production Head Office, which only retires an active recipe after its product is inactive and stock tracking is disabled; draft/retired recipes are handled idempotently.
- Updated `tests/staging/kds-pos-stock-positive.mjs` to remember whether the recipe started as draft and retire it during `finally` cleanup after restoring the product. Cleanup failures are recorded in `cleanup_errors`.
- Added a contract test for the new route and cleanup sequence. Deployed staging Edge Function `dlice-orders` as **v59 ACTIVE**, preserving `verify_jwt=false`; fetched deployed source confirms the new route is present.
- The manual KDS/POS and procurement E2E workflows remain unexecuted. Do not infer business acceptance from deployment or static contracts; inspect the sanitized artifacts after manually dispatching both workflows.
