# Feature workflow implementation notes

## Scope and release posture

This branch adds source-controlled workflow foundations and contract coverage for Executive Command Center, approval inbox, POS checkout/cash reconciliation, Order, Kitchen, Menu/Recipe, Inventory, and the eight priority domains.

These changes are **not a staging release**. No production mutation, staging migration application, merge, auto-merge, force push, or release-flag change is authorized by this work. Tenant isolation and public tenant routing release flags remain closed.

## Migration inventory

- `20261128101500_executive_sales_monitor.sql`: versioned Executive sales/KPI aggregation and Finance reconciliation source.
- `20261128102000_executive_approval_center.sql`: tenant/branch-scoped approval inbox, claims, decisions, history, and delegation primitives.
- Existing POS shift/cash and checkout migrations are extended only in source to enforce held-order and split-tender refund reconciliation guards.

## Required validation before any release

1. Disposable migration replay across the complete migration chain.
2. All contract and security tests, including RLS/ACL assertions.
3. Staging tenant A/B and branch A/B authenticated acceptance; Storage, browser UI, and lifecycle E2E.
4. POS reconciliation across sale totals, split tender, refunds, settlements, cash drawer, inventory movements, KDS tickets, immutable receipts, Finance journal entries, and audit events.
5. Evidence ledger for every feature from E0 through E6. No feature is DONE on source or CI evidence alone.

## Ticket coverage and evidence status

The candidate contains source modules and contract tests for the 39 requested tickets:
- T01–T02 Executive sales monitor and unified approval center.
- T03–T09 POS shifts, cart, order types, payment, refund/void, cash drawer and independent order/payment/fulfillment state.
- T10–T16 unified order queue, availability, routing, business numbering, timeline, cancellation/history and notifications.
- T17–T23 KDS, prep SLA, kitchen lifecycle, recipe yield/costing, prep planning, batch consumption and production mode.
- T24–T30 product catalog, branch availability, pricing, BOM, recipe versioning, stock availability and recipe change rollout.
- T31–T39 inventory balance, movement ledger, warehouse/bin, UOM, stock buckets, reorder, cycle count, adjustments and procurement receiving reconciliation.

All 39 remain **PARTIAL** until each database contract, authenticated tenant/branch runtime workflow, browser/device acceptance and feature-specific E6 reconciliation is evidenced.

## Migration status

Official source migrations in this candidate cover Executive sales, Executive approvals, POS shift/cash, order state transitions and POS sale fulfillment types. Order Management, Kitchen/Production and Menu/Recipe SQL remain design drafts in `docs/implementation/sql`; they are not yet official migrations. Inventory modules rely partly on the existing stock transfer, count, receiving and movement foundations; full parity still requires E6 evidence.

The full repository disposable local Supabase migration replay **passed** on candidate commit `207314a2f835660d6d8fdb45dfa719818b6fa241`. The Free quality-check workflow also **passed**, including the full contract suite. This is source and disposable-database evidence only; it does not prove that the migrations were applied to staging or that staging workflows passed.

## Remaining acceptance gates

1. Promote the reviewed Order, Kitchen/Production and Menu/Recipe SQL designs into official migrations after dependency, RLS, FK, function ACL and rollback review.
2. Run authenticated staging tenant A/B and branch A/B workflows.
3. Run browser/device acceptance for Executive, POS, Order, Kitchen, Menu and Inventory workflows.
4. Reconcile POS sale, tender allocation, refund, settlement, cash drawer, stock movements, KDS tickets, immutable receipt, Finance journals and audit events through E6.

No production mutation, staging migration application, merge, auto-merge, force push, or release-flag change has been performed. `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false` remain closed.
