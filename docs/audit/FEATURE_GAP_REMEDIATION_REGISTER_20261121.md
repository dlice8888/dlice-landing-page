# D’Lice FnB OS — feature gap remediation register

Snapshot: 2026-11-21 | PRD baseline: 189 features / 18 domains | Target: SaaS + ERP + POS for 150 branches

## Status and work rules
- `audit_status` describes evidence in the staging baseline. A Draft PR does not prove that shared staging is updated.
- `work_status=IN_PROGRESS` is assigned only when a concrete code/database/workflow change exists and is linked to an active PR.
- A `NOT VERIFIED` feature moves to `PARTIAL` only after implementation evidence exists; no status is changed merely by opening an issue or writing a plan.
- `BLOCKED` remains a release gate until its external/platform/authorization dependency is resolved. Partial implementation does not erase the gate.
- Progress percentages are not guessed. Score each feature only after its acceptance criteria are decomposed and evidence is linked. DONE requires 100%, code + DB + auth + workflow tests, reconciliation, no BLOCKED/SKIPPED, and independent review.

## Implementation priority
1. Security/access: feature 8 (permission-change audit) and feature 9 (leaked-password protection).
2. Transaction integrity: feature 3 (duplicate/delayed/failed orders) then feature 2 (receipt/checkout correctness).
3. Production/inventory: features 4 and 5.
4. Branch operations: feature 6.
5. Finance/Command Center: features 7 and 1.
6. Start all remaining NOT VERIFIED features in dependency/risk order. A feature is moved to PARTIAL only after its first concrete vertical slice is implemented and tested.

## Baseline reconciliation

The supplied 18-domain rows originally summed to **82 PARTIAL + 98 NOT VERIFIED + 9 BLOCKED = 189** before the newest implementation evidence was counted. The supplied total-row value of 93 NOT VERIFIED was an arithmetic error; the domain rows sum to 98.

Two SaaS Tenant Management features moved from NOT VERIFIED to PARTIAL after concrete implementation began in PR #126. Five additional features moved to PARTIAL after the live schema/function audit confirmed implementation foundations. The current feature-level source of truth is **89 PARTIAL + 91 NOT VERIFIED + 9 BLOCKED = 189**.

| Domain | Features | PARTIAL | NOT VERIFIED | BLOCKED |
|---|---:|---:|---:|---:|
| Executive Command Center | 10 | 4 | 5 | 1 |
| POS & Checkout | 13 | 7 | 5 | 1 |
| Order Management | 10 | 7 | 2 | 1 |
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
| Admin, Identity & Access Control | 10 | 5 | 4 | 1 |
| SaaS Tenant Management | 8 | 2 | 6 | 0 |
| Integrations & Automation | 9 | 5 | 4 | 0 |
| Quality, Compliance & Security | 20 | 10 | 9 | 1 |
| **TOTAL** | **189** | **89** | **91** | **9** |

The five additional PARTIAL classifications are evidence-based:
- Kitchen & Production: KDS tickets and kitchen queue priority (tables, dispatch/transition RPCs, priority field, and six staging tickets/items exist).
- Menu & Recipe: branch-specific pricing settings (branch settings pricing category and read/write handlers exist).
- Inventory & Warehouse: warehouse master (warehouse table and ERP handlers exist) and min-stock threshold (inventory_items.min_stock exists).

These five are not DONE. Station routing, SLA escalation, central/regional pricing governance, storage/bin hierarchy, safety stock/reorder workflow and other acceptance gaps remain open. Two SaaS PARTIAL features have weighted progress of 30% and 38%; the other 87 PARTIAL features still require feature-level evidence decomposition before a defensible percentage can be assigned. No percentage is fabricated.

## Per-domain feature gaps and work

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
- PR #120: atomic permission-change audit; Draft; independent review and authorized staging runtime acceptance remain.
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
- **Remaining gaps:** create/verify two distinct tenant identities; test own-tenant read/write; reject cross-tenant read/write through every Edge Function; test Storage object isolation, caches, exports, cron/jobs and platform-owner bypass; prove role and permission changes cannot cross tenants; run browser/API negative probes with no BLOCKED/SKIPPED; independently review before release.
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

**Remaining gap:** password reset attempts/outcomes, tenant membership role changes and branch-assignment create/update/revoke still need a full mutation inventory and audit/transaction treatment. **Validation update (21 November):** exact PR #120 head `29d6d808c2b56eb9596335805499266de4e1b4ba` passes free quality, disposable migration replay, KDS, CORS, procurement receiving and requisition contracts. Disposable replay executed 7 pgTAP files / 107 assertions, including all 11 new audited-invite assertions. PR remains Draft and the feature remains BLOCKED until independent review and authorized staging runtime evidence pass.


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
- **#120:** exact head `29d6d808` quality, disposable migration replay, CORS, KDS, procurement requisition and receiving contracts PASS. Independent review and real staging permission-mutation runtime remain open.
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

The score measures implementation completeness, not release readiness. Missing evidence receives zero; no score is inferred from a PR being open or a table existing. At this checkpoint, 2 of 89 PARTIAL features have evidence-backed provisional percentages (tenant isolation 38%, tenant directory/onboarding 30%); 87 remain explicitly marked `UNSCORED_EVIDENCE_BREAKDOWN_REQUIRED`. Completing those 87 feature-level evidence breakdowns is itself an audit work item; I will not manufacture percentages.
