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

## Known limitations

Executive sales monitor, branch-local business-day cutoff, Unified Approval Inbox, claim/decision/history/delegation actions, POS order-type checkout, and fulfillment history are now wired through the ERP UI and authenticated Edge API. Their database migrations remain source-only until the final migration batch is explicitly scheduled.

The current branch's contract suite and staging CORS/KDS probes have passed at the latest observed head. Disposable migration replay is still running. Staging schema inspection confirms the T01/T02/POS-fulfillment objects are not yet present, so authenticated staging workflow E2E and E6 transaction reconciliation remain blocked until the final migration/deployment window. Do not infer schema readiness, successful staging migration application, or E6 from source/CI evidence alone.
