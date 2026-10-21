# D’Lice FnB OS — Staging Capability Audit & Implementation Register
Audit refresh: 2026-10-22
Code baseline: GitHub PR #25 head `02dd251faf43342ef5646a3eb04468349854c4a8`; PR #24 security/timezone base head `3f148185b8a8a9a4e1bbeeab38c8596f8cf646dd`
Target environment: Supabase staging `higoadrzxnhzbbwhdbmh` + Vercel Preview only.
Safety: do not merge or modify production without passing acceptance tests and explicit Owner approval.

## Audit method and meaning of progress
- **Present** means source/schema evidence exists; it does not mean production-ready.
- **Partial** means some screens, tables, RPCs, or workflow steps exist, but at least one critical sub-workflow is missing or not verified.
- **Not evidenced** means no sufficient evidence was found in the current staging schema/source audit.
- **Test status** is tracked separately from implementation status. A READY Vercel build is not an end-to-end acceptance test.

### Snapshot from live staging — refreshed 2026-10-22
- Supabase staging project `higoadrzxnhzbbwhdbmh` (`dlice-staging`) is `ACTIVE_HEALTHY`, PostgreSQL 17.11, region `ap-southeast-1`. Production remains a separate environment and is out of scope for these changes.
- Live public schema inspection returns **41 tables** (the previous 39-table snapshot is stale). All 40 reported tables have RLS enabled. Domains represented include catalog/orders/payments, admin identity/audit, branches/job positions/assignments, POS shifts/sales, inventory/stock ledger, suppliers/PO/receipts, recipe/production, expenses, settlements/refunds, fiscal periods/journal entries, rate limits and funnel metrics.
- The live database exposes **15 public functions** including atomic checkout/reservation, POS sale creation, recipe activation, production completion/consumption, PO receiving, stock movement, settlement matching, payment verification and operational status changes. This proves database primitives exist, not that all workflows are connected or accepted.
- Branch status counts from live SQL: **150 planned, 4 active**. The 150 planned slots are not 150 operating branches; live active count is only four and should be reconciled with the intended HQ/test-fixture model before any operational-readiness claim.
- Key live row counts: orders 7; POS sales 0; inventory items 2; branch inventory 0; stock movements 0; purchase orders 0; production batches 0; finance journal entries 0. Empty operational ledgers mean schema coverage materially exceeds demonstrated workflow usage.
- Security: previous audit verified 27/27 internal ERP tables had restrictive deny policies and zero direct client SELECT grants. All 40 tables now report RLS enabled, but that alone does not prove every table's policies/grants are correct; the full direct-API negative test is still required.
- Supabase Security Advisor currently reports one warning: leaked-password protection disabled. Performance Advisor reports 67 unused-index notices; do not drop these without representative workload analysis.
- Live Edge Function `dlice-orders` is ACTIVE at version 35 with `verify_jwt=false`; its handler must therefore continue enforcing JWT/session and role/scope checks itself. Source uses exact configured origin allowlisting through `DLICE_ALLOWED_ORIGINS`, but the secret value itself is not readable/independently verified in this audit.
- Vercel Preview deployment for commit `02dd251faf43342ef5646a3eb04468349854c4a8` is **READY**. Stable branch alias: `https://dlice-landing-page-git-feat-fnb-os-stagin-f4a8a6-dlice8888-7332.vercel.app`. READY only proves deployment/build state; no browser flow or authenticated P0 runtime suite has passed yet.
- GitHub PR #24 (security/timezone changes) and PR #25 (audit and username-based P0 test harness) are both **OPEN, DRAFT, UNMERGED**. Quality checks on the latest PR #25 head are successful; the manual `staging-p0-smoke.yml` workflow has not been dispatched.
- The first Branch Operations slice is deployed in staging: checklist-run table is protected by RLS/restrictive deny policy, direct table SELECT is denied, and missing-session calls return 401. Authenticated branch-scope acceptance remains pending.
- P0 test harness now uses username/password variables matching D’Lice's `admin-login` model. Its required staging secrets and disposable test accounts still need to exist in GitHub Environment `staging`; do not put credentials or tokens in chat or source.
- Figma identity check reports a Starter plan and a **View** seat, with code layers disabled. No D’Lice Figma file URL/node was provided in the current request, and this chat does not expose the Product Design Work-mode browser capture workflow; therefore this is a tool-access assessment, not a screenshot-based UX audit or a claim that Figma was changed.

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
| 8 | Branch Operations | Branch directory/status, assignments, POS shift/cash reconciliation, and a new daily opening/closing checklist slice (migration + Edge Function v35 deployed to staging) | Partial (improved) | Checklist runtime with authenticated roles is not yet proven; configurable templates, task assignment, photo evidence, corrective actions, equipment maintenance and branch audits remain |
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
