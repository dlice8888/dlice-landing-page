# D’Lice FnB OS — PRD traceability & Superpowers delivery plan
**Audit snapshot:** 2026-10-23  
**Baseline:** GitHub `staging`, Supabase staging project `higoadrzxnhzbbwhdbmh`, Vercel Preview deployments, and currently accessible Figma account metadata.  
**Production guardrail:** `main`, production Supabase project `gdjlkrmlsurcdbwnmqgg`, and `https://dlice.vercel.app/` are out of scope until all gates pass and Owner explicitly approves.

## How progress is scored
These are evidence-based engineering estimates of PRD feature coverage, not the percentage of screens or database objects created. A feature is not "done" merely because a table, button, or handler exists. Full credit requires working behavior, permission/scope checks, meaningful positive and negative tests, auditability, and end-to-end reconciliation where applicable. Overall mean across 18 domains: **31% estimated coverage**. This is not production-readiness or 150-branch readiness.

Status: **Partial** = some implementation exists; **Gate** = blocked by runtime, integration, or acceptance evidence; **Not implemented** = no sufficient implementation evidence found; **Unverified** = needs a real browser/fixture test.

## Executive summary
- Supabase staging is `ACTIVE_HEALTHY` (PostgreSQL 17), with 38 recorded migrations through `20261023003006_revoke_direct_client_access_stock_workflows`.
- 45 public tables have RLS enabled. Several operational tables have no real business rows yet, so schema presence is not proof of complete workflows.
- Edge Function `dlice-orders` is ACTIVE v50 and has `verify_jwt=false`; the function implements custom per-action authentication/authorization, but public endpoint hardening still depends on the runtime CORS gate. Current deployed source still has a temporary project-ID-guarded staging origin fallback. PR #32 removes that fallback but remains Draft and is not deployed.
- PR #31 is Draft. Its reported acceptance suite is 21 PASS / 0 FAIL for role/scope and negative probes only. It explicitly does not establish positive-path business E2E.
- Vercel Preview build for commit `576d0781281ea826d19824990cd1668190d1ab46` is READY. This does not deploy Supabase functions.
- Security Advisor: leaked-password protection disabled. Performance Advisor: 69 unused-index findings; do not bulk-drop them.
- Figma account is on Starter/View seat and Code Layers are disabled. No current screenshots were captured for this audit, so cross-device visual QA is not marked passed.
- `README.md` explicitly says website order routing, recipe-based ingredient deduction, supplier receiving automation, payroll, taxes, refund/void POS, bank/QRIS settlement, and accounting period close are not claimed complete until approved rules and end-to-end tests exist.

## 18-domain feature coverage matrix

| # | Domain | Est. coverage | Evidence present | Main missing / acceptance blocker |
|---|---|---:|---|---|
| 1 | Executive Command Center | 20% | `erp-overview`, reports/funnel metrics, branch master and alerts foundations | Official KPI definitions, sales/margin/stock/waste rollups, branch ranking, anomaly assignment, region→branch→shift→transaction drill-down, scheduled executive reports |
| 2 | POS & Checkout | 45% | POS shifts/sales, cart/order checkout, payment proof and status separation foundations, cash reconciliation | Full dine-in/takeaway/pickup/delivery parity, modifiers, discount/voucher rules, split/partial payments, hold/resume, void/refund/return policy and approvals, receipts, offline queue; POS sale→stock→ledger→settlement E2E |
| 3 | Order Management | 55% | Online order flow, branch/product capacity, reservations/cutoff, order status history, fulfillment queue/status transitions | WhatsApp/marketplace connectors, duplicate/idempotency behavior, preparation ETA, exception escalation, channel-wide status parity and customer notifications E2E |
| 4 | Kitchen & Production | 35% | Recipe/BOM, production batches, actual consumption RPC, fulfillment status integration | KDS stations and ticket dispatch, prioritization/SLA, prep list, batch planning, QC/temp, waste/spoilage, made-to-order vs batch scheduling, actual-vs-theoretical usage reconciliation |
| 5 | Menu, Recipe & Product Engineering | 45% | Product catalog, branch capacity, recipe ingredients/version activation, price/copy migration | Nested BOM/yield conversion, effective-date history proof, allergens, central/regional/branch pricing policies, cost/margin calculation, approval simulation and POS/production version parity |
| 6 | Inventory & Warehouse | 55% | Inventory items, branch inventory, stock movement ledger, transfers with approve/pick/ship/receive/reconcile states, stock counts | Multi-warehouse/storage/batch/lot, FIFO/FEFO, reserved/in-transit/blocked balances, valuation, reorder points, cycle-count variance approval, full receiving/production/waste/transfer ledger reconciliation |
| 7 | Procurement & Supplier | 35% | Supplier master, PO draft/update, purchase receipt/GRN, atomic receipt→stock RPC, permission gates | Purchase requisitions, consolidated multi-branch buying, approval thresholds, supplier price history/contracts, invoice three-way match, AP handoff, supplier returns and performance metrics |
| 8 | Branch Operations | 50% | Branch directory/status/timezone, job positions/assignments, opening/closing checklist and completion gates | SOP/task scheduling, photo evidence, incident/escalation, equipment maintenance, temperature checks, branch audit score, readiness enforcement on real branch lifecycle |
| 9 | Delivery & Fulfillment | 20% | Pickup/delivery selection fields, branch routing foundations, fulfillment queue/status workflow | Live courier quote/booking/tracking, Biteship integration, address validation, proof of delivery, retry/cancel handling, separate food/fee/subsidy/courier cost and cost reconciliation |
| 10 | CRM & Loyalty | 10% | Customer/order identity fields and order history foundations | Unified customer profiles/consent, segmentation, points/tiers, rewards/vouchers, referrals, campaigns, support/feedback and attributable campaign analytics |
| 11 | Finance & Accounting | 35% | Expense approvals, settlement creation/matching, refund records, cash/bank/QRIS reconciliation, tax settings and fiscal-period guards; journal table exists | Full AR/AP/GL, chart of accounts, balanced journal lines and source mapping, tax compliance, budget, period lock/reopen controls, branch P&L/consolidation and source-to-bank reconciliation E2E |
| 12 | HR & Workforce | 15% | Job positions, branch assignments, role/permission scaffolding | Employee lifecycle, attendance, schedule, timesheets, leave/overtime, payroll integration, labor cost allocation, training/certification, offboarding/session revocation |
| 13 | Franchise & Expansion | 5% | Branch master and ownership model foundations only | Franchise application/contracts/territory, site feasibility, opening project, royalty calculation, franchise-specific access and compliance workflow |
| 14 | BI & Analytics | 20% | Funnel metrics and basic overview/report UI | KPI dictionary, verified sales/margin/food-cost/labor/waste metrics, fair branch cohorts, forecast/demand planning, data quality, anomaly workflow, exports and action-outcome tracking |
| 15 | Admin, Identity & Access Control | 55% | Admin profiles, login/session lookup, role permissions, branch assignments, audit logs, action-level auth and branch checks | Full role×scope×action matrix, delegated approval policy, access reviews, session/device management, recovery/offboarding controls, API-wide BOLA/cross-tenant negative tests and audited permission changes |
| 16 | SaaS Tenant Management | 5% | Product is designed around one D’Lice organization and multiple branches | Tenant table/membership isolation across DB/API/storage/cache/jobs, tenant onboarding, entitlements, quotas, subscription billing, suspension, support access and export/offboarding |
| 17 | Integrations & Automation | 20% | Supabase Edge Function/API, payment proof flow, notification logs/retry actions, rate limiting | Verified payment-provider callbacks, webhook signing/idempotency/replay protection, delivery/e-commerce/accounting/WhatsApp connectors, durable retry/dead-letter queue, secret rotation and integration health |
| 18 | Quality, Compliance & Security | 35% | RLS on 45 public tables, restricted direct access for internal/stock tables, audit logs, rate limits, branch checklists, cutoff timezone support | CORS secret-only runtime verification, leaked-password protection, food safety/temperature/allergen/recall workflow, backup+restore drill, monitoring/runbooks, load/concurrency tests and incident/corrective-action closure |

**Arithmetic mean: 31% estimated PRD feature coverage.** The estimate is deliberately not called "31% finished": the percentage discounts features that exist only as schema or UI without positive E2E proof. Operational readiness is lower than feature coverage; 150-branch readiness is **not demonstrated**.

## Cross-domain workflows — current acceptance state

| Workflow | Current evidence | Status |
|---|---|---|
| Order-to-Cash | Order/payment/fulfillment/settlement/cash-reconciliation handlers and guard tests exist | **Partial / E2E blocked** — no positive disposable-fixture lifecycle with reconciled totals |
| Procure-to-Pay | PO, receiving RPC, receipt tables, stock movement path and negative authorization probes exist | **Partial / E2E blocked** — no positive PR→approval→PO→GRN→stock→invoice/AP→payment reconciliation proof |
| Forecast-to-Production | Recipes/BOM, batch and actual-consumption code exists | **Partial / E2E blocked** — no demand forecast and no verified theoretical-vs-actual inventory reconciliation |
| Record-to-Report | Settlement, cash reconciliation, tax settings and fiscal period guards exist | **Partial / E2E blocked** — no full balanced GL, period close evidence, and branch/group P&L reconciliation |
| Stock transfer/count | State machine, audit trail and permission probes exist | **Partial** — must test positive state transitions, quantities, ledger balances, idempotent retries and cross-branch scope |
| Login / permissions | Custom auth/profile/permissions/branch checks and 21 negative/role probes reported | **Partial / CORS gate open** — deployed endpoint still `verify_jwt=false`; verify custom auth on every protected action and exact origin allowlist at runtime |
| Responsive UI/CX | Static HTML/CSS has responsive grid, focus-visible rings, 44px touch targets and reduced-motion intent documented | **Unverified** — current screenshot capture and real device/browser test evidence missing |
| Backup/restore, scale and rollout | No acceptance evidence retrieved in this audit | **Not demonstrated** |

## Superpowers delivery protocol
Use small vertical slices; do not start 18 modules in parallel.

1. **Specify:** turn every PRD bullet into an acceptance criterion and identify owner, data source, permission/scope, audit event, failure behavior and reconciliation rule.
2. **Plan:** choose one bounded slice with dependencies and rollback path; staging-only, free-tier first.
3. **Test first:** add deterministic unit/contract tests and staging E2E probes before implementation. Use disposable fixtures and clean them up; no real business records in negative probes.
4. **Implement:** schema/migration, server-side authorization and atomic RPC, UI, audit logging and idempotency in the same vertical slice.
5. **Verify:** quality checks, positive and negative tests, cross-branch/anonymous tests, data-ledger reconciliation, mobile/desktop smoke and Supabase advisors.
6. **Review:** PR remains Draft until evidence is attached; mark ready only after test artifacts and risk review.
7. **Deploy staging:** apply migration and deploy Edge Function to staging only; compare source/runtime hashes and run smoke tests against the actual Preview URL.
8. **Accept and repeat:** Owner/business acceptance for the slice; only then start the next dependency slice. Production requires all release gates plus explicit Owner approval.

## Delivery order
- **P0 — close current release/security gates:** CORS exact-secret runtime, auth/scope regression suite, migration/runtime parity, leaked-password protection decision, cross-branch/anonymous probes.
- **P1 — finish core operating loop:** procurement→receiving→stock ledger; POS/order→payment status→fulfillment; recipe/BOM→production consumption; stock transfer/count; settlement→cash reconciliation.
- **P2 — accounting and branch control:** balanced journal/GL, AP/AR, fiscal close/reopen, branch P&L, branch opening/closing and SOP/incident workflows.
- **P3 — customer, delivery and intelligence:** CRM/consent/loyalty, courier integration, official KPI definitions, analytics/alerts/forecasting, retries/idempotency.
- **P4 — workforce and SaaS commercialization:** HR scheduling/payroll integration, franchise, tenant isolation/onboarding/entitlements/billing.
- **Scale gate:** concurrency/load testing, backup+restore drill, observability/runbooks, branch pilot and rollback evidence before claiming 150-branch readiness.

## Immediate blockers / safe decisions
1. PR #32 must remain unmerged until secret save is confirmed by the Owner and runtime CORS probes pass on staging.
2. PR #31's 21/21 reported tests are authorization probes, not positive business E2E.
3. Keep `main` and production untouched.
4. Keep the 69 unused-index findings for workload-based review; do not bulk-drop them.
5. Leaked-password protection remains an explicit security warning; don't silently upgrade a paid plan.
6. Do not invent missing business rules, external provider credentials, legal/payroll/tax policy, or tenant billing behavior. Capture these as implementation prerequisites before the affected feature is enabled.
7. UI changes must preserve the existing palette and priority copy, and must honor reduced-motion settings.
