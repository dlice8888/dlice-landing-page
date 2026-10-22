# D’Lice FnB OS — Full Staging Audit (2026-10-22)

## Executive result

- **Estimated existing staging capability: ~28% of the 18-domain blueprint.** This is an evidence-based scope estimate, not test coverage, completion percentage by LOC, or production-readiness certification.
- **No domain is certified complete.** 15 domains have partial implementation evidence; CRM & Loyalty, Franchise & Expansion, and SaaS Tenant Management have no sufficient implementation evidence.
- **Release posture: staging-only, not production-ready.** Do not merge to `main` or deploy production until the required end-to-end and security gates pass and the Owner explicitly approves.
- The stock-transfer/cycle-count slice is currently in draft PR #27 and is **not part of the existing staging runtime yet**. The opening/closing checklist slice is deployed to staging; its authenticated browser acceptance is still incomplete.

## Evidence sources checked

- GitHub repository: `dlice8888/dlice-landing-page`; default branch `main`.
- Latest P1 draft head at audit time: `feat/p1-stock-transfer-count-20261022`, commit `a0480d56998babc061c13c6990a146fb4ed5711a`.
- GitHub Actions: `Free quality checks` succeeded for that head; Vercel check succeeded.
- Supabase staging: `dlice-staging`, project `higoadrzxnhzbbwhdbmh`, status `ACTIVE_HEALTHY`.
- Supabase public schema: 41 tables returned; RLS enabled on all 41 in the current inventory.
- Latest applied migration: `20261021182634_branch_operation_checklists`.
- Edge Function `dlice-orders`: ACTIVE version 35; `verify_jwt=false`, with authentication expected to be enforced inside the function.
- Vercel deployment for the P1 branch: READY at https://dlice-landing-page-3n43pbhrx-dlice8888-7332.vercel.app ; Vercel status alone does not prove browser acceptance.
- Figma account: Starter plan with View seat; Code Layers disabled. No Figma file URL/key was provided to establish a visual target, and direct canvas edits cannot be assumed.
- Product Design screenshot-based audit is not complete in this standard chat context; the preview is protected by Vercel SSO and cannot be represented as visually audited from a READY status alone.

## Domain-by-domain capability matrix

| # | Domain | Existing staging evidence | Status / gap |
|---|---|---|---|
| 1 | Executive Command Center | Order/funnel data and operational records exist | **Partial** — no verified consolidated 150-branch KPI/alert/approval drill-down |
| 2 | POS & Checkout | Product catalog, checkout, payment records, shift/sales schema | **Partial** — no representative authenticated shift-to-close and payment reconciliation E2E |
| 3 | Order Management | Orders, items, reservations, status history and checkout guards | **Partial** — full multi-channel exception and fulfillment acceptance pending |
| 4 | Kitchen & Production | Recipes, production batches/consumptions schema and server actions | **Partial** — no verified KDS station workflow, quality gates and production reconciliation |
| 5 | Menu & Recipe Engineering | Products, recipes, ingredients, recipe activation | **Partial** — version distribution, effective dating, allergen and margin validation incomplete |
| 6 | Inventory & Warehouse | Inventory items, branch inventory and stock movement tables | **Partial** — operational stock data absent; transfer/count implementation is in draft PR #27, not applied to staging |
| 7 | Procurement & Supplier | Suppliers, purchase orders, receipts and receipt items | **Partial** — no representative PR→approval→PO→GRN→invoice/AP reconciliation |
| 8 | Branch Operations | Checklist-run table and checklist actions deployed | **Partial** — role/branch browser acceptance and operational escalation gates pending |
| 9 | Delivery & Fulfillment | Order fulfillment fields and queue logic | **Partial** — external courier booking, tracking, proof of delivery and cost reconciliation not verified |
| 10 | CRM & Loyalty | No sufficient customer/loyalty implementation evidence | **No evidence** — profiles, consent, points, campaigns and rewards need implementation |
| 11 | Finance & Accounting | Settlement, refund, cash reconciliation, tax, fiscal period and journal schemas/actions | **Partial** — finance tables are empty; balanced journals, AP/AR, bank reconciliation and branch P&L not proven |
| 12 | HR & Workforce | Job positions / basic workforce scaffolding | **Partial (limited)** — employees, schedules, attendance, leave, payroll integration and labor-cost reconciliation incomplete |
| 13 | Franchise & Expansion | No sufficient franchise lifecycle evidence | **No evidence** — agreements, site feasibility, royalties and compliance need implementation |
| 14 | BI & Analytics | Funnel metrics and operational source tables | **Partial** — formal KPI dictionary, forecasting, branch benchmarking and anomaly-to-action flow absent |
| 15 | Admin & Access Control | Roles/permissions, branch assignments, audit logs, restrictive RLS and server-side checks | **Partial** — branch assignments currently have no rows; role/scope E2E still required |
| 16 | SaaS Tenant Management | No sufficient tenant/subscription/entitlement isolation evidence | **No evidence** — tenant model, plans, metering, billing, support access and offboarding need implementation |
| 17 | Integrations & Automation | Payment/order functions, notification log and rate limiting | **Partial** — no full integration health/retry queue and end-to-end webhook idempotency proof |
| 18 | Quality, Compliance & Security | RLS across current tables, audit logs, rate limiting, branch timezone logic | **Partial** — food safety, traceability/recall, backup-restore drill, security test suite and leaked-password protection remain incomplete |

## Data and runtime facts

- Current public table inventory contains 41 tables, all with RLS enabled.
- Key operational tables currently show no representative business activity: `branch_assignments` (0), `branch_inventory` (0), `stock_movements` (0), `purchase_orders` (0), `purchase_receipts` (0), `pos_shifts` (0), `pos_sales` (0), `production_batches` (0), `payment_settlements` (0), `refund_records` (0), `cash_reconciliations` (0), `fiscal_periods` (0), and `finance_journal_entries` (0).
- Current inventory rows include 154 branch records. That count is not evidence that 150 branches are active, configured, assigned, or operationally ready.
- Security Advisor has previously identified leaked-password protection as disabled. Recheck and resolve before production.
- Performance Advisor has many unused-index notices on a low-activity staging workload. Do not drop indexes solely from that signal; assess representative query plans first.
- The draft stock-transfer/count migration `20261022121503_stock_transfers_and_counts.sql` is not included in the applied migration list yet.

## Phased readiness estimate

These are planning estimates based on the evidence above, not independently measured test coverage.

| Phase | Target | Current estimate | Acceptance status |
|---|---|---:|---|
| P0 | Tenant/branch foundation, auth, RLS, audit, payment/order states | 55% | **Not passed** — identity, branch/tenant negative tests and full browser acceptance incomplete |
| P1 | POS, order, payment, menu/recipe, KDS, inventory, procurement, shifts, fulfillment | 30% | **Not passed** — no full order→payment→production/fulfillment→stock→settlement reconciliation |
| P2 | Accounting, AP/AR, bank/settlement reconciliation, close, branch P&L, workforce/payroll | 20% | **Not passed** — key finance/workforce data and reconciliations unproven |
| P3 | Command center, KPI definitions, alerts/approvals, CRM, forecasting, delivery automation | 10% | **Not passed** — CRM/loyalty and predictive/alert workflows missing |
| P4 | SaaS tenant onboarding, plans, entitlements, metering/billing, support/offboarding, scale/recovery | 0% | **Not passed** — no proven multi-tenant commercial lifecycle or 150-branch load/restore evidence |

## Merge and branch strategy

The repository contains many historical and feature branches. The P1 branch is 218 commits ahead and 4 commits behind `main`, and several older branches are diverged from it. Blindly merging every branch into `main` would mix historical variants and risks conflict/regression. This audit therefore does **not** authorize merging all branches or promoting production.

Recommended integration strategy:
1. Treat the latest P1 branch as the current staging candidate and review each divergent branch for unique commits/files.
2. Integrate only non-duplicate changes into a dedicated staging integration branch, with conflict resolution and regression checks.
3. Reconcile database migrations against the actual staging migration history; apply new migrations in order only after SQL review.
4. Deploy the matching Edge Function and explicitly allowlist the exact Preview origin in staging CORS secrets.
5. Run authenticated Owner/manager/no-permission/inactive/wrong-branch tests and business-data reconciliation.
6. Keep PRs draft until their gates pass. Production remains untouched until explicit Owner approval.

## Required next implementation slices

1. **P0 release gate:** fix and verify type-check; confirm staging CORS allowlist; provision disposable staging identities via GitHub Environment secrets (never paste passwords into chat); execute anonymous, role, branch and tenant negative tests.
2. **P1:** apply the stock-transfer/count migration, deploy matching Edge Function to staging, then test idempotent ship/receive and count posting against ledger/balance invariants. Continue KDS and shift/cash control gaps.
3. **P2:** implement/verify balanced journal posting, COA, AP/AR, settlement/bank reconciliation, fiscal close, branch P&L and workforce/payroll interface.
4. **P3:** establish a versioned KPI dictionary, actionable alerts/approval center, CRM/loyalty, demand forecast and integration retry/idempotency controls.
5. **P4:** design tenant isolation before adding subscriptions, entitlements, usage/billing, support and offboarding; then run concurrency/load and backup/restore drills.

## Acceptance gate for 150 branches

Do not call the system ready until each is evidenced:
- Checkout/payment/refund/settlement end-to-end reconciliation.
- Recipe/theoretical stock/actual stock/waste/transfer/receiving reconciliation.
- Balanced finance journals and branch-to-group close reconciliation.
- Anonymous, no-permission, wrong-branch and cross-tenant negative access tests at API and database layers.
- Representative peak concurrency/load test with defined SLOs.
- Successful backup restore and documented recovery objective.
- Pilot branch operational SOP/training/support and rollback rehearsal.
- Owner-approved rollout only after pilot sign-off.
