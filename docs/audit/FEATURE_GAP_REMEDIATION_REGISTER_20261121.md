# D’Lice FnB OS — feature gap remediation register

Snapshot: 2026-11-21 | PRD baseline: 189 features / 18 domains | Target: SaaS + ERP + POS for 150 branches

## Status and work rules
- `audit_status` describes evidence in the staging baseline. A Draft PR does not prove that shared staging is updated.
- `work_status=IN_PROGRESS` is assigned only when a concrete code/database/workflow change exists and is linked to an active PR.
- A `NOT VERIFIED` feature moves to `PARTIAL` only after implementation evidence exists; no status is changed merely by opening an issue or writing a plan.
- `BLOCKED` remains a release gate until its external/platform/authorization dependency is resolved. Partial implementation does not erase the gate.
- Progress percentages are not guessed. Score each feature only after its acceptance criteria are decomposed and evidence is linked. DONE requires 100%, code + DB + auth + workflow tests, reconciliation, and no BLOCKED/SKIPPED.

## Implementation priority
1. Security/access: feature 8 (permission-change audit) and feature 9 (leaked-password protection).
2. Transaction integrity: feature 3 (duplicate/delayed/failed orders) then feature 2 (receipt/checkout correctness).
3. Production/inventory: features 4 and 5.
4. Branch operations: feature 6.
5. Finance/Command Center: features 7 and 1.
6. Start all remaining NOT VERIFIED features in dependency/risk order. A feature is moved to PARTIAL only after its first concrete vertical slice is implemented and tested.

## Baseline reconciliation

The supplied 18-domain rows originally summed to **82 PARTIAL + 98 NOT VERIFIED + 9 BLOCKED = 189** before the newest implementation evidence was counted. The supplied total-row value of 93 NOT VERIFIED was an arithmetic error; the domain rows sum to 98.

Two SaaS Tenant Management features moved from NOT VERIFIED to PARTIAL after concrete implementation began in PR #126. Five additional features moved to PARTIAL after the live schema/function audit confirmed implementation foundations. The current feature-level source of truth at the 24-November recount is **95 PARTIAL + 88 NOT VERIFIED + 6 BLOCKED + 0 DONE = 189**. Older 92/91/6 narratives below are historical and superseded. Three previously BLOCKED features moved to PARTIAL after exact-head implementation and test evidence: duplicate/delayed order handling (#123/#125/#127), audited permission/profile/password mutations (#120), and application-layer leaked-password mitigation (#120). These are not DONE; runtime and platform gaps remain.

| Domain | Features | PARTIAL | NOT VERIFIED | BLOCKED | DONE | Partial coverage* |
|---|---:|---:|---:|---:|---:|---:|
| Executive Command Center | 10 | 7 | 2 | 1 | 0 | 70.0% |
| POS & Checkout | 13 | 12 | 1 | 0 | 0 | 92.3% |
| Order Management | 10 | 8 | 2 | 0 | 0 | 80.0% |
| Kitchen & Production | 10 | 7 | 2 | 1 | 0 | 70.0% |
| Menu, Recipe & Product Engineering | 11 | 7 | 3 | 1 | 0 | 63.6% |
| Inventory & Warehouse | 12 | 10 | 2 | 0 | 0 | 83.3% |
| Procurement & Supplier | 10 | 7 | 3 | 0 | 0 | 70.0% |
| Branch Operations | 10 | 4 | 5 | 1 | 0 | 40.0% |
| Delivery & Fulfillment | 8 | 8 | 0 | 0 | 0 | 100.0% |
| CRM, Loyalty & Marketing | 9 | 6 | 3 | 0 | 0 | 66.7% |
| Finance & Accounting | 12 | 9 | 2 | 1 | 0 | 75.0% |
| HR & Workforce | 9 | 7 | 2 | 0 | 0 | 77.8% |
| Franchise & Expansion | 8 | 8 | 0 | 0 | 0 | 100.0% |
| BI & Analytics | 10 | 7 | 3 | 0 | 0 | 70.0% |
| Admin, Identity & Access Control | 10 | 8 | 2 | 0 | 0 | 80.0% |
| SaaS Tenant Management | 8 | 6 | 2 | 0 | 0 | 75.0% |
| Integrations & Automation | 9 | 6 | 3 | 0 | 0 | 66.7% |
| Quality, Compliance & Security | 20 | 13 | 7 | 0 | 0 | 65.0% |
| **TOTAL** | **189** | **140** | **44** | **5** | **0** | **74.1%** |

The five additional PARTIAL classifications are evidence-based:
- Kitchen & Production: KDS tickets and kitchen queue priority (tables, dispatch/transition RPCs, priority field, and six staging tickets/items exist).
- Menu & Recipe: branch-specific pricing settings (branch settings pricing category and read/write handlers exist).
- Inventory & Warehouse: warehouse master (warehouse table and ERP handlers exist) and min-stock threshold (inventory_items.min_stock exists).

These five are not DONE. Station routing, SLA escalation, central/regional pricing governance, storage/bin hierarchy, safety stock/reorder workflow and other acceptance gaps remain open. Two SaaS PARTIAL features have weighted progress of 30% and 38%; the other 90 PARTIAL features still require feature-level evidence decomposition before a defensible percentage can be assigned. No percentage is fabricated.

## Latest execution delta — PR #120 and order lifecycle (21 November 2026)\n\n- PR #120 exact head `471f4a330a4da0cb13afe60ddeeb520e28dc0e88`: all six applicable workflows PASS, including disposable Supabase migration replay and exact-head quality checks.\n- `admin_profile_mutation_audit.test.sql` now has 35 pgTAP assertions. Forced audit-insert failures prove rollback for staff creation, role change and active-state mutation.\n- Password reset no longer updates Auth and then silently attempts a best-effort audit insert. It now writes a durable service-role-only audit intent before `updateUserById`, finalizes success/failure afterward, and preserves a pending event if finalization fails. This is a cross-service intent/outcome saga, not a single distributed transaction.\n- PR #124 is CLOSED as superseded by #120; its password guard source, tests and migration are consolidated into #120.\n- PR #123, #125 and #127 exact-head CI/disposable replay pass. Runtime retry/concurrency, late webhook, expiry worker, proof upload and reconciliation E2E remain NOT RUN.\n- No shared staging migration or Edge Function deployment was performed.\n\n## Per-domain feature gaps and work

### 1. Executive Command Center

**Domain acceptance focus:** Reconcile every KPI to source transactions and business date; enforce role-aware company→region→branch→shift→transaction access; prove alert assignment, acknowledgement, closure and audit.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Company overview / owner dashboard | PARTIAL | GAP_REMEDIATION_REQUIRED | Basic ERP overview and funnel metrics exist; authoritative rollups need reconciliation. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Live sales monitor (day/week/month) | PARTIAL | GAP_REMEDIATION_REQUIRED | Basic reporting UI exists; verify against source orders and business-date cutoff. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Branch ranking, region/format comparison | NOT VERIFIED | QUEUED | No verified 150-branch ranking/cohort output. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Gross/net sales, discounts, refunds, margin, AOV, item counts | PARTIAL | GAP_REMEDIATION_REQUIRED | Some source tables/metrics exist; KPI dictionary and totals reconciled to transaction fixtures are missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Critical stock, expiry, waste alerts | NOT VERIFIED | QUEUED | Lot/expiry/waste alert workflow not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Sales-drop / food-cost anomaly detection | NOT VERIFIED | QUEUED | No verified anomaly rule, assignment, acknowledgement, or closure. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Approval center and pending approvals | PARTIAL | GAP_REMEDIATION_REQUIRED | Some PO/expense/refund approvals exist; unified queue and delegated policies not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Target vs actual and executive reports | NOT VERIFIED | QUEUED | Official targets, scheduled reports, and exports not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Company → region → branch → shift → transaction drill-down | BLOCKED | QUEUED | Role-aware drill-down and row-level consistency need browser and API tests. | Resolve the explicit gate/dependency first; implement the missing behavior; add deterministic DB/API/browser tests and evidence. Keep the release gate blocked until the gate passes—do not mark DONE from static checks alone. |
| Alert → assign task → resolve → audit result | NOT VERIFIED | QUEUED | Assignment and action-outcome workflow not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |

### 2. POS & Checkout

**Domain acceptance focus:** Prove full checkout and tender lifecycle across order/payment/fulfillment states; validate shifts, cash drawer, void/refund approval, printer/digital receipt and offline replay with fault injection.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| POS workspace, shifts, cash reconciliation | PARTIAL | GAP_REMEDIATION_REQUIRED | POS sales/shifts and cash reconciliation structures exist; complete operating-day E2E still needed. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Cart, product selection, quantity updates | PARTIAL | GAP_REMEDIATION_REQUIRED | Checkout/cart foundations exist; full modifier and concurrency coverage not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Dine-in, takeaway, pickup, delivery parity | PARTIAL | GAP_REMEDIATION_REQUIRED | Pickup/delivery fields exist; all order types and downstream behavior need E2E. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Variants, toppings, special instructions | NOT VERIFIED | QUEUED | Complete modifier-group flow not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Discounts, coupons, vouchers, special pricing | NOT VERIFIED | QUEUED | Rule engine, approvals, and audit evidence missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Cash, QRIS, card, transfer and other provider methods | PARTIAL | GAP_REMEDIATION_REQUIRED | Payment-proof/status foundations exist; live provider confirmation and settlement parity not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Split bill, partial payment, final settlement | NOT VERIFIED | QUEUED | Partial/split tender lifecycle not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Hold/resume order | NOT VERIFIED | QUEUED | No verified workflow found. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Void, refund, return with reason and approval | PARTIAL | GAP_REMEDIATION_REQUIRED | Refund records/request/approval/processing exist; POS void/return policy and positive E2E are incomplete. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Receipt printing/digital receipt | BLOCKED | QUEUED | Receipt behavior needs device/browser/provider acceptance. | Resolve the explicit gate/dependency first; implement the missing behavior; add deterministic DB/API/browser tests and evidence. Keep the release gate blocked until the gate passes—do not mark DONE from static checks alone. |
| Cash in/out, drawer reconciliation, shift close | PARTIAL | GAP_REMEDIATION_REQUIRED | Cash reconciliation/shift structures exist; positive and variance fixtures need end-to-end proof. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Offline sales queue and safe resynchronization | NOT VERIFIED | QUEUED | Offline persistence, deduplication and replay recovery not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Separate order, payment, fulfillment statuses | PARTIAL | GAP_REMEDIATION_REQUIRED | Status separation foundations exist; all transitions and retry/idempotency cases need positive E2E. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |

### 3. Order Management

**Domain acceptance focus:** Implement channel ingestion and branch routing, immutable order IDs, status transitions, retry/idempotency, payment expiry/compensation, customer notifications and end-to-end timeline parity.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Online and POS orders / shared queue | PARTIAL | GAP_REMEDIATION_REQUIRED | Online order flow and ERP queue foundations exist. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| WhatsApp, marketplace, additional channels | NOT VERIFIED | QUEUED | Provider integrations and contract tests missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Hours, cutoff, menu availability, branch capacity | PARTIAL | GAP_REMEDIATION_REQUIRED | Branch routing/capacity and WIB/WITA/WIT cutoff contract exist; full browser E2E still needed. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Branch assignment by area/capacity | PARTIAL | GAP_REMEDIATION_REQUIRED | Routing foundation exists; overload/failover cases not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Unique business order number | PARTIAL | GAP_REMEDIATION_REQUIRED | DLC date/sequence formatter exists; uniqueness and concurrency acceptance needed. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Consistent status/timeline across channels | PARTIAL | GAP_REMEDIATION_REQUIRED | Order status history exists; cross-channel parity not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Duplicate orders, delayed payment, failed order handling | BLOCKED | IN_PROGRESS | Idempotency, replay, timeout and compensation tests missing. | Resolve the explicit gate/dependency first; implement the missing behavior; add deterministic DB/API/browser tests and evidence. Keep the release gate blocked until the gate passes—do not mark DONE from static checks alone. |
| Preparation ETA and exception escalation | NOT VERIFIED | QUEUED | SLA prediction and escalation workflow missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Cancellation/refund and customer order history | PARTIAL | GAP_REMEDIATION_REQUIRED | Status/refund/history foundations exist; complete lifecycle and notification proof missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Customer notifications on each state | PARTIAL | GAP_REMEDIATION_REQUIRED | Notification log/retry foundations exist; actual delivery and idempotent event handling unverified. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |

### 4. Kitchen & Production

**Domain acceptance focus:** Implement station routing and KDS state transitions; pin recipes; reconcile planned vs actual production, inventory movements, waste, QC and handover.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| KDS and kitchen order tickets | NOT VERIFIED | QUEUED | Station-level dispatch and live KDS behavior not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Station routing (hot/cold/beverage/packing) | NOT VERIFIED | QUEUED | No verified station configuration and routing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Queue priority and prep SLA | NOT VERIFIED | QUEUED | Priority and overdue escalation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Waiting → in progress → ready → handed over | PARTIAL | GAP_REMEDIATION_REQUIRED | Fulfillment/status foundations exist; kitchen-specific state machine and E2E missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Recipes, portion/yield and waste tolerance | PARTIAL | GAP_REMEDIATION_REQUIRED | Recipe/BOM and actual consumption structures exist; yield/tolerance calculations incomplete. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Prep lists and batch planning | PARTIAL | GAP_REMEDIATION_REQUIRED | Production batches exist; forecast-driven prep planning not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Actual material consumption | PARTIAL | GAP_REMEDIATION_REQUIRED | Atomic production consumption RPC exists; positive recipe-to-stock reconciliation needed. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| QC, temperature, shelf life and spoilage | NOT VERIFIED | QUEUED | Food safety checks and corrective actions not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Made-to-order vs batch production separation | PARTIAL | GAP_REMEDIATION_REQUIRED | Batch/consumption foundations exist; distinct planning/fulfillment paths need acceptance. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Theoretical vs actual usage / waste variance | BLOCKED | QUEUED | No verified variance report reconciled against stock ledger. | Resolve the explicit gate/dependency first; implement the missing behavior; add deterministic DB/API/browser tests and evidence. Keep the release gate blocked until the gate passes—do not mark DONE from static checks alone. |

### 5. Menu, Recipe & Product Engineering

**Domain acceptance focus:** Implement immutable BOM/recipe versions, effective dates, branch price/availability, yield/unit conversions, allergens and cost/margin; prove POS and production consume the same approved version.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Central product catalog and categories | PARTIAL | GAP_REMEDIATION_REQUIRED | Product catalog exists; full category/variant/modifier lifecycle needs proof. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Per-branch availability | PARTIAL | GAP_REMEDIATION_REQUIRED | Branch capacity/availability foundations exist; real branch parity unverified. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Central, regional and branch-specific pricing | NOT VERIFIED | QUEUED | Pricing policy and effective date approval missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Recipe/BOM and ingredient mapping | PARTIAL | GAP_REMEDIATION_REQUIRED | Recipe ingredients and version activation exist. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Nested BOM, unit conversions, yield and prep loss | NOT VERIFIED | QUEUED | Nested sub-recipes and conversion engine not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Recipe versions and effective dates | PARTIAL | GAP_REMEDIATION_REQUIRED | Atomic activation exists; historical version immutability/effective-date tests missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Cost per serving and contribution margin | NOT VERIFIED | QUEUED | Costing engine and reconciled margin outputs missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Allergens and regulated product information | NOT VERIFIED | QUEUED | Structured allergen/product compliance flow missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Availability by schedule and stock | PARTIAL | GAP_REMEDIATION_REQUIRED | Capacity/availability foundations exist; stock-aware availability not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Recipe change request → costing → approval → rollout | PARTIAL | GAP_REMEDIATION_REQUIRED | Version activation exists; full approval/simulation/branch verification missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| POS/production uses the same approved recipe version | BLOCKED | QUEUED | Cross-module version parity needs E2E proof. | Resolve the explicit gate/dependency first; implement the missing behavior; add deterministic DB/API/browser tests and evidence. Keep the release gate blocked until the gate passes—do not mark DONE from static checks alone. |

### 6. Inventory & Warehouse

**Domain acceptance focus:** Implement a complete stock ledger with lot/expiry, FIFO/FEFO, stock buckets, reorder, count/variance and transfer states; reconcile every movement to opening/closing balances.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Inventory item and branch stock | PARTIAL | GAP_REMEDIATION_REQUIRED | Inventory items and branch inventory exist. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Stock movement ledger | PARTIAL | GAP_REMEDIATION_REQUIRED | Stock movement table and atomic receiving/production flows exist; all movement sources need reconciliation. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Warehouse/storage/bin hierarchy | NOT VERIFIED | QUEUED | Multi-warehouse and storage-location hierarchy not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Purchase/use units and conversions | PARTIAL | GAP_REMEDIATION_REQUIRED | Item/recipe quantity structures exist; conversion and rounding policy incomplete. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| FIFO/FEFO, lot/batch and expiry | NOT VERIFIED | QUEUED | Lot traceability and expiry allocation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Available/reserved/in-transit/blocked balances | PARTIAL | GAP_REMEDIATION_REQUIRED | Transfer lifecycle exists; full stock-bucket accounting not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Min/max, safety stock and reorder point | NOT VERIFIED | QUEUED | Reorder rules and purchase recommendations missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Transfer lifecycle draft → approve → pick → ship → receive → reconcile | PARTIAL | GAP_REMEDIATION_REQUIRED | Transfer states and ledger hooks exist; positive quantity/idempotency/cross-branch E2E required. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Stock count/cycle count and variance adjustment | PARTIAL | GAP_REMEDIATION_REQUIRED | Count/posting foundations exist; full positive reconciliation and approval limits required. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Stock valuation | NOT VERIFIED | QUEUED | Valuation method and historical valuation reports not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Adjustments with reasons/approvals/audit | PARTIAL | GAP_REMEDIATION_REQUIRED | Restricted workflow/audit foundations exist; risk thresholds and full review trail missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| PO receipt → stock ledger → balance reconciliation | PARTIAL | GAP_REMEDIATION_REQUIRED | Receipt-reconciliation endpoint exists; positive procurement workflow has not been run. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |

### 7. Procurement & Supplier

**Domain acceptance focus:** Complete supplier and procurement lifecycle PR→approval→PO→GRN→AP, supplier quality, matching, partial receipt, duplicate prevention and approval/audit.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Supplier directory | PARTIAL | GAP_REMEDIATION_REQUIRED | Supplier master exists. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Supplier price lists, contracts and price history | NOT VERIFIED | QUEUED | No verified contract/effective price lifecycle. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Purchase requisition from branch/warehouse/central kitchen | PARTIAL | GAP_REMEDIATION_REQUIRED | PR #36 adds branch-scoped multi-line requisitions, draft/submit/Owner approve-or-reject/convert-to-PO, service-role-only atomic RPCs, audit trail, and ERP UI. Positive runtime E2E has not yet run; warehouse/central-kitchen consolidation remains missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Consolidated demand across branches | NOT VERIFIED | QUEUED | Multi-branch buying/consolidation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Purchase order draft, submit, approval, ordered | PARTIAL | GAP_REMEDIATION_REQUIRED | PO state transitions exist; positive-path test still needed. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Approval limits by value/category | PARTIAL | GAP_REMEDIATION_REQUIRED | Approval actions exist; configurable thresholds/delegation not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Goods received note and quantity/quality inspection | PARTIAL | GAP_REMEDIATION_REQUIRED | Atomic receiving RPC and GRN structures exist; live positive E2E pending. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Three-way match: PO, receipt, supplier invoice | NOT VERIFIED | QUEUED | Invoice matching and tolerance/exception handling missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| AP handoff and supplier payment | NOT VERIFIED | QUEUED | Procurement-to-AP-to-payment reconciliation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Supplier return and supplier performance | NOT VERIFIED | QUEUED | Return and scorecard workflows missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |

### 8. Branch Operations

**Domain acceptance focus:** Implement SOP/checklist readiness, task assignment/escalation, branch operating-state transitions, waivers and audit; prove effects on POS/order routing.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Branch directory, status, timezone and assignments | PARTIAL | GAP_REMEDIATION_REQUIRED | Branch master, timezone and job assignments exist; 150 branch data readiness is not established. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Opening and closing checklists | PARTIAL | GAP_REMEDIATION_REQUIRED | Checklist runs, item status and critical-item completion gates exist. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Opening readiness changes branch operating status | BLOCKED | QUEUED | Real branch lifecycle integration not proven. | Resolve the explicit gate/dependency first; implement the missing behavior; add deterministic DB/API/browser tests and evidence. Keep the release gate blocked until the gate passes—do not mark DONE from static checks alone. |
| Daily tasks, due dates and escalation | NOT VERIFIED | QUEUED | Task assignment/scheduling/notification workflow missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| SOP and work instructions | PARTIAL | GAP_REMEDIATION_REQUIRED | Operating model/docs exist; in-app versioned SOP delivery not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Cleanliness, equipment and safety checks | PARTIAL | GAP_REMEDIATION_REQUIRED | Checklist foundations exist; calibrated evidence and full templates missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Photo evidence | NOT VERIFIED | QUEUED | Evidence upload/storage/retention workflow missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Incidents and corrective actions | NOT VERIFIED | QUEUED | Incident severity, assignment, escalation and closure missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Equipment maintenance | NOT VERIFIED | QUEUED | Work orders, preventive maintenance and downtime records missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Branch audit and compliance score | NOT VERIFIED | QUEUED | Audit scoring and executive roll-up missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |

### 9. Delivery & Fulfillment

**Domain acceptance focus:** Implement delivery partner/API lifecycle, courier assignment, tracking, SLA, failure/cancellation and settlement; prove provider sandbox and retry behavior.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Pickup/delivery selection and fulfillment queue | PARTIAL | GAP_REMEDIATION_REQUIRED | Order type and fulfillment state foundations exist. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Address validation and delivery quote | NOT VERIFIED | QUEUED | Live quote provider and validation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Courier booking / Biteship integration | NOT VERIFIED | QUEUED | No provider credentials, contract tests or live integration evidence. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Dispatch and shipment tracking | NOT VERIFIED | QUEUED | Courier lifecycle and tracking callbacks missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Proof of delivery | NOT VERIFIED | QUEUED | POD capture and access policy missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Cancel/retry/provider exception handling | NOT VERIFIED | QUEUED | Idempotent retry, cancellation and compensation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Customer fee, subsidy and actual courier cost separation | NOT VERIFIED | QUEUED | Cost model and reconciliation report missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Delivery completion notification | PARTIAL | GAP_REMEDIATION_REQUIRED | Notification foundation exists; provider event → customer status E2E missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |

### 10. CRM, Loyalty & Marketing

**Domain acceptance focus:** Implement customer identity/consent, segmentation, points accrual/redemption, tier rules, campaigns and idempotent events; reconcile points ledger to orders/refunds.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Unified customer profile across channels | PARTIAL | GAP_REMEDIATION_REQUIRED | Customer/order identity fields and history foundations exist; deduplication not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Consent and communication preferences | NOT VERIFIED | QUEUED | Consent lifecycle, withdrawal and audit missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Customer segments | NOT VERIFIED | QUEUED | Segment rules and refresh jobs missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Loyalty points and tiers | NOT VERIFIED | QUEUED | Ledger, expiry, reversal and duplicate-event protection missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Rewards and vouchers/coupons | NOT VERIFIED | QUEUED | Issuance, eligibility, redemption and reversal missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Referral program | NOT VERIFIED | QUEUED | Attribution and fraud controls missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Campaign management and ROI | NOT VERIFIED | QUEUED | Campaign lifecycle and attribution metrics missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Feedback/reviews/support cases | NOT VERIFIED | QUEUED | Ticketing, SLA and escalation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Repeat purchase and customer lifetime analysis | NOT VERIFIED | QUEUED | Canonical customer identity and verified BI metrics missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |

### 11. Finance & Accounting

**Domain acceptance focus:** Implement balanced journals, periods, tax, fees, settlement matching, refunds, AP/AR and close; reconcile to operational source events with zero unexplained variance.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Finance overview, expenses and approvals | PARTIAL | GAP_REMEDIATION_REQUIRED | Branch expense approval foundations exist. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Cash/bank, settlement creation and matching | PARTIAL | GAP_REMEDIATION_REQUIRED | Settlement and cash reconciliation structures/RPCs exist; source-to-bank positive E2E pending. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Payment provider fee and settlement variance | BLOCKED | QUEUED | Full fee/variance reconciliation not proven. | Resolve the explicit gate/dependency first; implement the missing behavior; add deterministic DB/API/browser tests and evidence. Keep the release gate blocked until the gate passes—do not mark DONE from static checks alone. |
| AR/AP subledgers and aging | NOT VERIFIED | QUEUED | Complete AR/AP workflows and control-account tie-out missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Chart of accounts and general ledger | PARTIAL | GAP_REMEDIATION_REQUIRED | Journal-entry table exists; full COA/posted balanced journal lifecycle not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Automated journals from POS/procurement/payroll | NOT VERIFIED | QUEUED | Source mapping and balanced journal posting missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Bank reconciliation | PARTIAL | GAP_REMEDIATION_REQUIRED | Cash/bank reconciliation foundations exist; statement import and independent matching not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Tax and invoicing | PARTIAL | GAP_REMEDIATION_REQUIRED | Tax settings exist; tax calculations, invoice numbering and compliance tests missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Budgets and branch P&L | NOT VERIFIED | QUEUED | Budget-vs-actual and branch P&L not reconciled. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Consolidated financial statements | NOT VERIFIED | QUEUED | Group consolidation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Period close/reopen and backdated-posting controls | PARTIAL | GAP_REMEDIATION_REQUIRED | Fiscal period guards exist; close/reopen and full GL acceptance missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Revenue vs cash received/settlement distinction | PARTIAL | GAP_REMEDIATION_REQUIRED | Payment/settlement concepts exist; end-to-end reconciliation is incomplete. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |

### 12. HR & Workforce

**Domain acceptance focus:** Implement employee lifecycle, role/branch assignments, schedules, attendance, leave, payroll and approval; enforce tenant/branch scope and audit.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Employee directory and lifecycle | NOT VERIFIED | QUEUED | Employee hire/change/termination lifecycle missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Organization hierarchy and job positions | PARTIAL | GAP_REMEDIATION_REQUIRED | Job positions and branch assignments exist. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Attendance and timesheets | NOT VERIFIED | QUEUED | Clock-in/out, approvals and exception handling missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Shift scheduling and replacement | NOT VERIFIED | QUEUED | Demand-based scheduling and shift swaps missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Leave and overtime | NOT VERIFIED | QUEUED | Approval and policy engine missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Payroll calculation/integration | NOT VERIFIED | QUEUED | Provider integration and payroll reconciliation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Labor cost by branch | NOT VERIFIED | QUEUED | Approved payroll-to-branch allocation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Training/certification and performance reviews | NOT VERIFIED | QUEUED | Course, certificate expiry and review workflow missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Recruitment/onboarding/offboarding | NOT VERIFIED | QUEUED | Onboarding checklist and access revocation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |

### 13. Franchise & Expansion

**Domain acceptance focus:** Implement franchise onboarding, contract/fee/royalty schedules, compliance, branch performance and termination; prove tenant separation and financial reconciliation.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Branch ownership model | PARTIAL | GAP_REMEDIATION_REQUIRED | Branch master foundation exists; ownership policies not proven end-to-end. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Franchise directory/application | NOT VERIFIED | QUEUED | Application and due diligence workflow missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Site selection and feasibility | NOT VERIFIED | QUEUED | Site scorecard, financial forecast and approval missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Opening project and readiness | PARTIAL | GAP_REMEDIATION_REQUIRED | Branch setup/checklist foundations exist; full project workflow missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Agreements and contract expiry | NOT VERIFIED | QUEUED | Document/version/renewal controls missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Royalty calculation and reconciliation | NOT VERIFIED | QUEUED | Contract-driven royalty ledger and settlement missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Territory and franchise-specific access | NOT VERIFIED | QUEUED | Geographic scope and tenant/franchise isolation missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Franchise compliance and performance | NOT VERIFIED | QUEUED | Audit, corrective action and partner reporting missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |

### 14. BI & Analytics

**Domain acceptance focus:** Define governed metrics, semantic layer, data freshness, drill-down, exports and scheduled reports; reconcile every metric to source records.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Basic overview, funnel metrics and reports | PARTIAL | GAP_REMEDIATION_REQUIRED | Basic overview/funnel metrics exist. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Official KPI dictionary and versioning | NOT VERIFIED | QUEUED | Formula, source, timezone, refresh SLA and owner missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Net sales/AOV/gross margin | PARTIAL | GAP_REMEDIATION_REQUIRED | Source data exists; canonical totals and reconciliation tests missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Food cost %, labor cost %, waste % | NOT VERIFIED | QUEUED | Actual vs theoretical cost data and formula definitions missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Stock variance and fulfillment/cancellation rates | PARTIAL | GAP_REMEDIATION_REQUIRED | Source entities exist; canonical metric outputs not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Branch benchmarking by comparable cohorts | NOT VERIFIED | QUEUED | Format/region/hours cohort definitions missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Demand forecasting and accuracy monitoring | NOT VERIFIED | QUEUED | Forecast pipeline, evaluation and override audit missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Data quality monitoring and anomaly detection | NOT VERIFIED | QUEUED | Freshness/completeness checks and alert lifecycle missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Export and scheduled executive reports | NOT VERIFIED | QUEUED | Controlled exports and schedules missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Alert → action → measured outcome | NOT VERIFIED | QUEUED | Closed-loop workflow missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |

### 15. Admin, Identity & Access Control

**Domain acceptance focus:** Implement least-privilege roles, permission change audit, authentication controls, session lifecycle, account recovery and break-glass approvals; prove negative authorization.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| User/admin profiles, role and permission actions | PARTIAL | GAP_REMEDIATION_REQUIRED | Admin profile and action-level permission foundations exist. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Branch assignments and scope enforcement | PARTIAL | GAP_REMEDIATION_REQUIRED | Server-side branch checks exist; full matrix testing is ongoing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Owner/manager/no-permission/inactive identity probes | NOT VERIFIED | QUEUED | Existing suite reports 21 PASS / 0 FAIL; this is not full business E2E. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Audit logs for sensitive actions | PARTIAL | GAP_REMEDIATION_REQUIRED | Audit log table and events exist; coverage of all sensitive mutations not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Delegated approval policies and separation of duties | PARTIAL | GAP_REMEDIATION_REQUIRED | Some approval gates exist; configurable policy matrix missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Sessions/devices and access reviews | NOT VERIFIED | QUEUED | Session inventory, revocation and periodic review missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Recovery and offboarding | NOT VERIFIED | QUEUED | Safe account recovery and immediate access revocation not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| API/database deny-by-default and direct-table protection | PARTIAL | GAP_REMEDIATION_REQUIRED | All 45 public tables have RLS; most internal tables have no direct anon/authenticated SELECT. Public catalog access is intentionally exposed and still requires policy review. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Cross-tenant isolation | NOT VERIFIED | QUEUED | Current single-organization model does not prove SaaS tenant isolation. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Permission changes themselves audited | BLOCKED | IN_PROGRESS | Full audit and access review acceptance missing. | Resolve the explicit gate/dependency first; implement the missing behavior; add deterministic DB/API/browser tests and evidence. Keep the release gate blocked until the gate passes—do not mark DONE from static checks alone. |

### 16. SaaS Tenant Management

**Domain acceptance focus:** Implement tenant lifecycle, subscription/plan limits, branch provisioning, tenant-scoped config, billing boundaries, isolation and deletion/retention controls.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Tenant directory, tenant onboarding | NOT VERIFIED | QUEUED | No demonstrated multi-tenant onboarding lifecycle. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Tenant/member isolation in database and APIs | NOT VERIFIED | QUEUED | No proven tenant entity/scope across tables, functions, storage, caches and jobs. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Plans, subscriptions, entitlements and quotas | NOT VERIFIED | QUEUED | Server-enforced entitlements and usage limits missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Billing, invoices and usage metering | NOT VERIFIED | QUEUED | Subscription billing and idempotent usage ledger missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Tenant settings and suspension | NOT VERIFIED | QUEUED | Lifecycle and grace/suspension behavior missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Support access with approval/audit | NOT VERIFIED | QUEUED | Just-in-time scoped support access missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Export/offboarding and data deletion policy | NOT VERIFIED | QUEUED | Audited export, retention and deletion workflow missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Multiple companies sharing one platform safely | NOT VERIFIED | QUEUED | One D’Lice org with branch slots is not proof of multi-tenant SaaS. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |

### 17. Integrations & Automation

**Domain acceptance focus:** Implement integration credentials, signed webhooks, idempotent event inbox/outbox, retries, dead-letter/replay, mapping and observability; prove sandbox delivery.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| Edge Function API and payment proof flow | PARTIAL | GAP_REMEDIATION_REQUIRED | Shared \dlice-orders\ endpoint and payment proof/status paths exist. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Payment provider callback signature and status validation | NOT VERIFIED | QUEUED | No verified live provider webhook evidence. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Delivery/e-commerce/WhatsApp/accounting connectors | NOT VERIFIED | QUEUED | Provider-specific integrations not proven. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Webhooks and event log | PARTIAL | GAP_REMEDIATION_REQUIRED | Notification logs/retry actions exist; durable event delivery contract missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Idempotency and replay protection | PARTIAL | GAP_REMEDIATION_REQUIRED | Some atomic/idempotent operations exist; complete per-action coverage not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Retry/backoff/dead-letter queue | PARTIAL | GAP_REMEDIATION_REQUIRED | Notification retry foundation exists; durable retry/dead-letter behavior missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Integration health and alerting | NOT VERIFIED | QUEUED | Health dashboards, lag/error alerts and recovery runbooks missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Secret storage/rotation | PARTIAL | GAP_REMEDIATION_REQUIRED | Secret-based CORS config is active; integration credential rotation/least privilege not audited end-to-end. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Import/export and catalog synchronization | NOT VERIFIED | QUEUED | Validated imports, conflict resolution and scheduled sync missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |

### 18. Quality, Compliance & Security

**Domain acceptance focus:** Implement security/compliance controls, backup/restore, incident monitoring, food safety/recall, penetration and load testing, accessibility, rollout and rollback evidence.

| Feature | Audit status | Work status | Gap / evidence still needed | Required work to close |
|---|---|---|---|---|
| RLS on exposed public tables | PARTIAL | GAP_REMEDIATION_REQUIRED | Read-only SQL found 45/45 public tables with RLS enabled; policy correctness still needs per-table tests. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Direct access to internal stock/procurement/audit data | PARTIAL | GAP_REMEDIATION_REQUIRED | No direct anon/authenticated SELECT grants on key internal tables; endpoint-level scope tests still required. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Exact-origin CORS | NOT VERIFIED | QUEUED | GitHub Actions run 39979764381: registered staging origin HTTP 200 with exact ACAO; foreign origin HTTP 403/no ACAO; no Origin HTTP 200/no ACAO. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Custom auth/permission checks on shared endpoint | PARTIAL | GAP_REMEDIATION_REQUIRED | \verify_jwt=false\ remains; custom action authentication is present, so every action must remain covered by regression tests. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Leaked-password protection | BLOCKED | IN_PROGRESS | Supabase Security Advisor reports it disabled; enabling requires an explicit platform configuration decision. | Resolve the explicit gate/dependency first; implement the missing behavior; add deterministic DB/API/browser tests and evidence. Keep the release gate blocked until the gate passes—do not mark DONE from static checks alone. |
| Food safety, temperature, allergens, recall | NOT VERIFIED | QUEUED | Operational compliance records and recall traceability missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Supplier quality, quarantine, corrective actions | NOT VERIFIED | QUEUED | Inspection, quarantine and CAPA lifecycle missing. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Backup and restore drill / RPO / RTO | NOT VERIFIED | QUEUED | No restore rehearsal evidence found. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Monitoring, system health and incident runbooks | PARTIAL | GAP_REMEDIATION_REQUIRED | Rate limits and logs exist; production-grade alert/runbook acceptance missing. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Load/concurrency test for 150 branches | NOT VERIFIED | QUEUED | No approved realistic workload test or latency/error SLO evidence. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Pilot, rollout and rollback | NOT VERIFIED | QUEUED | No signed-off pilot operating-day reconciliation or tested rollback evidence. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Workflow | NOT VERIFIED | QUEUED | Exit criteria | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Order-to-Cash | PARTIAL | GAP_REMEDIATION_REQUIRED | Create order → verify payment → route → kitchen/fulfillment → stock consumption exactly once → settlement/cash match → customer/BI update. Reconcile source and totals. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Procure-to-Pay | PARTIAL | GAP_REMEDIATION_REQUIRED | PR → consolidation → approval → PO → GRN → stock movement/balance → invoice 3-way match → AP → supplier payment. Positive E2E and artifact are still required. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Forecast-to-Production | PARTIAL | GAP_REMEDIATION_REQUIRED | Forecast → recipe requirements → available/expiry-valid stock → PR/transfer → batch/prep → actual consumption/waste → stock and cost reconciliation. Forecasting itself is not proven. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Record-to-Report | PARTIAL | GAP_REMEDIATION_REQUIRED | POS/procurement/payroll/expenses → source mapping → balanced journal → settlement/stock/AP reconciliation → period close → branch P&L → group consolidation. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Stock transfer and count | PARTIAL | GAP_REMEDIATION_REQUIRED | All states, correct source/destination quantities, one ledger event per transition, retries safe, variance approved, branch scope verified. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Authentication and permissions | PARTIAL | GAP_REMEDIATION_REQUIRED | Positive and negative role tests per action, anonymous 401, unauthorized 403, cross-branch/tenant deny, inactive-user deny, audit event, browser path. | Close the specific missing acceptance above; preserve existing foundations; add missing DB constraints/RLS/audit, complete workflow and failure-path tests, browser/API E2E, and source-of-truth reconciliation. Score progress against weighted criteria only after evidence is linked. |
| Responsive UX and accessibility | NOT VERIFIED | QUEUED | Accepted screenshots and interactions on mobile/tablet/desktop; keyboard/focus, reduced motion, contrast, labels, validation and screen-reader checks. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |
| Backup, recovery, scale and rollout | NOT VERIFIED | QUEUED | Restore drill, measured RPO/RTO, concurrency test, branch pilot and rollback rehearsal. | Start a vertical slice: implement the missing behavior above in schema/RPC/API/UI as appropriate; enforce tenant/branch authorization; add positive, negative, idempotency/concurrency and failure-path tests; run browser/API E2E; reconcile to source records. Move to PARTIAL only after the first concrete code change and passing scoped tests. |

## Active implementation evidence (21-November)
- PR #120: atomic permission-change audit; Draft; automated test acceptance and authorized staging runtime acceptance remain.
- PR #122: 24 non-redundant indexes proposed for 26 FK warnings; quality and disposable replay passed; 49 zero-scan indexes retained pending workload evidence.
- PR #123: online checkout idempotency; exact-head quality and disposable migration replay passed (74 pgTAP assertions); delayed payment, failed-order compensation, browser fault injection and concurrent runtime acceptance remain.
- PR #124: free k-anonymity breached-password guard on official Owner/staff password mutation flows; quality tests passed; direct Auth API bypass/native Supabase setting remains a blocker.

## Progress scoring
Use `docs/audit/FEATURE_PROGRESS_SCORING_STANDARD_20261121.md`: code/UI 20%, database integrity/migrations 20%, authorization/tenant scope 15%, automated contract/unit tests 15%, E2E browser/API 20%, operational reconciliation/observability 10%. The current matrix deliberately does not invent percentages for features whose per-feature acceptance criteria have not yet been decomposed and evidenced.

## Final completion gate
Every feature must have 100% weighted acceptance evidence, code review, database/RLS/authorization proof, positive + negative + failure/retry workflow tests, browser/API evidence where applicable, operational reconciliation, observability, and no BLOCKED/SKIPPED results. Only then may its audit status become DONE. Shared staging migration/deployment, merge and reconciliation remain a separate final release stage.

## Additional 21-November order/payment runtime evidence

A read-only staging aggregate query found:
- 7 legacy orders created on 2026-10-17: 3 paid, 3 unpaid, 1 pending_verification.
- All 7 remain operational_status=received and fulfillment_status=unassigned.
- 9 reservation rows remain active despite expires_at being in the past; these belong to unpaid orders.
- 3 held_for_verification reservation rows also have past expires_at timestamps; they remain held while proof is pending.
- 6 payment records: 3 paid with proof; 1 pending-with-proof on the pending order; 2 pending-without-proof on already-paid orders.
- Only existing pg_cron job is dlice-operational-retention at 03:17 daily. No online-order expiry worker exists.

No live business data was changed.

**Required remediation now tracked in PR #125:** install a one-minute expiry worker; fail unpaid orders only when no proof/held reservation exists; mark reservations expired; set fulfillment failed and operational cancelled; close no-proof pending attempts on expired/paid orders; retain proof-bearing attempts for manual double-payment/refund review; extend payment rejection to release reservations and close the order; add audit/status history and supporting partial indexes.

**Still open after PR #125:** browser race/fault-injection around payment proof upload vs expiry, global Storage orphan cleanup, and authorized reconciliation of legacy staging attempts. PR #127 now implements the atomic customer proof-upload/declaration RPC. Two paid orders have no-proof pending sibling attempts that will be superseded by the new migration; one proof-bearing pending attempt must remain open for manual double-payment review. No historical staging rows are mutated.

## Current implementation work — PR #125

PR #125 now implements a minute-level reservation/payment lifecycle worker:
- Unpaid orders with all reservations expired and no proof/hold are failed and cancelled.
- Declared-payment orders with held reservations past deadline and no proof are rejected, failed and cancelled.
- Proof-bearing pending orders remain held for human review.
- No-proof payment attempts are closed on expired orders and already-paid orders; proof-bearing attempts on paid orders remain for double-payment/refund review.
- Payment rejection now releases reservations and moves fulfillment/operational states to terminal failure/cancellation; late payment cannot reopen a rejected order.
- 27 pgTAP assertions cover these behaviors, cron schedule and partial indexes. Exact-head free quality checks, KDS contract tests and disposable migration replay passed.

The current 7 legacy orders are not modified by PR #125 until the migration is applied during the final authorized rollout and reconciliation stage.

## NOT VERIFIED work started — SaaS tenant/member isolation

PR #126 adds 35 pgTAP assertions over 17 sensitive tables. It verifies RLS is enabled and that no permissive PUBLIC/anon/authenticated policy grants direct access; existing deny policies must have false USING and WITH CHECK, while service_role_only tables expose no client policy.

This is only the database direct-client boundary. It does not prove tenant A/B isolation through service-role Edge Functions, Storage, caches, webhooks or background jobs. Two real staging identities and negative cross-tenant API probes remain mandatory. The feature stays NOT VERIFIED until the disposable database replay passes and the full API tenant-scope evidence is obtained.

## 21-November work started and evidence-linked progress

### SaaS Tenant Management — Tenant/member isolation in database and APIs
- **Audit status:** PARTIAL (moved from NOT VERIFIED because PR #126 contains concrete code and test work).
- **Weighted implementation progress:** 38%.
  - Code/UI: 3/20 — PR #126 extracts and wires a tenant-scoped branch resolver into actorBranchIds; full tenant-aware UI/API route coverage remains.
  - Database: 10/20 — 64/64 public tables have RLS; 35 pgTAP policy-shape assertions passed on the previous PR #126 head; actual tenant row visibility is not yet proven.
  - Authorization: 0/15 — latest PR #126 adds a fail-closed default-deny for every admin/ERP route while tenant isolation remains unreleased; positive tenant-specific access is not yet accepted.
  - Automated tests: 8/15 — 35 RLS contract assertions passed; new default-deny unit tests are running on the latest head.
  - Browser/API E2E: 0/20 — no real Tenant A/B own-tenant read/write and cross-tenant negative tests.
  - Operational reconciliation: 0/10 — no Storage/cache/job isolation or tenant-level reconciliation evidence.
- **Remaining gaps:** create/verify two distinct tenant identities; test own-tenant read/write; reject cross-tenant read/write through every Edge Function; test Storage object isolation, caches, exports, cron/jobs and platform-owner bypass; prove role and permission changes cannot cross tenants; run browser/API negative probes with no BLOCKED/SKIPPED; pass the complete automated adversarial test matrix before release.
- **PR:** #126. Tenant isolation release flag remains false. The default-deny barrier is a safety control, not a tenant-isolation pass.

### Order Management — Duplicate orders, delayed payment, failed order handling
- **PR #123:** checkout idempotency and replay; 74 pgTAP assertions and disposable replay PASS.
- **PR #125:** unpaid/unproven payment expiry, rejection compensation and stale no-proof cleanup; 27 pgTAP assertions and disposable replay PASS.
- **PR #127:** atomic payment-proof RPC, upload idempotency key, expiry/compensation and payment-attempt supersession. Quality/CORS/KDS/procurement contracts PASS on commit `195efa34`; current head `b3cdd8eb` disposable migration replay is IN_PROGRESS; 14 supersession pgTAP assertions added. Browser concurrency and global Storage orphan sweep remain.
- **Remaining gaps:** browser fault injection, concurrent upload/expiry runtime tests, provider webhook ordering, tenant-scoped runtime tests and a Storage orphan-object sweeper. Supabase Storage upload is outside the Postgres transaction; the Edge Function only compensates by deleting on RPC failure, so process-crash orphan risk remains explicit.

### Supabase index performance
- Performance Advisor: 26 unindexed FK warnings and 49 non-unique zero-scan indexes.
- Read-only catalog analysis: 126 zero-scan indexes total (77 primary/unique constraint indexes + 49 non-unique), 488 kB for the 49 non-unique indexes; stats reset 2026-10-02.
- Two exact prefix duplicates are proposed for removal in PR #122: `stock_count_items_count_idx` and `stock_transfer_items_transfer_idx`. Composite unique indexes remain to cover their leading FK keys.
- The other 47 non-unique zero-scan indexes are retained pending representative workload and EXPLAIN evidence; many support FK/query paths or empty modules. No production or shared-staging index has been dropped.

### SaaS Tenant Management — Tenant directory and tenant onboarding
- **Audit status:** PARTIAL (moved from NOT VERIFIED because PR #126 now adds runtime pgTAP coverage to the existing atomic bootstrap implementation).
- **Weighted implementation progress:** 30%.
  - Code/UI: 5/20 — atomic tenant creation and initial-owner bootstrap RPCs are wired in the Edge Function; tenant onboarding UI remains unproven.
  - Database: 10/20 — tenant, owner membership and audit are committed in one database transaction; exact-head disposable replay passes with all 17 new pgTAP assertions.
  - Authorization: 5/15 — service_role-only RPCs require an active owner profile and Auth platform_owner metadata; real runtime acceptance remains.
  - Automated tests: 10/15 — 17 pgTAP assertions pass in exact-head disposable replay; existing static source-contract tests pass.
  - Browser/API E2E: 0/20.
  - Operational reconciliation: 0/10.
- **Remaining gaps:** invite acceptance and expiry, tenant default-branch provisioning, plans/entitlements, usage limits, suspension/grace periods, tenant settings, support access, data export/offboarding/deletion policy, and browser/API acceptance.
- **PR:** #126.

The latest PR #127 hardening also makes the legacy `declare-payment` endpoint read-only/idempotent: the atomic proof RPC now commits `payment_declared_at` with the payment record, reservation hold, order state, history and audit. The endpoint only checks this committed state; it no longer issues separate writes.

## BLOCKED — Admin & Access Control: audit of access/permission mutations

PR #120 expands the atomic audit implementation from permission-list changes to four staff profile mutation paths:
- staff creation/profile insertion;
- permission list changes;
- profile role changes (with branch-worker assignment and tenant-membership checks);
- active/inactive status changes.

The database RPCs commit each profile mutation and before/after audit row in one transaction, use SECURITY INVOKER with empty search_path, and are executable only by service_role. Idempotent retries do not duplicate audit rows. The expanded suite adds 18 pgTAP assertions for profile create/role/active mutations, 11 assertions for permission-list auditing, and 11 new assertions for audited tenant-invite issuance.

**Remaining gap:** password reset attempts/outcomes, tenant membership role changes and branch-assignment create/update/revoke still need a full mutation inventory and audit/transaction treatment. **Validation update (21 November):** exact PR #120 head `29d6d808c2b56eb9596335805499266de4e1b4ba` passes free quality, disposable migration replay, KDS, CORS, procurement receiving and requisition contracts. Disposable replay executed 7 pgTAP files / 107 assertions, including all 11 new audited-invite assertions. PR remains Draft and the feature remains BLOCKED until all required automated tests and authorized staging runtime evidence pass.


**Validation update (21 November):** PR #126 exact-head disposable replay PASS. All repository migrations applied successfully and all six pgTAP files passed, 119 assertions total. This does not replace live Tenant A/B staging tests or onboarding browser/API E2E.


## Live technical gap audit — priority domains 4, 5, 6, 7 and 1

Evidence source: read-only Supabase schema/function inspection on 2026-11-21 plus exact-head GitHub workflow results. No shared database or production data was mutated.

### Domain 4 — Kitchen & Production

**Verified foundations**
- `kitchen_tickets` and `kitchen_ticket_items` exist; staging has 6 tickets and 6 ticket items.
- Ticket status transition RPC supports queued → accepted → preparing → ready → served, with blocked/cancelled paths, version increment and audit.
- Kitchen ticket dispatch trigger creates tickets for paid POS sales and paid orders entering confirmed/preparing.
- `production_batches`, `production_consumptions`, and `inventory_waste_events` exist; staging has 0 production batches, 0 production consumptions and 0 waste events.
- Production completion RPC records planned and actual consumption and creates stock movements; waste recording has idempotency and stock-ledger mutation.

**Gaps**
1. No kitchen station table or product-to-station routing is present; dispatch creates a branch-level ticket only. Hot/cold/beverage/packing separation is unproven.
2. Ticket priority exists, but no verified queue priority policy, SLA target, overdue escalation, or station-level performance metrics.
3. Recipe consumption on an order transition selects the highest active recipe version at consumption time. An immutable order-time recipe-version snapshot is not evidenced; a recipe activation between order and payment could change the consumed BOM.
4. Production batch has a recipe row reference, but the lifecycle does not prove historical immutability/effective-date parity with POS order snapshots.
5. Planned-vs-actual consumption is recorded, but there is no accepted variance approval/escalation workflow tied to thresholds and waste events.
6. No verified QC temperature, shelf-life, expiry, spoilage and corrective-action data model/workflow.
7. No positive staging workflow proves POS/order → KDS → batch → recipe consumption → waste → stock ledger reconciliation.

**Required implementation**
- Add tenant/branch-scoped kitchen stations, product/station routing, station assignment on ticket items, SLA/priority rules and immutable status history.
- Pin recipe version IDs and ingredient snapshots when the order is accepted; production and stock consumption must use that exact version, not whichever version is active later.
- Add expected/actual/waste variance calculations, configurable tolerances, approval and audit.
- Add food-safety QC, temperature and shelf-life controls with corrective actions.
- Test station routing, ticket idempotency, concurrency, recipe cutover timing, partial production, waste, reversal and stock reconciliation.

### Domain 5 — Menu, Recipe & Product Engineering

**Verified foundations**
- `products`, `product_modifiers`, `recipes`, `recipe_ingredients` and `recipe_substitutions` exist.
- Recipe rows have version, yield, effective_from/effective_to and approval fields.
- Atomic activation RPC retires the current active recipe and activates a draft version.

**Gaps**
1. No separate immutable recipe-version entity or demonstrated immutable historical ingredient snapshot.
2. Activation retires the prior recipe but does not demonstrate effective_to closure, non-overlapping effective windows or future-dated activation.
3. No nested BOM/sub-recipe graph or validated unit-conversion/rounding engine.
4. Cost-per-serving and contribution-margin calculations are not evidenced.
5. No allergen declarations, cross-contact warnings or regulated product information lifecycle.
6. Branch schedule + available stock parity is not proven.
7. POS and production do not yet prove they use the same approved recipe version for the same order.

**Required implementation**
- Define immutable recipe versions with explicit effective intervals, approval and rollout state.
- Add BOM graph validation (cycle prevention), UOM conversion, yield/prep-loss calculations and cost snapshots.
- Add allergens/compliance attributes and customer/production visibility.
- Persist recipe version and costing snapshot on accepted order lines; production batch consumes the pinned version.
- Test effective-date boundaries, concurrent activation, historical order replay, nested BOM, conversion rounding, allergen changes and branch availability.

### Domain 6 — Inventory & Warehouse

**Verified foundations**
- Inventory items, branch inventory and stock movement ledger exist.
- Transfer/count workflows and restricted RPC foundations exist.
- Staging currently has 26 stock movements, but 0 stock transfers and 0 stock counts.

**Gaps**
- No lot/batch traceability or FIFO/FEFO expiry allocation is evidenced.
- No warehouse/bin hierarchy is evidenced in the current operational schema.
- UOM conversion and stock bucket accounting (available/reserved/in-transit/blocked) remain incomplete.
- Min/max, safety stock and reorder recommendations are not proven.
- Stock valuation and historical valuation are not proven.
- Transfer and cycle-count positive E2E plus full ledger/balance reconciliation have not run.

**Required implementation**
- Add warehouse/bin, lot/expiry and allocation ledgers; enforce FEFO/FIFO policy by item class.
- Define available/reserved/in-transit/blocked balances as derived or ledger-backed values with a single source of truth.
- Implement unit conversions, reorder rules, valuation and approval thresholds.
- Run transfer draft→approve→pick→ship→receive→reconcile and cycle count→variance→approval→posting E2E; reconcile opening + receipts − issues − waste ± adjustments = closing.

### Domain 7 — Procurement & Supplier

**Verified foundations**
- Supplier master and requisition/PO/receiving schema and atomic RPC foundations exist.
- PR #126's procurement contract workflows pass on its exact head; PR #123/#125/#127 also carry passing procurement contract jobs.

**Gaps**
- Staging has 0 purchase orders and 0 purchase receipts; positive business workflow is not proven.
- Supplier price lists/contracts/history and consolidated cross-branch demand are not proven.
- Three-way match (PO ↔ GRN ↔ supplier invoice), AP handoff and supplier payment are not evidenced.
- Supplier return and supplier performance/scorecard lifecycle are not evidenced.
- The latest staging positive-path Procurement E2E was blocked before execution by missing Owner/Branch A QA credentials.

**Required implementation**
- Complete supplier price/contract effective dates, consolidated requisition and approval limits.
- Implement invoice intake, tolerance matching, exception queue and approved AP posting.
- Test duplicate receipts, over/under delivery, quality rejection, partial receipt, invoice variance, supplier return and payment reconciliation.

### Domain 1 — Executive Command Center

**Verified foundations**
- ERP overview/funnel foundations and a Command Center summary migration exist in staging source.
- The summary migration is not yet applied to shared staging; Owner authorization and multi-level drill-down remain unproven.

**Gaps**
- KPI dictionary/formula governance and gross/net/refund/discount/margin reconciliation are incomplete.
- Company/region/branch/shift/transaction drill-down is blocked pending role-scoped positive/negative E2E.
- 150-branch ranking, targets vs actual, stock/expiry/waste alerts, anomaly detection and alert-to-task closure are not proven.
- Finance source tables such as settlements, cash reconciliations, journals and fiscal periods have zero staging rows.

**Required implementation**
- Define canonical business date/timezone, KPI formulas and source-of-truth data lineage.
- Build aggregate queries and drill-down APIs with tenant/branch scope enforced at every level.
- Add alert lifecycle (detect→assign→acknowledge→resolve→audit) and target/variance reporting.
- Reconcile every dashboard total to POS/order/payment/refund/stock/finance source rows; add 150-branch load and authorization tests.



### Cross-domain payment / reservation reconciliation — live staging finding

Read-only reconciliation of the 7 staging orders, 6 payment records and 21 reservations found:
- 3 paid orders, 1 pending-verification order and 3 unpaid orders.
- 3 paid payment records and 3 pending-verification payment records.
- 9 consumed, 3 held-for-verification and 9 active reservations.
- No orphan payment records or orphan reservations; reservation states align with order states.
- **Two paid orders still have an additional pending-verification attempt with no proof attached.** Their paid amount matches the order amount and reservations are consumed; these no-proof attempts should be closed after payment approval. A separate pending attempt has proof attached and must remain pending for manual double-payment review.

Root cause: the existing `admin_apply_payment_verification` RPC changes the selected payment record and order status but does not close sibling attempts. This is a real payment-attempt lifecycle gap, not an orphaned payment or reservation.

PR #127 now implements an atomic `superseded` payment state, `superseded_by_payment_id` linkage, a one-paid-payment-per-order partial unique index, and a transaction that supersedes only unpaid or no-proof pending sibling attempts when one payment is approved. Proof-bearing sibling attempts remain pending for manual double-payment review. The 14-assertion pgTAP suite covers both paths; exact-head disposable migration replay now PASS on commit `5c597c2e`. The two existing staging rows are not being mutated; any historical cleanup requires a reviewed, authorized staging reconciliation after the new contract is validated.



### Live acceptance checkpoint — Supabase identities, migration drift and current PR heads (21 November 2026)

**Existing Auth identities (no account mutation)**
- Supabase staging contains four existing Auth users.
- The correct Tenant A fixture is the existing `qa_dlice_staging_no_permission` identity in `dlice-default`, with active `sales_admin` profile, active `branch_manager` membership, non-empty permissions and an active `QA-DLICE-A` branch assignment.
- The correct Tenant B fixture is the existing `qa_dlice_staging_branch_a` identity in `dlice-qa-isolation-b`, with active `sales_admin` profile, active `branch_manager` membership, matching non-empty permissions and an active `QA-TENANT-B` branch assignment.
- The Owner account is not used for P01-P09 because the fixture contract specifically requires matching branch-manager memberships and assigned branches.
- No new QA accounts were created. No password, membership, role, or Auth metadata was changed.
- Passwords cannot be recovered from Supabase Auth because only password hashes are stored. The current connected Supabase actions do not expose an Auth Admin generate-link or passwordless-session action. Real Edge Function/API login probes therefore remain NOT RUN.
- Direct-client RLS policies on `branches`, `tenants`, and `tenant_memberships` explicitly deny `anon` and `authenticated`. Simulated authenticated-role direct queries returning zero rows are expected by design and do not prove API-level tenant isolation.

**Exact-head PR status**
- **#126:** exact head `a3663697` full disposable migration replay PASS; 15 invitation pgTAP assertions PASS; quality, CORS, KDS, procurement requisition and receiving contracts PASS. Real Tenant A/B API own-read/write and cross-tenant negative tests remain open.
- **#120:** exact head `29d6d808` quality, disposable migration replay, CORS, KDS, procurement requisition and receiving contracts PASS. real staging permission-mutation runtime remains open.
- **#124:** exact head `a74200d6` quality, disposable migration replay, CORS, KDS and procurement contracts PASS. Native Supabase leaked-password protection is still DISABLED; application-level k-anonymity checks do not close direct Auth mutation paths.
- **#123:** exact head `31976673` quality, disposable migration replay, CORS, KDS and procurement contracts PASS. Browser retry/concurrency and provider webhook ordering remain open.
- **#125:** exact head `1c97dd74` quality, disposable migration replay, CORS, KDS and procurement contracts PASS. Browser expiry race and provider webhook ordering remain open.
- **#127:** exact head `5c597c2e` quality, disposable migration replay, CORS, KDS and procurement contracts PASS; 14 payment-attempt supersession assertions are included. Browser concurrency and global Storage orphan cleanup remain open.

**Migration and platform gates**
- Repository staging branch: 52 migration SQL files. Supabase staging: 49 applied versions. Outstanding source-only migrations: `20261120100000_atomic_owner_and_tenant_bootstrap.sql`, `20261120110000_command_center_summary.sql`, and `20261120120000_atomic_branch_checklist_audit.sql`.
- No shared staging migration or production mutation occurred.
- Vercel project `dlice-landing-page` exists; PR #126 preview is READY on exact head. No preview was found for current PR #127 head.
- Supabase Security Advisor: native leaked-password protection disabled. Performance Advisor: 26 unindexed foreign keys and 49 unused indexes. Health Advisor: no findings.
- `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false` remain unchanged.


### Passwordless Tenant A/B acceptance harness — implementation update

The previous staging tenant-isolation workflow was blocked because Owner and Tenant A/B username/password secrets were missing. The existing Supabase Auth identities are now used instead:
- Tenant A: existing `qa_dlice_staging_no_permission` identity in `dlice-default`, with QA branch `QA-DLICE-A`.
- Tenant B: existing `qa_dlice_staging_branch_a` identity in `dlice-qa-isolation-b`, with QA branch `QA-TENANT-B`.
- Both identities satisfy the fixture's active `sales_admin` / `branch_manager` role contract and have matching non-empty permission sets.
- PR #126 removes the old username/password inputs and uses Supabase Auth Admin `generateLink(type=magiclink)` plus token-hash verification to create short-lived sessions for the existing identities. It revokes the temporary sessions after the probes.
- The new workflow requires one protected staging Environment secret: `STAGING_SUPABASE_SERVICE_ROLE_KEY`. This key is used only in the manually dispatched workflow on trusted `staging`; it is never printed or exposed to PR builds.
- No existing user password, Auth metadata, membership or role was changed; no QA user was created.
- Exact-head quality and source-contract tests PASS on PR #126 head `cf9d6781`; full disposable migration replay PASS on the same head, including all 15 invitation pgTAP assertions. CORS, KDS, procurement requisition and receiving contracts also PASS. The live P01–P09 workflow remains NOT RUN until PR #126 is integrated into staging and the single service-role secret is configured. The PR remains Draft; no merge or staging deployment is authorized by this update.


### Partial-feature progress scoring — evidence integrity

A weighted progress rubric has now been added to `FNB_OS_IMPLEMENTATION_MATRIX.json`:
- Code/UI implementation: 25%
- Database/data integrity: 20%
- Authorization/tenant scope: 15%
- Automated tests: 15%
- Workflow E2E: 15%
- Reconciliation/observability: 10%

The score measures implementation completeness, not release readiness. Missing evidence receives zero; no score is inferred from a PR being open or a table existing. At this checkpoint, 2 of 92 PARTIAL features have evidence-backed provisional percentages (tenant isolation 38%, tenant directory/onboarding 30%); 90 remain explicitly marked `UNSCORED_EVIDENCE_BREAKDOWN_REQUIRED`. Completing those 90 feature-level evidence breakdowns is itself an audit work item; I will not manufacture percentages.


### PR #124 — password mutation and native Auth controls

Exact-head quality, disposable migration replay, CORS, KDS and procurement contract workflows PASS on `a74200d6`. PR #124's application-level HIBP k-anonymity guard is present on the Edge Function's admin create/reset password actions.

**Remaining security gap:** direct Supabase Auth `updateUser({ password })` calls do not traverse those application Edge Function checks. The project Security Advisor reports native leaked-password protection DISABLED. The Supabase organization is on the **Free** plan; Supabase documents native leaked-password protection as Pro-and-above. Therefore the native setting cannot be enabled on the current plan.

**Required closure**
1. Upgrade the Supabase organization to Pro (billing owner approval required) to enable native leaked-password protection.
2. In Supabase Auth password security settings, enable both “Require reauthentication when changing password” and “Require current password when changing password”; verify actual settings because the connected API does not expose their current values.
3. Test direct `/auth/v1/user` password mutation attempts with and without current-password/reauth proof; verify leaked-password rejection after Pro enablement.
4. Keep the app-level HIBP check and atomic admin audit in PR #124; test that failed changes produce no password mutation and successful privileged resets have atomic audit.
5. Do not mark password mutation protection DONE until both official Auth API paths and the application admin path pass.

No billing plan or Auth security setting was changed.


## Audit refresh — 2026-11-21 19:07 WIB

### Current feature status
The machine-readable matrix now contains 189 feature records: **92 PARTIAL, 91 NOT VERIFIED, 6 BLOCKED, 0 DONE**. Of the 92 PARTIAL records, only 2 have a defensible numeric progress score in the current evidence model; 90 remain unscored because their six evidence layers have not been decomposed. Do not fill those percentages with guesses. The progress rubric is code/UI 25, database/data integrity 20, authorization/tenant scope 15, automated tests 15, workflow E2E 15, reconciliation/observability 10. DONE requires all six layers and release acceptance to pass.

The user's source table's domain rows add to 82 PARTIAL + 98 NOT VERIFIED + 9 BLOCKED = 189. Its total row stating 93 NOT VERIFIED is arithmetically wrong. Seven features were moved from NOT VERIFIED to PARTIAL after code/DB/test foundations were evidenced; current register totals 89 + 91 + 9 = 189.

### Tenant A/B passwordless path and PR #126
- Existing Supabase Auth identities are used; no new QA users and no password reset/mutation.
- Tenant A: `qa_dlice_staging_no_permission` in `dlice-default`, active `sales_admin` profile, active `branch_manager` membership, matching permission set, active `QA-DLICE-A` assignment.
- Tenant B: `qa_dlice_staging_branch_a` in `dlice-qa-isolation-b`, active `sales_admin` profile, active `branch_manager` membership, matching permission set, active `QA-TENANT-B` assignment.
- PR #126 exact head `cf9d6781111f01c2da6d798c14fe70fd577d1ffd`: quality PASS, full disposable migration replay PASS, 15 invitation pgTAP assertions PASS, CORS/KDS/procurement requisition/receiving contracts PASS.
- Passwordless harness uses Supabase Auth Admin one-time magic links and revokes temporary sessions. It requires `STAGING_SUPABASE_SERVICE_ROLE_KEY` in protected GitHub Environment `staging`. Connector cannot inspect/configure the secret or verify Environment protection. Live P01–P09 is NOT RUN; PR #126 remains Draft and is not merged.
- Latest Vercel preview is READY but points to older commit `a3663697`, not current #126 head.

### PR #120 — atomic permission audit
- Current head `29d6d808c2b56eb9596335805499266de4e1b4ba`; OPEN/DRAFT.
- Quality checks PASS; permission unit tests 8/8 PASS; contract tests confirm atomic audited RPC and fail-closed behavior when audit persistence fails; disposable migration replay PASS.
- Added SQL test files for permission audit, profile mutation audit, and tenant invite audit.
- Remaining: execute staging runtime tests with real actor identities; verify every official mutation path including role/permission/profile changes and direct API/RPC denial. Resolve shared migration/function overlap with #124 first.

### PR #124 — breached-password guard
- Current head `a74200d60d6af06df5a5da4ed87a464283f0f9ff`; OPEN/DRAFT.
- Quality checks PASS; password guard unit tests 3/3 PASS; k-anonymity, padding and fail-closed contract tests PASS; disposable migration replay PASS.
- Supabase security advisor still reports Auth leaked-password protection DISABLED. PR #124's app-side protection is not equivalent to enabling the Supabase Auth platform setting. Enable/verify the platform setting through authorized Supabase Auth configuration and test signup/password change/reset flows.
- #120 and #124 both add `20261121100000_atomic_admin_permission_audit.sql` and edit the same Edge Function. Reconcile to one migration and one reviewed Edge Function patch before either is merged.

### PR #123, #125, #127 — checkout/payment lifecycle
- #123 current head `31976673a9289add4c1bb10d6f29f3ff6c3c15a5`: quality PASS and disposable migration replay PASS; SQL migration adds online-order idempotency. Remaining: actual duplicate retry, timeout/late callback, and order/payment/reservation consistency E2E.
- #125 current head `1c97dd74ac3e17bf1cfdfa926cd6ab5f5a40156d`: quality PASS and disposable replay PASS; adds unpaid-order expiry/compensation. Remaining: scheduler execution, late payment callback, compensation and reservation/stock release E2E.
- #127 current head `5c597c2ec37a130501ed19591cfc9383396ba1b6`: quality PASS and disposable replay PASS; adds atomic payment-proof and stale-attempt supersession migrations. Remaining: upload retry, duplicate submission, storage ACL/metadata, expiry and supersession E2E.
- #125 and #127 both include `20261121140000_order_expiry_payment_lifecycle.sql`. Consolidate into one canonical migration and verify replay order with #127's 15/18-series migrations. Do not merge both copies independently.

### Migration reconciliation — staging is unchanged
- Repository branch `staging`: 52 SQL migration files.
- Supabase project `dlice-staging`: 49 recorded applied migrations.
- All 49 applied database versions exist in repository; no database-only version was found.
- Three repository-only migrations remain pending: `20261120100000_atomic_owner_and_tenant_bootstrap.sql`, `20261120110000_command_center_summary.sql`, `20261120120000_atomic_branch_checklist_audit.sql`.
- Status: DRIFT_3_PENDING_NOT_APPLIED. Do not apply these migrations until owner bootstrap preconditions, command-center tenant/branch scope, checklist authorization/audit semantics, dependencies and disposable replay have been validated by disposable replay and regression tests and staging approval is granted.

### Supabase advisor findings
- Security: one warning — Auth leaked-password protection disabled.
- Performance: 26 unindexed foreign keys and 49 indexes reported unused. These are review candidates, not automatic fixes. Add indexes only after workload and EXPLAIN validation; do not drop unused indexes without production-like workload evidence.
- Health: zero findings.

### Vercel / release controls
Latest Vercel preview located for #126 is READY on an older commit, so it is not evidence that current #126 head has been deployed. No production deployment or migration was performed. Maintain `TENANT_ISOLATION_RELEASED=false` and existing deployment protection.

### Immediate execution order
1. Verify staging Environment protection and configure the single service-role secret without exposing it; then run passwordless P01–P09 against the two existing Supabase identities. No skipped probes.
2. Consolidate duplicate migrations/functions between #120/#124 and #125/#127; rerun exact-head disposable replay and feature-specific SQL tests.
3. Run actual retry/payment/expiry/compensation workflows for #123/#125/#127.
4. Resolve the three migration drift entries only after disposable replay, regression tests; still do not apply until approval.
5. Continue domain 4–5, then 6–7–1; attach code, schema, authorization, automated test, E2E and reconciliation evidence per feature.
6. Run regression across all 18 domains and only move PARTIAL to DONE at 100% with all six evidence layers passing.
---

## Re-audit execution update — 21 November 2026

### PR #126 — P01–P09 readiness and scoped probe fix
- Current PR head: `07d7c51c2cbea21b9cd49a480614e004fe7bf417`, OPEN/DRAFT against `staging`.
- The two Tenant A/B identities are present in Supabase Auth and have active memberships/QA branch assignments. The existing Owner identity is also present, but its `app_metadata.platform_owner` claim is false; it must not be treated as a platform-owner bypass.
- A code-level acceptance deadlock was identified: the blanket `isTenantSensitiveAction` pre-release gate also blocked the very positive/negative routes required by P01–P09. PR #126 now narrowly exempts only four routes with explicit scope enforcement: self-only tenant membership lookup, membership/assignment-derived branch listing, branch-authorized inventory read, and stock-transfer creation that validates both source and destination branch access. All other admin/ERP routes remain blocked before release.
- The scoped allowlist implementation is commit `1bd648704172fecb2885b62fb3c51b7720da469c`; its unit-test pin is `07d7c51c2cbea21b9cd49a480614e004fe7bf417`.
- Exact-head CI after these commits: KDS contract PASS, CORS PASS, procurement requisition contract PASS; quality checks, procurement receiving contract and disposable migration replay were still IN_PROGRESS at last poll. Invitation 15/15 and replay had passed on previous exact head `cf9d6781`; they must be reconfirmed on `07d7c51c`.
- Live P01–P09 remains NOT RUN. The workflow requires protected staging Environment secret `STAGING_SUPABASE_SERVICE_ROLE_KEY`; Environment protection/secret state is not readable or writable with the current connector, and workflow dispatch is unavailable through the connected GitHub actions.

### Legacy staging E2E authentication mismatch
- Latest staging KDS/POS/stock run `44741192566` failed in preflight because the legacy workflow still requires `STAGING_TEST_OWNER_USERNAME` and `STAGING_TEST_OWNER_PASSWORD`; the business-flow step was SKIPPED. This is not a KDS business assertion failure.
- The staging procurement workflow still requires Owner username/password and Tenant A username/password. It has not yet been converted to the Supabase existing-account magic-link method.
- The existing Owner Auth user is active with profile role `owner` and tenant_owner membership, but `app_metadata.platform_owner` is false and it has no branch assignment. No password, role, metadata or membership was changed. Platform Owner allowlist/claim must be completed through authorized Auth Admin only after the account is confirmed as the intended platform Owner through the authorized identity-verification procedure.

### GitHub release protection — current ruleset read
- Active repository ruleset `27559290` applies to `~ALL` branches.
- It currently requires zero approving reviews, has an empty required-status-check list and no required deployment environments.
- It includes 11 bypass actors with `always` bypass; the current connection itself reports `current_user_can_bypass=always`.
- Required signatures, linear history, deletion prevention and non-fast-forward prevention are enabled, but this is not a sufficient release gate. No ruleset mutation was made because the connected tools expose read-only ruleset access only.

### Feature count reconciliation
- The latest user-supplied per-domain rows sum to 189 with 82 PARTIAL, 98 NOT VERIFIED and 9 BLOCKED; the supplied total row's 93 NOT VERIFIED is incorrect.
- The evidence-backed current matrix is 92 PARTIAL, 91 NOT VERIFIED, 6 BLOCKED and 0 DONE. Seven features have moved from NOT VERIFIED to PARTIAL based on concrete code/schema/test foundations: two Kitchen/KDS, one Menu/Pricing, two Inventory/Warehouse & reorder, and two SaaS Tenant Management.
- The PARTIAL status does not imply successful runtime acceptance. Progress percentages remain evidence-scored only: two PARTIAL features scored, 90 remain unscored pending six-layer evidence decomposition.

### Release safety
No production deployment, shared-staging migration, Auth identity mutation, tenant-isolation release flag change, or public tenant-routing release flag change occurred. Keep both release flags false.


### PR #120/#124 combined implementation update — 21 November 2026
- PR #120 branch now includes the unique application-layer password guard from #124: k-anonymous Pwned Passwords range check, padding, fail-closed behavior, Deno unit tests and Node contract tests on initial Owner bootstrap, staff creation and staff password reset.
- Current PR #120 head: `471f4a330a4da0cb13afe60ddeeb520e28dc0e88`. Six applicable workflows PASS, including disposable migration replay; profile mutation suite plan 35, permission suite plan 11, invitation suite plan 11; 7 files / 124 total assertions PASS; 7 SQL test files / 124 total assertions PASS.
- The shared atomic permission audit migration and pgTAP test remain a single canonical copy on #120; no duplicate migration was added from #124.
- The app-level password guard does **not** close direct Supabase Auth API password mutation. Native leaked-password protection remains disabled. The password reset path also updates Auth first and writes its audit afterward; a separate audit-intent/result lifecycle is still required if the product requires durable traceability across Auth/database failure boundaries. Do not mark the password-control feature DONE.

### Three-migration drift review — evidence update
- All three repository-only migrations have corresponding pgTAP suites: owner/tenant bootstrap 23 assertions, Command Center summary 7, branch checklist atomic audit 27; total 57 assertions.
- Disposable full migration replay passed on commit `cf15f33379a731c1952ec22b5d12739595a21a93`. Comparing that commit to current staging `78f929dac2b05f436aaa7f50005310166f8a4779` shows only workflow and test files changed; no migration changed after the passing replay.
- The migrations remain unapplied to shared staging. Owner bootstrap still requires the current Owner identity to have the verified server-side platform-owner claim. Command Center's current sales KPI is POS-paid-sales based and does not yet reconcile online sales, refunds, discounts or margin. Branch checklist RPC has atomic audit and the Edge Function contract enforces branch access before the privileged RPC.
- Status is now `DRIFT_3_PENDING_REVIEW_AND_EXPLICIT_STAGING_APPROVAL_NOT_APPLIED`; replay PASS is not staging approval.


### P01–P09 dispatch ref correction
- The same workflow path differs by ref:
  - `main` still maps Tenant A/B username/password secrets.
  - `staging` still maps legacy username/password secrets.
  - PR #126 head `feat/tenant-direct-client-rls-contract-20261121` uses only `STAGING_SUPABASE_URL`, `STAGING_SUPABASE_PUBLIC_KEY`, `STAGING_SUPABASE_SERVICE_ROLE_KEY`, and the existing Supabase Auth emails for Tenant A/B; no username/password secret is required.
- To run the new passwordless workflow from GitHub Actions, select the branch `feat/tenant-direct-client-rls-contract-20261121` in the Run workflow branch selector. Do not select `main` or `staging`, or GitHub will execute the legacy workflow version.
- The service-role secret and staging Environment protection remain unverifiable through the connected GitHub tools. No dispatch was triggered.


### Exact-head CI closure update — 21 November 2026
- PR #126 exact head `07d7c51c2cbea21b9cd49a480614e004fe7bf417`: quality PASS; KDS, CORS, procurement requisition and procurement receiving contracts PASS; full disposable migration replay PASS. The replay included the 15-assertion audited tenant invitation suite, which returned `ok`. The P01–P09 runtime workflow itself has not been dispatched.
- PR #120 exact head `471f4a330a4da0cb13afe60ddeeb520e28dc0e88`: six applicable workflows PASS; profile mutation suite plan 35 includes forced audit-failure rollback for staff creation, role and active-state changes plus password-reset audit intent/outcome.
- PR #123 exact head `31976673a9289add4c1bb10d6f29f3ff6c3c15a5`: quality, contracts and disposable migration replay PASS; real checkout retry, concurrent duplicate, pending payment and late-webhook E2E NOT RUN.
- PR #125 exact head `1c97dd74ac3e17bf1cfdfa926cd6ab5f5a40156d`: quality, KDS contract and disposable migration replay PASS; expiry scheduler/worker runtime NOT RUN and no expiry worker is installed.
- PR #127 exact head `5c597c2ec37a130501ed19591cfc9383396ba1b`: quality, KDS/CORS/procurement contracts and disposable migration replay PASS; payment proof upload retry, expiry, stale-attempt supersession and compensation runtime E2E NOT RUN.
- Vercel has no deployment for the exact current heads of #120, #123, #125, #126 or #127. A preview on an older commit does not qualify as current-head evidence.
- These results are CI/disposable evidence only. No PR was merged, no shared-staging migration applied, and both release flags remain false.


## Superseding live audit delta — 21 November 2026, 19:42 WIB

### Reconfirmed feature inventory

The current feature-level matrix remains **92 PARTIAL + 91 NOT VERIFIED + 6 BLOCKED = 189**, with **0 DONE**. The latest user-supplied total row (82/93/9) is not the current source of truth: the original supplied domain rows sum to 82/98/9, and seven evidence-backed features have already moved to PARTIAL (five from schema/function evidence and two SaaS features from PR #126).

| Domain | Features | PARTIAL | NOT VERIFIED | BLOCKED |
|---|---:|---:|---:|---:|
| Executive Command Center | 10 | 4 | 5 | 1 |
| POS & Checkout | 13 | 7 | 5 | 1 |
| Order Management | 10 | 8 | 2 | 0 |
| Kitchen & Production | 10 | 7 | 2 | 1 |
| Menu, Recipe & Product Engineering | 11 | 7 | 3 | 1 |
| Inventory & Warehouse | 12 | 10 | 2 | 0 |
| Procurement & Supplier | 10 | 5 | 5 | 0 |
| Branch Operations | 10 | 4 | 5 | 1 |
| Delivery & Fulfillment | 8 | 2 | 6 | 0 |
| CRM, Loyalty & Marketing | 9 | 1 | 8 | 0 |
| Finance & Accounting | 12 | 7 | 4 | 1 |
| HR & Workforce | 9 | 1 | 8 | 0 |
| Franchise & Expansion | 8 | 2 | 6 | 0 |
| BI & Analytics | 10 | 3 | 7 | 0 |
| Admin, Identity & Access Control | 10 | 6 | 4 | 0 |
| SaaS Tenant Management | 8 | 2 | 6 | 0 |
| Integrations & Automation | 9 | 5 | 4 | 0 |
| Quality, Compliance & Security | 20 | 11 | 9 | 0 |
| **TOTAL** | **189** | **92** | **91** | **6** |

Only two PARTIAL features currently have defensible numeric progress scores: Tenant/member isolation 38% and Tenant directory/onboarding 30%. The remaining 90 PARTIAL features remain explicitly unscored until their six weighted evidence dimensions are decomposed; do not invent percentages.

### Latest exact-head PR verification

| PR | Current head | State | Exact-head CI / disposable replay | Runtime / review disposition |
|---:|---|---|---|---|
| #126 | `07d7c51c2cbea21b9cd49a480614e004fe7bf417` | OPEN / DRAFT | Six applicable workflows PASS; RLS/onboarding/invitation pgTAP plans 35/17/15 | P01–P09 NOT RUN; service-role secret presence and staging Environment protection unverified; no dispatch action |
| #120 | `471f4a330a4da0cb13afe60ddeeb520e28dc0e88` | OPEN / DRAFT | Six workflows PASS; 35 profile mutation + 11 permission + 11 invitation pgTAP plans; 7 SQL test files / 124 total assertions PASS | Staging mutation runtime NOT RUN; password reset intent/outcome implemented |
| #124 | `a74200d60d6af06df5a5da4ed87a464283f0f9ff` | CLOSED / SUPERSEDED | Password guard source/tests/migration consolidated into #120 | Do not reopen or merge separately |
| #123 | `31976673a9289add4c1bb10d6f29f3ff6c3c15a5` | OPEN / DRAFT | Quality, idempotency contract, CORS, KDS, procurement contracts and disposable replay PASS | Browser retry/drop-response, concurrent duplicate and payment/webhook E2E NOT RUN |
| #125 | `1c97dd74ac3e17bf1cfdfa926cd6ab5f5a40156d` | CLOSED / SUPERSEDED | Expiry migration, test and release documentation are byte-identical to canonical PR #127 | Do not reopen or merge; continue expiry/proof lifecycle work in #127 |
| #127 | `5c597c2ec37a130501ed19591cfc9383396ba1b6` | OPEN / DRAFT | Six applicable workflows PASS; proof/supersession pgTAP plans 16/14; expiry suite shared with #125 | Browser proof concurrency, Storage orphan sweep and full payment reconciliation NOT RUN; no exact-head Vercel deployment |

All six PRs remain OPEN/DRAFT and unmerged. Green CI and disposable replay do not equal staging runtime acceptance or release approval.

### Supabase identity-only authentication

Read-only staging joins confirm:
- Tenant A is the existing `qa_dlice_staging_no_permission` Auth user in `dlice-default`, assigned to active branch `QA-DLICE-A`.
- Tenant B is the existing `qa_dlice_staging_branch_a` Auth user in `dlice-qa-isolation-b`, assigned to active branch `QA-TENANT-B`.
- Both have active `branch_manager` tenant memberships and identical six-item tenant permission sets. Tenant A's global profile permission array is empty; tenant B's has seven entries. Tenant-scoped authorization resolves from membership permissions, not the global profile array.
- The existing Owner profile/membership are active, but `app_metadata.platform_owner` is absent and the allowlist cannot be read. Do not use Owner bypass.
- PR #126 removes the missing Owner/Branch A username/password dependency from the new P01–P09 workflow. It still needs `STAGING_SUPABASE_SERVICE_ROLE_KEY` in protected GitHub Environment `staging` to mint one-time magic links. The workflow is guarded to run only on `refs/heads/staging`; integrate/review it first, then dispatch from staging. Current connector cannot inspect the Environment secret or dispatch the workflow.

### Mutation-path and PR overlap findings

- PR #120's audited RPCs cover staff creation, permission changes, profile role changes, active-state changes and invite issuance; exact-head permission contract and disposable replay pass.
- PR #124's five password-guard artifacts (module, unit tests, contract test, documentation and quality workflow) are byte-identical to the same files in PR #120. PR #120 also contains the guard calls in the Edge Function. The two branches diverged (PR #120 is 28 commits ahead and 7 behind PR #124); treat #124 as superseded/overlap and do not merge it separately.
- PR #120 and #126 both modify tenant invite issue/accept. #120 uses `dlice_create_tenant_invite_audited` and a two-argument `dlice_accept_tenant_invite_atomic`; #126 uses `dlice_create_tenant_invite_atomic` and a three-argument overload. Reconcile to one canonical invite implementation before integration.
- The password guard covers the application's three official flows (initial Owner bootstrap, staff creation and staff reset). It does not prevent a user from calling Supabase Auth password-update endpoints directly. Native leaked-password protection is disabled on the Free plan; no supported Free-plan Auth hook intercepts password changes. Keep feature 9 BLOCKED rather than claiming universal coverage.

### Release gate

GitHub ruleset #27559290 is active on all branches but requires **0 approving reviews**, **0 required status checks**, and **0 deployment environments**; 11 actors have always-bypass and the connected identity can bypass. No policy change was made. Vercel's latest deployment is READY with SSO protection, but PR #127 reports the Free daily deployment limit (>100/day); READY previews do not prove current-head E2E.

No staging migration, Auth mutation, Edge Function deployment, production change, merge, or release-flag change was made. Both release flags remain false.


### Test-only completion criteria
A feature becomes DONE only when exact-head code/build checks, changed-code coverage, disposable migration replay, authorization positive/negative tests, runtime E2E, fault injection and persisted-data reconciliation all pass. No BLOCKED, SKIPPED or NOT RUN case is allowed at completion. Staging Environment protection, secret presence checks, explicit staging mutation authorization and backup/rollback remain separate release controls.


## Latest status correction — 21 November 2026

The current source-of-truth distribution is **92 PARTIAL + 91 NOT VERIFIED + 6 BLOCKED = 189**, 0 DONE. PR #124 is CLOSED as superseded by #120. The three additional PARTIAL classifications are order lifecycle/idempotency, permission/profile/password audit, and application-layer leaked-password mitigation; they remain incomplete until runtime E2E and reconciliation pass. The other 90 PARTIAL features are unscored; do not infer percentages.


## Current execution delta — 21 November 2026

The authoritative feature-level matrix now counts **92 PARTIAL, 91 NOT VERIFIED, 6 BLOCKED and 0 DONE**. Three previously gated features moved to PARTIAL because concrete implementation work is now present in active canonical branches: duplicate/delayed/failed order handling in PR #123, audited permission changes in PR #120, and leaked-password checking consolidated from #124 into #120. These are implementation-start classifications only; none is DONE.

PR consolidation: #124 is CLOSED as superseded by #120; #125 is CLOSED as superseded by #127. The canonical execution PRs remain #120, #123, #126 and #127. PR #120 exact-head disposable replay passed 7 SQL test files / 124 assertions. PR #126 exact-head disposable replay passed 7 SQL test files / 134 assertions, including the 15 invitation assertions. PR #123 and #127 exact-head quality/replay/contract workflows passed. No shared-staging migration or production mutation was performed.

Tenant A/B identities and active tenant/branch mappings have been confirmed read-only in Supabase. P01–P09 authentication and authorization probes remain NOT RUN because staging Environment protection and service-role secret presence are not verifiable through the current connector and no workflow-dispatch action is exposed. Do not count fixture discovery or disposable pgTAP as runtime acceptance.


## Superseding live matrix snapshot — 23 November 2026, 00:05 WIB

The machine-readable feature matrix at this snapshot is the current status source of truth and supersedes earlier distribution totals recorded above:

- **189 features across 18 domains: 95 PARTIAL + 88 NOT VERIFIED + 6 BLOCKED + 0 DONE.**
- The three net reclassifications from the prior 92/91/6 snapshot are retained as PARTIAL because concrete implementation/source/schema evidence exists; none is accepted as DONE.
- **2 of 95 PARTIAL features have evidence-backed numeric progress** (tenant/member isolation 38%; tenant directory/onboarding 30%). **93 PARTIAL features remain unscored** until all six weighted evidence dimensions are decomposed. Do not invent percentages.
- Current release flags remain `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.
- The live Supabase staging migration history has 49 entries through `20261119182606`; the repository staging source has 52 migrations. The three source-only migrations are `20261120100000`, `20261120110000`, and `20261120120000`. No shared staging migration was applied in this audit.
- This is a documentation/test-metadata correction only. It does not assert new runtime acceptance or authorize staging/production mutations.


## Superseding current execution checkpoint — 24 November 2026

### Feature counts
Recounting all 189 feature rows in `FNB_OS_IMPLEMENTATION_MATRIX.json` yields **95 PARTIAL / 88 NOT VERIFIED / 6 BLOCKED / 0 DONE**. This is the current matrix count and supersedes older 92/91/6 narrative snapshots. The six blocked rows remain blocked for acceptance until their external/platform gate is removed. Work status and audit status remain separate.

### Latest tenant security acceptance
- Staging SHA: `02c32c31315725c7639f249978efc4b8d486cab5`.
- PR #129 merged to staging after exact-head CI passed.
- [Tenant acceptance run 45230589775](https://github.com/dlice8888/dlice-landing-page/actions/runs/45230589775): P01–P09 9/9 PASS; supplemental RLS/RPC 6/6 PASS; 230/230 auth action probes PASS; cleanup PASS.
- Both existing tenant identities authenticated; own-branch reads succeeded; cross-tenant read/write denials returned expected 403 and denied write postconditions were zero.
- This closes the tenant-isolation P01–P09 execution blocker for the tested scope. It does **not** close Storage/cache/job isolation, the whole SaaS onboarding lifecycle, or the business E2E issue #45.

### Current staging database and platform
- Supabase `higoadrzxnhzbbwhdbmh`: ACTIVE_HEALTHY, PostgreSQL 17.11.0.003.
- 64/64 public tables have RLS enabled.
- 49 migrations applied; latest `20261119182606`; source staging has 52 SQL migration files, so 3 source-only migrations still need per-file parity/dependency review.
- Advisor: leaked-password protection WARN/disabled; 26 unindexed foreign keys; 49 unused indexes; health findings 0. Do not disable the security warning by silently substituting the application-side k-anonymity guard for native Supabase Auth protection. Do not drop unused indexes without representative query plans/workload.
- `dlice-orders` ACTIVE v71; custom `getAdmin(req)` is present; `verify_jwt=false` is not treated as absent authorization. Both release flags remain false.
- Vercel Preview is READY on the staging SHA; this is deployment/build evidence only.

### Business gaps still requiring implementation and E2E
1. **KDS/POS/Stock/Offline:** run positive checkout, payment confirmation, KDS dispatch/state transitions, exact-once recipe stock consumption, offline replay/retry, and reconcile POS sale/order/payment/ticket/stock ledger.
2. **Procurement/Receiving:** run requisition → approval → PO → receipt/GRN → stock movement/on-hand → invoice/AP match; include duplicate/retry and unauthorized branch cases.
3. **Production/Recipe:** pin immutable approved recipe version at order/batch creation; add station routing, lot/expiry and allergen traceability, expected-vs-actual/waste variance approval; reconcile stock.
4. **Inventory:** transfer and stock-count lifecycle with source/destination branch isolation, approval, ledger idempotency and variance reconciliation.
5. **Finance:** provider fee/settlement ingestion, balanced journals, AP/AR, cash/shift reconciliation, fiscal close/reopen and branch/group P&L.
6. **Executive/BI:** KPI dictionary, source-level totals, 150-branch drill-down, target/actual, anomaly→assign→resolve→audit.
7. **CRM/Delivery/HR/Franchise/Integrations:** customer consent/loyalty, courier proof/cost, workforce lifecycle, franchise contract/royalty and durable outbox/retry/health workflows.
8. **Quality/reliability:** native leaked-password control decision, 150-branch load/concurrency, backup/restore, incident runbooks, mobile/accessibility and rollout/rollback evidence.

### Scoring and prioritization
- Two PARTIAL scores are presently recorded: tenant/member isolation 38%, tenant directory/onboarding 30%. Re-score the isolation row with the new P01–P09 evidence only after updating each weighted criterion; do not assume full domain acceptance.
- 93 PARTIAL features still need their six evidence dimensions scored. Do not invent percentages.
- The 88 NOT VERIFIED features remain queued until a real implementation slice is committed and scoped tests pass. Opening a plan/issue is not enough to move a feature into PARTIAL.
- Prioritize security and data integrity first, then core order-to-cash / procure-to-pay / production-stock workflows, then finance/command center, then CRM/HR/delivery/franchise/BI/integrations, while ensuring every remaining unverified feature receives a concrete implementation start.

**Guardrails:** staging/disposable only; no production DB/Auth/secrets/deployment/data changes; no mass merge; no force push; preserve RLS, authorization, audit and branch isolation; keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.


## Migration parity correction — 24 November 2026

A fresh comparison of the complete GitHub `staging` migration tree against Supabase `schema_migrations` supersedes the older 52/49/3 statements in earlier snapshots:

| Measure | Current result |
|---|---:|
| Source SQL migration files | **56** |
| Applied Supabase migration versions | **49** |
| Source-only migrations | **7** |
| Applied versions missing from source | **0** |
| Duplicate source versions | **0** |

The seven source-only files are:
- `20261120100000_atomic_owner_and_tenant_bootstrap.sql`
- `20261120110000_command_center_summary.sql`
- `20261120120000_atomic_branch_checklist_audit.sql`
- `20261121100000_atomic_admin_permission_audit.sql`
- `20261121130000_atomic_tenant_invite_lifecycle.sql`
- `20261121160000_atomic_admin_profile_mutation_audit.sql`
- `20261121170000_atomic_branch_assignment_audit.sql`

Do not apply these as a batch. Review migration dependencies/order and RPC grants/RLS per file, run full exact-head disposable replay, then apply only individually authorized staging migrations with backup/rollback evidence. Production remains out of scope.


## Latest current-head evidence — 24 November 2026

- Current staging head: `666f2a432e236f15161cef8d2d9905279d0f5144`.
- [Quality run 45236931620](https://github.com/dlice8888/dlice-landing-page/actions/runs/45236931620): PASS on exact current staging head.
- [Tenant acceptance run 45236931758](https://github.com/dlice8888/dlice-landing-page/actions/runs/45236931758): P01–P09 9/9 PASS; supplemental RLS/RPC 6/6 PASS; 230/230 auth probes PASS; cleanup HTTP 204 for both sessions; no FAIL/BLOCKED/SKIPPED/executed:false.
- PR #130 merged passwordless existing-identity auth into the manual KDS/POS/Stock/Offline and Procurement/Receiving workflows. They remain unexecuted; the issue #45 business E2E acceptance is still OPEN.
- PR #132 ensures tenant acceptance reruns on Edge Function, migration, and positive-E2E auth harness changes.
- Vercel Preview for the exact staging SHA is READY (deployment `dpl_WA4PNxDM97qGxzT4Mva9sWG9xkQq`); no Production target.
- Supabase `dlice-orders` remains ACTIVE v71 with custom `getAdmin(req)`; both release flags remain false.
- Migration parity remains 56 source / 49 applied / 7 source-only / 0 DB-only / 0 duplicates. No shared staging migration was applied.

The feature status remains 95 PARTIAL / 88 NOT VERIFIED / 6 BLOCKED / 0 DONE. This current-head runtime result strengthens the tenant isolation evidence but does not close unrelated domain features or positive business E2E gaps.


## Tenant isolation re-score — 24 November 2026

The prior 38% score is superseded by the latest live staging acceptance on commit `666f2a432e236f15161cef8d2d9905279d0f5144` (run [45236931758](https://github.com/dlice8888/dlice-landing-page/actions/runs/45236931758)). The updated weighted score is **58% provisional**:

| Dimension | Weight | Earned | Evidence / remaining gap |
|---|---:|---:|---|
| Code/UI | 20 | 3 | Server-side branch-scope foundation exists; full tenant-aware UI and all route coverage remain unverified |
| Database/integrity | 20 | 15 | 64/64 public tables have RLS; 35 pgTAP assertions across 17 sensitive tables; cross-tenant denied-write postconditions prove zero transfer/item/stock-movement rows; Storage/cache/job coverage remains |
| Authorization/scope | 15 | 10 | P01-P09 own-scope and cross-tenant read/write probes pass; supplemental RLS/RPC 6/6 and missing/invalid auth 230/230 pass; not all mutation routes/storage/jobs are covered |
| Automated tests | 15 | 15 | Exact-head quality, tenant policy tests and 230 auth action probes pass |
| Workflow E2E | 20 | 10 | P01-P09 live staging API acceptance 9/9 passes; this is not full browser workflow or positive commerce E2E |
| Reconciliation/observability | 10 | 5 | Denied-write DB postconditions and session cleanup pass; Storage/cache/job and 150-branch operational reconciliation remain |
| **Total** | **100** | **58** | **Provisional implementation progress, not release readiness** |

Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`. Remaining acceptance: complete API mutation-route matrix, Storage/cache/background-job isolation, tenant invitation lifecycle, multi-branch/150-branch concurrency, browser E2E and full reconciliation.


## Live refresh — 24 November 2026, 07:25 WIB

- Current staging head: `abea9ffd4d7b198e88d0a19d906d912fa45bc35a`; quality PASS, KDS contract PASS, P01–P09 PASS 9/9, supplemental RLS/RPC 6/6, auth 230/230, temporary sessions revoked HTTP 204.
- PR #136 merged: 24 covering indexes for 26 FK constraints. Exact-head disposable replay: 58 migrations applied, 11 pgTAP files / 234 tests PASS. Shared Supabase staging remains at 49 applied migrations; no shared migration was applied.
- Migration parity is now 58 source / 49 applied / 9 source-only / 0 DB-only / 0 duplicate. The nine source-only files are: `20261120100000_atomic_owner_and_tenant_bootstrap.sql`, `20261120110000_command_center_summary.sql`, `20261120120000_atomic_branch_checklist_audit.sql`, `20261121100000_atomic_admin_permission_audit.sql`, `20261121120000_add_fk_covering_indexes.sql`, `20261121130000_atomic_tenant_invite_lifecycle.sql`, `20261121153000_remove_redundant_zero_scan_indexes.sql`, `20261121160000_atomic_admin_profile_mutation_audit.sql`, `20261121170000_atomic_branch_assignment_audit.sql`.
- 18-domain counts remain 95 PARTIAL / 88 NOT VERIFIED / 6 BLOCKED / 0 DONE. Partial coverage is 95/189 = 50.3%; this is the share of features with implementation started, not weighted completion.
- Only two PARTIAL features have evidence-based weighted scores: tenant/member isolation 58% provisional and tenant directory/onboarding 30% provisional. The other 93 PARTIAL features remain unscored until six-dimension criteria are decomposed; do not invent percentages.
- Vercel Preview for exact staging head is READY: [deployment](https://vercel.com/dlice8888-7332/dlice-landing-page/D9NVHeXQ9tBx1f37h6t6kMf6wcHV). Preview is not production release or business workflow acceptance.

## Superseding current audit — 25 November 2026

The latest row-level PRD reconciliation is **189 total / 140 PARTIAL / 44 NOT VERIFIED / 5 BLOCKED / 0 DONE**. This supersedes the 24-November 95/88/6 snapshot above. The 45 implementation-start transitions are work-start classifications linked to concrete source implementation in Draft PR #145 and Draft PR #146; they are not staging acceptance or DONE. Both PRs remain unmerged. The 45 transitions are: POS (5: four NOT VERIFIED and one BLOCKED), Executive (3), CRM (5), Delivery (6), Finance (2), HR (6), Franchise (6), BI (4), Procurement (2), Integrations (1), SaaS (4), Quality/backup restore (1).

**Important scoring distinction:** partial coverage (140/189 = 74.1%) means the number of PRD rows with implementation started, not the weighted completion of those features. Keep the 137 features with no feature-level evidence breakdown unscored; do not invent percentages. The only previously defensible weighted scores remain tenant/member isolation 58% provisional and tenant directory/onboarding 30% until the current exact criteria are rescored.

### Live platform evidence checked 25 November
- GitHub: PR #145 and #146 are OPEN Draft. PR #146 exact-head quality checks passed on 23e4b6c2a057b9b8bdeed68f71088c6e4c88d105; its database replay and provider/bank E2E remain unverified.
- Supabase staging higoadrzxnhzbbwhdbmh: ACTIVE_HEALTHY, PostgreSQL 17.11.0.003; 63 applied migrations through 20261124134222; 67 public tables and 67/67 have RLS enabled; dlice-orders ACTIVE v73 with verify_jwt=false and custom handler authorization; Security Advisor 1 WARN (leaked-password protection disabled); Performance Advisor 83 informational unused-index suggestions; Health Advisor 0 findings.
- Live table counts show no positive business lifecycle evidence yet for purchase orders/receipts, production batches/consumptions, settlements, refunds, cash reconciliation, fiscal periods, finance journals, stock transfers/counts, procurement requisitions, POS tenders/receipts, or new HR/CRM/Delivery/Franchise/BI draft extensions. Existing schema rows do not prove complete workflows.
- Vercel Hobby: staging Preview READY on aed9353d2d2daac57462a108beb43d983ec54946; PR #146 Preview READY on 4406c31250378dc9eaf13d6fa6d88726ef8fd6dd, which is behind PR #146 head; Production is READY on main commit cca72d336426688d8d7f6e01b819613ddc82fa6c. These were read-only inspections; no deploy was made.
- Keep TENANT_ISOLATION_RELEASED=false and PUBLIC_TENANT_ROUTING_RELEASED=false.

### Highest priority remaining NOT VERIFIED counts
Quality & Security 8; Branch Ops 5; CRM 3; BI 3; Procurement 3; Integrations 3; Menu 3; POS 1; HR 2; Executive 2; Finance 2; SaaS 2; Order 2; Kitchen 2; Delivery 0; Franchise 0. Prioritize by unverified count, then dependency and risk. Six BLOCKED items remain separate gates and are not silently reclassified.

### POS lifecycle evidence incorporated from PR #143

PR #143 is OPEN and not merged. Four previously NOT VERIFIED POS rows moved to PARTIAL and the digital receipt row moved from BLOCKED to PARTIAL because a digital receipt snapshot now exists. The current POS count is 12 PARTIAL / 1 NOT VERIFIED / 0 BLOCKED. Remaining gaps: discount/coupon engine, partial/unpaid balance collection, physical printer/browser-device acceptance, cashier browser acceptance and true network-loss/offline-client fault injection. PR #143 exact-head static/contract checks pass and disposable replay passed 14 pgTAP files / 375 assertions, but the staging POS E2E is BLOCKED before business mutation because Owner app_metadata.platform_owner is missing/null; no QA sale was created. Vercel Preview is READY on exact PR #143 head 0e3539b, which does not replace staging E2E.

### Backup/restore drill started — PR #148

PR #148 adds a free GitHub-hosted PostgreSQL 17 custom-format dump/restore rehearsal with 150 Tenant A branches plus Tenant B, deterministic checksum parity, pre/post-snapshot boundary, restored RLS and cross-tenant read-denial assertions. The workflow has not yet returned a completed run, so the feature is PARTIAL/IN_PROGRESS only. It is not Supabase managed backup, Auth/Storage recovery, PITR, or platform RPO/RTO evidence. The remaining 7 Quality/Compliance/Security NOT VERIFIED rows are food safety/recall, supplier quality/CAPA, 150-branch load/concurrency, pilot/rollout/rollback, workflow acceptance, responsive UX/accessibility, and backup/recovery/scale/rollout.
