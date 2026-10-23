# D’Lice FnB OS — Staging Gap Audit & Implementation Roadmap
Date: 2026-10-21
Scope: GitHub `fix/staging-security-timezone-20261021` / PR #24, Supabase staging `higoadrzxnhzbbwhdbmh`, Vercel Preview, and available Figma workspace.
Production changes: none.

## Executive status

**Planning estimate: ~20% of the full blueprint is represented by a code/data foundation; end-to-end readiness is not yet established.** This is a directional gap estimate, not a test-pass rate or feature-completion claim. UI, schema presence, and deployment READY are not equivalent to a working workflow.

- Current operational workspace has 9 navigation domains: dashboard, order & fulfillment, production & BOM, POS, inventory, purchasing, finance, branches & HR, reports.
- Staging schema includes 41 listed public tables (orders, products, branch/ERP/finance foundations); many ERP tables are empty in staging. Empty tables do not prove unusable code, but do show that production-like acceptance evidence is missing.
- Migrations include checkout, role permissions, POS/ERP foundation, order fulfillment/production/finance controls, routed checkout, settlement/refund guards, recipe activation, direct-client denial policies, branch timezone cutoff, and FK indexes.
- Supabase Edge Function `dlice-orders` is ACTIVE version 33. `verify_jwt=false` means application-level token verification/authorization must be tested for every action.
- Latest Vercel preview commit observed: `d30e59b5314472a8816053d308997428c8a87743`, state READY. READY confirms deployment/build, not authenticated UI or business workflow acceptance.
- Figma connection is available on Starter/View seat; Code Layers/specs are disabled. No evidence was obtained that an approved, authoritative FnB OS design file or complete component library is available. Treat Figma design parity as unverified until a target file/frame is identified.
- Product Design full audit workflow is available in Work mode; this chat does not expose its screenshot-capture flow. Technical repository/database review can proceed here, but a screenshot-backed UX audit must be completed in Work mode.

## Domain estimate (18 blueprint modules)

Percentages are **coverage estimates for current code/data evidence**, not test pass rates.

| # | Domain | Estimated coverage | Evidence / main gaps |
|---|---|---:|---|
| 1 | Executive Command Center | 25% | Summary view exists; live all-branch KPIs, ranking, alert-to-task workflow, and drill-down need proof/build. |
| 2 | POS & Checkout | 40% | Shift and POS transaction UI/schema; refund/void, offline queue, split payments, receipt lifecycle and payment reconciliation need completion/testing. |
| 3 | Order Management | 40% | Orders, payment records, history, capacity/cutoff foundations; channel unification, exception handling, routing and customer timeline incomplete/unverified. |
| 4 | Kitchen & Production | 30% | Recipe/BOM and batch/consumption foundations; KDS, station routing, production queue, quality and waste workflows incomplete/unverified. |
| 5 | Menu & Recipe Management | 30% | Product catalog, recipes, ingredients, version activation foundations; modifiers, units/yield, allergen, effective pricing and costing need completion. |
| 6 | Inventory & Warehouse | 30% | Inventory item, branch balances, stock movements, ledger foundations; counts, lot/expiry, transfers, valuation and auto-consumption incomplete/unverified. |
| 7 | Procurement & Supplier | 30% | Supplier, PO, receipt schema and UI foundations; PR, supplier pricing, 3-way match, invoice/AP, return and performance incomplete/unverified. |
| 8 | Branch Operations | 20% | Branch master/assignments and shift/expense foundations; opening/closing checklist, tasks, SOP, incidents, maintenance and audit missing/unverified. |
| 9 | Delivery & Fulfillment | 25% | Fulfillment queue/status foundations; courier API, quotes, tracking, POD, delivery-cost reconciliation not evidenced. |
| 10 | CRM & Loyalty | 0% | No dedicated CRM/loyalty domain evidenced in inspected operational workspace/schema. |
| 11 | Finance & Accounting | 25% | Expenses, cash reconciliation, settlements, refunds, tax/fiscal-period/journal foundations; AP/AR, GL posting, bank reconciliation and consolidated P&L unverified. |
| 12 | HR & Workforce | 15% | Job positions and staff assignments foundations; attendance, scheduling, leave, payroll and training not evidenced. |
| 13 | Franchise & Expansion | 0% | No franchise/site-selection/royalty workflow evidenced. |
| 14 | BI & Analytics | 15% | Basic report/funnel metrics; canonical KPI definitions, profitability/food-cost/labor/waste analytics and forecasting missing/unverified. |
| 15 | Admin & Access Control | 45% | Role/permission/branch-scoping code and security audit exist; negative API tests, audit-log completeness, sessions/device controls and access reviews still required. |
| 16 | SaaS Tenant Management | 0% | No tenant isolation, plans, subscriptions, entitlements, quotas or billing evidence. One company with 150 branches is not multi-tenant SaaS. |
| 17 | Integrations & Automation | 15% | Edge Function and notification/payment foundations; webhook idempotency/retry console, provider health, Biteship, WhatsApp, external channels not evidenced. |
| 18 | Quality, Compliance & Security | 20% | RLS deny policies and security foundations exist; food safety, temperature, traceability/recall, backup restore drills and operational monitoring incomplete/unverified. |

## Release-gate status

- [x] Staging target identified and production protected.
- [x] RLS enabled and deny policies/direct-grant restrictions recorded for 27 internal ERP tables (per existing audit artifact).
- [x] Branch timezone/cutoff and missing-FK index migrations recorded in staging.
- [ ] Negative access matrix passes for anonymous, unauthorized, inactive, wrong-branch and Owner users.
- [ ] CORS OPTIONS/POST verified for allowed preview and rejected origin.
- [ ] Checkout tests pass before/at/after 18:00 in WIB/WITA/WIT using disposable staging fixtures.
- [ ] POS → payment → order → fulfillment → inventory → finance end-to-end reconciliation passes.
- [ ] Procurement → receipt → stock ledger → invoice/AP reconciliation passes.
- [ ] Production/KDS, recipe consumption, waste and costing reconciled.
- [ ] Mobile/tablet/desktop screenshot-backed UX/accessibility audit complete.
- [ ] Load, retry/idempotency, backup/restore and recovery tests complete.
- [ ] Final CI/security/performance checks pass on final PR head.
- [ ] Explicit Owner approval recorded before any production merge.

## Implementation order

### P0 — Security and transaction correctness
1. Establish repeatable staging test fixtures and role/branch test identities.
2. Run anonymous/authenticated negative API tests and CORS preflight/POST tests.
3. Run timezone cutoff checkout matrix and verify status separation: order vs payment vs fulfillment.
4. Capture evidence (request, status, before/after row counts) and fix failures before proceeding.

### P1 — One connected core workflow
1. POS sales and shifts; idempotent payment status transitions and receipt.
2. Order state machine and branch fulfillment queue.
3. Recipe/BOM consumption, stock ledger, goods receipt, transfer/count/waste.
4. Cash/QRIS settlement, refund controls, reconciliation and finance traceability.
5. Automated end-to-end tests for each workflow.

### P2 — Finance, workforce and branch controls
1. Posting rules, chart of accounts, journal lines, AP/AR and close periods.
2. Branch opening/closing, tasks, incidents, maintenance and audit checklists.
3. Staff schedule/attendance and payroll integration boundary.

### P3 — Analytics, CRM and automation
1. Official KPI dictionary and branch drill-down/alerts.
2. Customer profiles, consent, loyalty, vouchers and campaign attribution.
3. Integration retry/idempotency/event log, notifications and delivery aggregator.

### P4 — SaaS and scale
1. Tenant/company membership and database-level tenant isolation across tables, storage and functions.
2. Plans, entitlements, usage, billing, support access and offboarding.
3. Load, disaster recovery, pilot rollout and 150-branch readiness gates.

## Non-negotiable implementation rules

- Do not claim a module complete because a navigation item or table exists.
- Use staging fixtures only; never create test transactions against production customers.
- Do not add paid services or upgrade plans without approval.
- Keep all work in a feature branch and Preview; do not merge/deploy production without passing gates and explicit Owner approval.
- Record each feature's acceptance tests, negative tests, screenshots, and rollback path.
