# D’Lice FnB OS — Staging Capability Audit & Implementation Register
Date: 2026-10-21
Baseline: GitHub PR #24 head `d30e59b5314472a8816053d308997428c8a87743`
Target environment: Supabase staging `higoadrzxnhzbbwhdbmh` + Vercel Preview only.
Safety: do not merge or modify production without passing acceptance tests and explicit Owner approval.

## Audit method and meaning of progress
- **Present** means source/schema evidence exists; it does not mean production-ready.
- **Partial** means some screens, tables, RPCs, or workflow steps exist, but at least one critical sub-workflow is missing or not verified.
- **Not evidenced** means no sufficient evidence was found in the current staging schema/source audit.
- **Test status** is tracked separately from implementation status. A READY Vercel build is not an end-to-end acceptance test.

### Snapshot from live staging
- Supabase staging is ACTIVE_HEALTHY; separate production project exists and must remain untouched.
- Staging has 39 public base tables covering branches, users/admin profiles, orders/payments, POS sales/shifts, inventory/stock movements, recipes/production, suppliers/purchase orders/receipts, branch expenses, journals/fiscal periods, refunds/settlements, rate limits, and audit logs.
- Staging has 15 public functions including atomic checkout/reservation, POS sale creation, recipe activation, production completion/consumption, PO receiving, stock movement, settlement matching, payment verification, and operational status changes.
- 150 branch slots are seeded as planned; only HQ is explicitly seeded active in the foundation migration. Planned slots must not be counted as operational branches.
- Security: 27 internal ERP tables have restrictive deny policies for anon/authenticated and 0 direct SELECT grants across those tables. Remaining Security Advisor warning: leaked-password protection disabled.
- Performance: no missing-FK-index warning remains; 67 unused-index notices remain and should be assessed with representative workload, not dropped blindly.
- PR #24 is OPEN, DRAFT, UNMERGED. Current head `d30e59b5314472a8816053d308997428c8a87743`; Vercel Preview is READY and latest commit CI status is success. CORS preflight/POST, timezone boundaries, role negative tests, and browser E2E remain unverified.
- Figma account access currently reports Starter plan and View seat; no edit/code-layers capability is evidenced. Product Design workflow must be run in supported Work mode; this audit does not claim Figma files were modified.

## Provisional progress estimate
**Approximately 25–30% functional scope coverage; 0% of the full 150-branch readiness gate is certified complete.**
This is an evidence-based planning estimate, not a test pass rate. The core foundation exists, but many blueprint subfeatures and cross-domain reconciliations are absent or unverified. Recalculate after each acceptance batch using the acceptance register.

## 18-domain matrix
| # | Domain | Current evidence | Status | Critical gaps / acceptance needed |
|---|---|---|---|---|
| 1 | Executive Command Center | ERP overview, branch readiness and operational summary are present in source | Partial | Live sales/branch ranking, profitability, anomaly alerts, actionable alerts, approval center, drill-down and KPI definitions |
| 2 | POS & Checkout | POS sale RPC, shift tables, sales/items, cash reconciliation, online queue UI | Partial | Payment-state separation, split/partial bill, discounts/vouchers, receipts, void/refund, offline queue, end-to-end stock/finance posting |
| 3 | Order Management | Orders/items, reservations, status history, payment records, branch capacity and cutoff logic | Partial | Channel adapters, exception queue, customer history, assignment escalation, notifications and verified status transitions |
| 4 | Kitchen & Production | Recipes, production batches/consumptions, completion RPC and waste quantities | Partial | KDS/station tickets, priority/SLA queue, prep list, quality gate, traceable made-to-order vs batch workflow |
| 5 | Menu & Recipe Engineering | Products, recipes, recipe ingredients, recipe activation/version-related safeguards | Partial | Variants/modifiers, unit conversion/yield, costing/margin, allergen data, effective-dated versions and branch pricing/availability |
| 6 | Inventory & Warehouse | Inventory items, branch inventory, stock movements, production consumption, receipt workflow | Partial | Warehouse/location, batch/expiry/FEFO, reservations/blocked stock, transfer state machine, stock counts and valuation |
| 7 | Procurement & Supplier | Suppliers, purchase orders/items, receipts/items and atomic receiving | Partial | PR, price lists/contracts, tiered approvals, supplier invoice, three-way match, returns and supplier scorecards |
| 8 | Branch Operations | Branch directory/status, assignments, POS shift and cash reconciliation | Partial | Opening/closing checklists, tasks, SOP evidence, incidents, maintenance and branch audit workflows |
| 9 | Delivery & Fulfillment | Fulfillment/status UI and branch order scope exist | Partial | Courier quote/booking/tracking/POD, exception handling, delivery cost reconciliation and tested routing |
| 10 | CRM & Loyalty | Funnel metrics exist; no dedicated CRM domain evidenced in current public schema | Not evidenced | Customer profiles/identity merge, loyalty ledger, rewards, campaigns, consent/preferences, feedback/support |
| 11 | Finance & Accounting | Expenses, journal entries, fiscal periods, refunds, settlements and guards | Partial | Chart of accounts, balanced journal lines, AR/AP, bank reconciliation, tax invoice, budgets, close process and consolidated statements |
| 12 | HR & Workforce | Admin profiles, job positions and branch assignments; no full workforce schema evidenced | Partial | Employee lifecycle, schedules, attendance, leave/overtime, payroll integration, training/certification and labor-cost allocation |
| 13 | Franchise & Expansion | Branch slots and branch master exist; franchise workflows not evidenced | Not evidenced | Ownership model, application/site feasibility, opening project, agreements, royalty and franchise compliance |
| 14 | BI & Analytics | Overview and POS sales report UI, funnel metrics table | Partial | KPI semantic definitions, margins/food cost/labor/waste/variance, benchmarking, forecasting, exports and data-quality checks |
| 15 | Admin & Access Control | Admin profiles, job positions, branch assignments, audit logs, rate limits, permission checks | Partial (strong foundation) | Full action/scope matrix, security-event/session review, access reviews, account recovery and negative API tests |
| 16 | SaaS Tenant Management | No tenant/subscription/entitlement/usage tables evidenced | Not evidenced | Tenant isolation across DB/API/storage/jobs, onboarding, plans, quotas, billing, support access and offboarding |
| 17 | Integrations & Automation | Edge Function, payment notifications, rate limits and funnel events | Partial | Integration registry, webhooks, idempotency/outbox/retry queue, health view, delivery/payment/channel adapters and replay controls |
| 18 | Quality, Compliance & Security | Audit logs, restrictive RLS deny policies, advisor checks and security controls | Partial | Food safety/temperature/allergen/recall workflows, backup-restore drill, monitoring, incident/corrective action and complete security test evidence |

## Cross-module workflow acceptance
1. **Order-to-Cash:** create order → verify payment (never infer paid from order creation) → assign branch → kitchen/fulfillment → consume stock exactly once → journal/settlement → customer/KPI update.
2. **Procure-to-Pay:** stock need → PR → approval → PO → quality/quantity GRN → invoice three-way match → AP → payment/journal.
3. **Forecast-to-Production:** forecast → effective recipe/BOM → available/usable stock → procurement/transfer → batch plan → actual consumption/yield/waste → allocation/availability.
4. **Record-to-Report:** POS/procurement/payroll/expenses → validated source dimensions → balanced journal → cash/bank/stock/AP reconciliation → period close → branch P&L/consolidation.

For each workflow, tests must verify database before/after state, duplicate/retry behavior, branch scope, audit history and reconciliation totals—not just visible success messages.

## Phased implementation order
- **P0 — Foundation/security (blocker):** tenant/company/branch data boundaries, identity + role/action/scope, RLS/API negative tests, audit events, order/payment state model, staging/production separation, test fixtures.
- **P1 — Core commerce/operations:** POS checkout, order/payment/fulfillment, catalog/recipe, KDS/production, inventory ledger/transfer/count, PR/PO/GRN, shifts and cash.
- **P2 — Finance/people/control:** chart of accounts/journal lines, AP/AR, settlement/bank reconciliation, period close, branch P&L, workforce schedules/attendance and payroll integration.
- **P3 — Intelligence/automation:** command center, canonical KPI definitions, alerts/approvals, CRM/loyalty, delivery/payment integrations, idempotent event processing.
- **P4 — SaaS scale-up:** tenant onboarding/isolation, plans/entitlements/usage/billing/support/offboarding, load/restore/pilot/rollout evidence.

## Immediate acceptance blockers
- Run CORS OPTIONS and POST tests against the latest Preview origin and a deliberately unlisted origin.
- Run anonymous, inactive, no-permission, wrong-branch, no-assignment, branch-only, Head Office and Owner tests with before/after row checks.
- Exercise 17:59/18:00 local checkout boundaries for Asia/Jakarta, Asia/Makassar and Asia/Jayapura with disposable staging fixtures.
- Verify POS → payment → fulfillment → stock → journal/settlement end-to-end and duplicate webhook/retry behavior.
- Review mobile/tablet/desktop in authenticated browser; collect screenshots and test evidence.
- Confirm staging backup/restore and load/concurrency plan before any pilot.
- Keep PR #24 draft/unmerged until every blocker is closed and Owner explicitly approves.

## Implementation governance
- Every feature is developed on a feature branch and previewed against staging.
- Schema changes require committed migrations and staging verification queries.
- Secrets must stay in the correct environment; never commit service-role keys.
- No paid plan or paid integration is enabled without explicit approval.
- No production migration, secret, deployment, alias promotion, or merge is performed without passing acceptance and explicit Owner approval.
