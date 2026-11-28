# 65 NOT VERIFIED — Concrete Implementation Backlog

**Repository:** `dlice8888/dlice-landing-page`  
**Target:** `staging`  
**Snapshot source:** `docs/audit/FNB_OS_IMPLEMENTATION_MATRIX.json` and `docs/audit/PRD_FEATURE_EVIDENCE_LEDGER_20261126.json`  
**Scope:** 65 feature IDs marked NOT VERIFIED in the audited matrix. This backlog is not a claim that all features are absent from source.

## Mandatory security and release guardrails
- Staging/disposable only. Production must remain read-only; no production deploy, migration, data, secret or environment mutation.
- Preserve `TENANT_ISOLATION_RELEASED=false`, `PUBLIC_TENANT_ROUTING_RELEASED=false`, and `BRANCH_OPS_WORKFLOWS_RELEASED=false`.
- Never expose service-role keys in browser, artifacts or logs. Do not weaken RLS, grants, tenant isolation, audit or release gates.
- Use existing schema/RPC signatures after inspecting the repository and staging catalog. Do not invent replacement SQL or duplicate existing migrations.
- Do not mark DONE from PR merge, static checks or preview readiness alone.

## Evidence gates (must be attached to each ticket)
- **E0:** PRD ID and acceptance criteria traced to source.
- **E1:** identify placeholder-only route/UI/mock; does not count as implementation.
- **E2:** exact source, schema/migration, FK/constraints, RLS, grants, RPC/API and audit lineage.
- **E3:** unit/contract/SQL tests plus positive and negative authorization, idempotency and regression.
- **E4:** UI → authorized server/API → DB → downstream domain integration.
- **E5:** successful staging runtime run on exact commit with fixture tenant/branch and redacted artifact.
- **E6:** complete E2E plus independent reconciliation against authoritative ledgers; no duplicate/unauthorized side effects.

## Implementation protocol
1. Inspect current staging HEAD and all overlapping open PRs before editing; rebase only with non-force fast-forward-safe operations.
2. Reuse existing domain modules and RPC signatures. Add a migration only after source/catalog parity review and disposable replay.
3. Add tests before changing audit status. Attach exact commit, workflow run, test artifact and reconciliation query/output.
4. Keep status NOT VERIFIED until concrete source work exists; then PARTIAL only when the matrix records real evidence. DONE requires all applicable E0–E6.

## Ticket index

1. **D01-F02** — Live sales monitor day/week/month (Executive Command Center)
2. **D01-F07** — Approval center and pending approvals (Executive Command Center)
3. **D02-F01** — POS workspace, shifts and cash reconciliation (POS & Checkout)
4. **D02-F02** — Cart, product selection and quantity updates (POS & Checkout)
5. **D02-F03** — Dine-in, takeaway, pickup and delivery parity (POS & Checkout)
6. **D02-F06** — Cash, QRIS, card, transfer and provider methods (POS & Checkout)
7. **D02-F09** — Void, refund and return with reason/approval (POS & Checkout)
8. **D02-F11** — Cash in/out, drawer reconciliation and shift close (POS & Checkout)
9. **D02-F13** — Separate order, payment and fulfillment statuses (POS & Checkout)
10. **D03-F01** — Online and POS orders in a shared queue (Order Management)
11. **D03-F03** — Hours, cutoff, menu availability and branch capacity (Order Management)
12. **D03-F04** — Branch assignment by area and capacity (Order Management)
13. **D03-F05** — Unique business order number (Order Management)
14. **D03-F06** — Consistent status/timeline across channels (Order Management)
15. **D03-F09** — Cancellation/refund and customer order history (Order Management)
16. **D03-F10** — Customer notifications on each state (Order Management)
17. **D04-F01** — KDS and kitchen order tickets (Kitchen & Production)
18. **D04-F03** — Queue priority and preparation SLA (Kitchen & Production)
19. **D04-F04** — Waiting → in progress → ready → handed over (Kitchen & Production)
20. **D04-F05** — Recipes, portion/yield and waste tolerance (Kitchen & Production)
21. **D04-F06** — Prep lists and batch planning (Kitchen & Production)
22. **D04-F07** — Actual material consumption (Kitchen & Production)
23. **D04-F09** — Made-to-order versus batch production separation (Kitchen & Production)
24. **D05-F01** — Central product catalog and categories (Menu, Recipe & Product Engineering)
25. **D05-F02** — Per-branch product availability (Menu, Recipe & Product Engineering)
26. **D05-F03** — Central, regional and branch-specific pricing (Menu, Recipe & Product Engineering)
27. **D05-F04** — Recipe/BOM and ingredient mapping (Menu, Recipe & Product Engineering)
28. **D05-F06** — Recipe versions and effective dates (Menu, Recipe & Product Engineering)
29. **D05-F09** — Availability by schedule and stock (Menu, Recipe & Product Engineering)
30. **D05-F10** — Recipe change request → costing → approval → rollout (Menu, Recipe & Product Engineering)
31. **D06-F01** — Inventory item and branch stock (Inventory & Warehouse)
32. **D06-F02** — Stock movement ledger (Inventory & Warehouse)
33. **D06-F03** — Warehouse, storage and bin hierarchy (Inventory & Warehouse)
34. **D06-F04** — Purchase/use units and conversions (Inventory & Warehouse)
35. **D06-F06** — Available/reserved/in-transit/blocked balances (Inventory & Warehouse)
36. **D06-F07** — Min/max, safety stock and reorder point (Inventory & Warehouse)
37. **D06-F09** — Stock count/cycle count and variance adjustment (Inventory & Warehouse)
38. **D06-F11** — Adjustments with reasons, approvals and audit (Inventory & Warehouse)
39. **D06-F12** — PO receipt → stock ledger → balance reconciliation (Inventory & Warehouse)
40. **D07-F03** — Purchase requisition from branch/warehouse/central kitchen (Procurement & Supplier)
41. **D07-F05** — Purchase order lifecycle draft → submit → approve → ordered (Procurement & Supplier)
42. **D07-F06** — Approval limits by value/category (Procurement & Supplier)
43. **D08-F01** — Branch directory, status, timezone and assignments (Branch Operations)
44. **D08-F02** — Opening and closing checklists (Branch Operations)
45. **D08-F05** — SOP and work instructions (Branch Operations)
46. **D08-F06** — Cleanliness, equipment and safety checks (Branch Operations)
47. **D10-F03** — Customer segments (CRM, Loyalty & Marketing)
48. **D10-F05** — Rewards and vouchers/coupons (CRM, Loyalty & Marketing)
49. **D11-F01** — Finance overview, expenses and approvals (Finance & Accounting)
50. **D11-F04** — AR/AP subledgers and aging (Finance & Accounting)
51. **D11-F08** — Tax and invoicing (Finance & Accounting)
52. **D11-F11** — Period close/reopen and backdated posting controls (Finance & Accounting)
53. **D15-F01** — User/admin profiles, roles and permission actions (Admin, Identity & Access Control)
54. **D15-F02** — Branch assignments and scope enforcement (Admin, Identity & Access Control)
55. **D15-F03** — Owner/manager/no-permission/inactive identity probes (Admin, Identity & Access Control)
56. **D15-F04** — Audit logs for sensitive actions (Admin, Identity & Access Control)
57. **D15-F05** — Delegated approvals and separation of duties (Admin, Identity & Access Control)
58. **D15-F08** — API/database deny-by-default and direct-table protection (Admin, Identity & Access Control)
59. **D15-F09** — Cross-tenant isolation (Admin, Identity & Access Control)
60. **D15-F10** — Permission changes are themselves audited (Admin, Identity & Access Control)
61. **D17-F01** — Edge Function API and payment proof flow (Integrations & Automation)
62. **D17-F08** — Secret storage and rotation (Integrations & Automation)
63. **D18-F05** — Leaked-password protection (Quality, Compliance & Security)
64. **D18-F09** — Monitoring, system health and incident runbooks (Quality, Compliance & Security)
65. **D18-F15** — Forecast-to-Production (Quality, Compliance & Security)

## D01-F02 — Live sales monitor day/week/month

**Domain:** Executive Command Center  
**Priority:** P1/P2  
**Gap teknis:** Sales aggregates lack proven source-order reconciliation, business-date cutoff and branch timezone handling.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** POS sales/items, refunds, tender/settlement and Finance journal; read-only aggregation RPC/view.
- **Otorisasi:** Owner/group scope; regional scope; branch manager own branch only; server derives tenant and branch.
- **UI:** Date range, timezone, branch/region filters, gross/net/refunds/discounts and transaction drill-down.
- **Test:** Cutoff boundaries, late events, refunds, duplicate sales, cross-tenant and branch denial.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Day/week/month totals equal eligible source transactions after refunds and adjustments; every total drills to source rows.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D01-F07 — Approval center and pending approvals

**Domain:** Executive Command Center  
**Priority:** P1/P2  
**Gap teknis:** Approvals are domain-specific; unified inbox, delegation, expiry and separation-of-duties are not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Approval requests/read model referencing Finance, Procurement, HR and Branch Ops entities; list/claim/decide RPCs.
- **Otorisasi:** Role, value, category, tenant, branch and self-approval policy enforced server-side.
- **UI:** Pending queue, evidence detail, approve/reject reason, delegation and decision history.
- **Test:** Self-approval, stale version, duplicate decision, expired delegation, race and unauthorized branch.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** One staging approval changes exactly one source entity, with immutable actor/reason/timestamp audit.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D02-F01 — POS workspace, shifts and cash reconciliation

**Domain:** POS & Checkout  
**Priority:** P0  
**Gap teknis:** End-to-end shift open → sales → cash movement → close/reconciliation not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Existing POS shift/sale/cash reconciliation schema; atomic open, movement and close RPCs.
- **Otorisasi:** Cashier assigned shift/branch; supervisor approval for variance; no cross-branch access.
- **UI:** Open shift, opening float, sales, cash-in/out, expected/count/variance and close.
- **Test:** Duplicate shift, pending sale, concurrent close, variance thresholds and branch isolation.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Expected drawer reconciles to opening float + cash tenders + cash-in − cash-out − cash refunds.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D02-F02 — Cart, product selection and quantity updates

**Domain:** POS & Checkout  
**Priority:** P0  
**Gap teknis:** Server-authoritative price, modifiers, availability and concurrent cart mutation not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Catalog, variants, modifiers, price snapshots, sale drafts/items; server checkout validation RPC.
- **Otorisasi:** Client price/discount ignored; tenant/branch and product visibility enforced server-side.
- **UI:** Search catalog, choose modifier, edit quantity/notes, view validated totals.
- **Test:** Tampered price, inactive item, stock race, duplicate submit, invalid modifier.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Persisted sale lines and totals exactly match server-calculated cart snapshot.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D02-F03 — Dine-in, takeaway, pickup and delivery parity

**Domain:** POS & Checkout  
**Priority:** P0  
**Gap teknis:** Order-type-specific fulfillment paths and required metadata are not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Order type, table/seat, pickup slot, delivery reference, fulfillment state and history.
- **Otorisasi:** Branch enabled types; only authorized actors may change type/state.
- **UI:** Order-type selector and type-specific fields/queues.
- **Test:** Missing metadata, illegal type change, cancellation, branch mismatch.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Each type completes correct fulfillment path; payment and fulfillment states remain independent.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D02-F06 — Cash, QRIS, card, transfer and provider methods

**Domain:** POS & Checkout  
**Priority:** P0  
**Gap teknis:** Provider confirmation, split-tender allocation and settlement parity not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Payment intents/records, tender allocations, webhook inbox and settlement references.
- **Otorisasi:** Verify provider signature/replay; client cannot mark paid; server-only secrets.
- **UI:** Tender selection, split allocation, pending/paid/failed and proof display.
- **Test:** Invalid/duplicate webhook, timeout, partial/over/underpayment and replay.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Tender allocations equal sale total; settlement and provider references reconcile exactly.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D02-F09 — Void, refund and return with reason/approval

**Domain:** POS & Checkout  
**Priority:** P0  
**Gap teknis:** Void/return policy and POS→stock→Finance compensation not proven end-to-end.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Refund/return requests, approval, reversal ledger, stock return and journal references.
- **Otorisasi:** Reason required; approval limits; maker-checker; same-tenant/branch scope.
- **UI:** Item-level return, reason/evidence, approval and refund status.
- **Test:** Partial/full refund, over-refund, duplicate processing, self-approval and stock disposition.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Tender reversal, stock return, journal, receipt and audit reconcile; idempotent exactly once.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D02-F11 — Cash in/out, drawer reconciliation and shift close

**Domain:** POS & Checkout  
**Priority:** P0  
**Gap teknis:** Cash movement lifecycle and variance controls not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Drawer movements, shift close snapshot, reconciliation and variance approval RPCs.
- **Otorisasi:** Cashier own shift; supervisor approval above threshold; immutable closed shift.
- **UI:** Cash-in/out reason, expected/count cash, variance and close receipt.
- **Test:** Concurrent movement, duplicate, pending transaction, variance threshold and reopen denial.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Recomputed drawer from tenders and movements equals close snapshot and variance.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D02-F13 — Separate order, payment and fulfillment statuses

**Domain:** POS & Checkout  
**Priority:** P0  
**Gap teknis:** Independent state machines and compensation/retry behavior not fully accepted.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Append-only transition history and versioned transition RPCs for each state.
- **Otorisasi:** Domain-specific actor rights; customer/client cannot set payment state.
- **UI:** Three independent status indicators and timelines.
- **Test:** Illegal/out-of-order/duplicate transition, stale version, paid then failed fulfillment.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Order/payment/fulfillment remain independently valid through payment failure, fulfillment failure and refund.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D03-F01 — Online and POS orders in a shared queue

**Domain:** Order Management  
**Priority:** P0  
**Gap teknis:** Channel parity, branch ownership and deduplication not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Canonical orders, channel references, queue projection and ingest/list RPCs.
- **Otorisasi:** Server derives tenant/branch; channel identity cannot select tenant.
- **UI:** Unified queue filtered by channel, age, branch and status.
- **Test:** Duplicate external ID, concurrent POS/online, routing and unauthorized branch.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Each source order appears exactly once in correct branch queue with source lineage.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D03-F03 — Hours, cutoff, menu availability and branch capacity

**Domain:** Order Management  
**Priority:** P0  
**Gap teknis:** Timezone, holidays, cutoff boundaries and capacity reservations not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Branch hours/exceptions, capacity slots, menu availability and quote RPC.
- **Otorisasi:** Only authorized branch/HQ role changes policy; server validates order quote.
- **UI:** Operating hours/cutoff editor and available/full slot display.
- **Test:** Timezone boundary, holiday, cutoff, simultaneous capacity reservation.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Before-cutoff orders accepted; after-cutoff/full-capacity orders follow configured rejection/next-slot policy.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D03-F04 — Branch assignment by area and capacity

**Domain:** Order Management  
**Priority:** P0  
**Gap teknis:** Area routing, capacity reservation, failover and override not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Service areas, capacity counters/reservations, routing decision log and reserve/release RPC.
- **Otorisasi:** Routing server-side; manual override restricted and audited.
- **UI:** Area/capacity configuration and assignment reason.
- **Test:** Overload, simultaneous reservation, inactive branch and override.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** All test orders assigned to eligible capacity; no overbooking; decisions auditable.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D03-F05 — Unique business order number

**Domain:** Order Management  
**Priority:** P0  
**Gap teknis:** Uniqueness under concurrency, retries and date boundary not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Server-side sequence/unique constraint and transactional number generator.
- **Otorisasi:** Client cannot set final order number; tenant/date scope checked.
- **UI:** Number displayed consistently across POS, order detail and receipt.
- **Test:** Concurrency, retry, rollback, date boundary and duplicate request.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Stress test produces unique numbers; retry preserves original number.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D03-F06 — Consistent status/timeline across channels

**Domain:** Order Management  
**Priority:** P0  
**Gap teknis:** Event ordering, source attribution and duplicate event handling not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Append-only order events, source event IDs, sequence/version and idempotent append RPC.
- **Otorisasi:** Only authorized channel/domain event types; state machine validated.
- **UI:** Unified timeline with actor, source, time and reason.
- **Test:** Duplicate/out-of-order webhook, clock skew, invalid transition and unauthorized source.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** POS and online timeline converge to identical canonical status and ordered event history.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D03-F09 — Cancellation/refund and customer order history

**Domain:** Order Management  
**Priority:** P0  
**Gap teknis:** Cancel-after-payment compensation and customer ownership checks not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Cancellation, refund, order history projection and compensation references.
- **Otorisasi:** Customer sees own orders; staff branch scope; refund approval policy.
- **UI:** Order history, detail, cancel request, refund progress.
- **Test:** Cancel unpaid/paid, partial fulfillment, duplicate cancel, cross-customer denial.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Cancel/refund/stock/Finance effects reconcile; customer cannot read another customer history.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D03-F10 — Customer notifications on each state

**Domain:** Order Management  
**Priority:** P0  
**Gap teknis:** Outbox delivery, consent, retry and duplicate suppression not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Notification outbox, attempts, provider IDs, dead-letter and dispatch worker.
- **Otorisasi:** Consent/opt-out enforced; provider secrets server-only; tenant isolation.
- **UI:** Notification preferences and delivery history.
- **Test:** Duplicate event, provider timeout, opt-out, invalid destination and retry exhaustion.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** One eligible transition sends one notification; failures retry safely and dead-letter visibly.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D04-F01 — KDS and kitchen order tickets

**Domain:** Kitchen & Production  
**Priority:** P1/P2  
**Gap teknis:** Station routing and live KDS lifecycle not proven against POS orders.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Kitchen tickets/items, station assignments, event history and dispatch/claim/transition RPCs.
- **Otorisasi:** Kitchen staff assigned station/branch; supervisor override audited.
- **UI:** Live station board, timer, priority and item handover.
- **Test:** Duplicate dispatch, station mismatch, cancel, stale ticket and reconnect.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** POS/order items create matching tickets and all tickets reconcile to source order.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D04-F03 — Queue priority and preparation SLA

**Domain:** Kitchen & Production  
**Priority:** P1/P2  
**Gap teknis:** SLA policy, overdue escalation and queue fairness not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Station/product SLA policy, target timestamps and escalation log.
- **Otorisasi:** Only supervisor/authorized HQ changes SLA; historical timers immutable.
- **UI:** Priority queue, countdown, overdue and escalation action.
- **Test:** Boundary, pause/resume, fairness, timezone and duplicate escalation.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Overdue ticket creates one escalation and dashboard duration matches event timestamps.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D04-F04 — Waiting → in progress → ready → handed over

**Domain:** Kitchen & Production  
**Priority:** P1/P2  
**Gap teknis:** State transitions and handover acknowledgement not fully accepted.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Kitchen transition history, actor/time and allowed-state RPC.
- **Otorisasi:** Station assignee controls work states; handover receiver acknowledgement required.
- **UI:** State-specific actions, ready queue and handover confirmation.
- **Test:** Illegal transition, wrong actor, duplicate handover and cancelled item.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Each ticket follows legal lifecycle with receiver and timestamp recorded.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D04-F05 — Recipes, portion/yield and waste tolerance

**Domain:** Kitchen & Production  
**Priority:** P1/P2  
**Gap teknis:** Yield, portion conversion, prep loss and tolerance calculations not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Versioned recipes/BOM, UOM conversion, yield factors and waste tolerance RPC.
- **Otorisasi:** Recipe author/editor separated from approver; branch uses active version only.
- **UI:** Portion/yield editor, expected output, ingredient usage and tolerance.
- **Test:** Conversion, rounding, zero yield, overlap and unauthorized activation.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Production theoretical usage matches active recipe version and approved yield/waste policy.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D04-F06 — Prep lists and batch planning

**Domain:** Kitchen & Production  
**Priority:** P1/P2  
**Gap teknis:** Demand-driven prep planning and ingredient reservation not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Prep plans, batch lines, demand references, ingredient requirements/reservations.
- **Otorisasi:** Planner scoped to branch; exceptional batch approval policy.
- **UI:** Prep list by shift, batch size, ingredient readiness.
- **Test:** Demand changes, duplicate plan, insufficient stock and concurrent reservation.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Planned quantity and reserved ingredients match demand and available stock.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D04-F07 — Actual material consumption

**Domain:** Kitchen & Production  
**Priority:** P1/P2  
**Gap teknis:** Production consumption needs positive recipe-to-stock reconciliation.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Existing atomic consumption RPC, batch/recipe version, stock movements and waste events.
- **Otorisasi:** Only assigned branch operator posts; variance above threshold approved.
- **UI:** Planned vs actual usage, waste and variance posting.
- **Test:** Duplicate consume, insufficient stock, partial batch, stale recipe and rollback.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Actual consumption equals ledger movements by ingredient; no duplicate depletion.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D04-F09 — Made-to-order versus batch production separation

**Domain:** Kitchen & Production  
**Priority:** P1/P2  
**Gap teknis:** Mode-specific planning, production and fulfillment paths not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Production mode, batch links, on-demand jobs and fulfillment source refs.
- **Otorisasi:** Mode determined by server policy; override authorized and audited.
- **UI:** Mode badge, on-demand queue and batch board.
- **Test:** Mode mismatch, batch depletion, fallback and cancellation.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Made-to-order and batch products follow distinct paths with correct stock and fulfillment.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D05-F01 — Central product catalog and categories

**Domain:** Menu, Recipe & Product Engineering  
**Priority:** P1/P2  
**Gap teknis:** Catalog lifecycle, hierarchy, variants and modifier governance incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Products/categories/variants/modifiers and version/effective metadata.
- **Otorisasi:** HQ manages master; branch edits limited to scoped overrides.
- **UI:** Catalog editor, category tree, modifier manager and preview.
- **Test:** Duplicate SKU, invalid modifier, inactive product and cross-tenant access.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Approved catalog version publishes only to entitled branches and POS reads active version.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D05-F02 — Per-branch product availability

**Domain:** Menu, Recipe & Product Engineering  
**Priority:** P1/P2  
**Gap teknis:** Stock-aware branch availability and override policy not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Branch product availability, schedule, stock threshold and override records.
- **Otorisasi:** Branch manager own branch; HQ policy controls overrides.
- **UI:** Availability matrix and unavailable reason.
- **Test:** Stock depletion, schedule boundary, wrong branch and cache invalidation.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Unavailable product blocked at selected branch while other eligible branches remain sellable.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D05-F03 — Central, regional and branch-specific pricing

**Domain:** Menu, Recipe & Product Engineering  
**Priority:** P1/P2  
**Gap teknis:** Price hierarchy, effective date, approval and precedence not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Price lists, scopes, effective dates, approvals and resolver RPC.
- **Otorisasi:** HQ/regional/branch permissions; price changes require policy approval.
- **UI:** Price editor, hierarchy preview and scheduled activation.
- **Test:** Overlapping dates, precedence, unauthorized override and timezone.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** POS at each test branch resolves the correct effective price by hierarchy.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D05-F04 — Recipe/BOM and ingredient mapping

**Domain:** Menu, Recipe & Product Engineering  
**Priority:** P1/P2  
**Gap teknis:** Nested BOM, UOM mapping and production linkage incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Recipe versions, BOM lines, ingredient refs, UOM mappings and parent-child links.
- **Otorisasi:** Recipe editor/approver separated; tenant and branch scopes enforced.
- **UI:** BOM tree, ingredient mapping and validation.
- **Test:** Cyclic BOM, missing ingredient, invalid UOM and version mismatch.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** POS/production usage references same active BOM version and computes ingredient needs.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D05-F06 — Recipe versions and effective dates

**Domain:** Menu, Recipe & Product Engineering  
**Priority:** P1/P2  
**Gap teknis:** Historical immutability and effective-date overlap not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Immutable recipe versions, effective_from/to and activation history RPC.
- **Otorisasi:** Only approver activates; author cannot self-approve when policy requires.
- **UI:** Version timeline, diff and scheduled activation.
- **Test:** Overlapping periods, backdated change, concurrent activation and post-activation mutation.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Old sales retain old recipe version; new sales use effective version; history immutable.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D05-F09 — Availability by schedule and stock

**Domain:** Menu, Recipe & Product Engineering  
**Priority:** P1/P2  
**Gap teknis:** Reservation-aware menu availability not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Schedules, stock balances, reservations and availability snapshot/RPC.
- **Otorisasi:** Server computes availability; branch edits policy only within role.
- **UI:** Availability calendar and stock indicators.
- **Test:** Concurrent checkout, reservation expiry, stock adjustment and cutoff.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Concurrent orders cannot sell more than allocatable stock.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D05-F10 — Recipe change request → costing → approval → rollout

**Domain:** Menu, Recipe & Product Engineering  
**Priority:** P1/P2  
**Gap teknis:** Change request, cost simulation, approval and branch rollout not proven end-to-end.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Change requests, costing snapshots, decisions, rollout jobs and acknowledgements.
- **Otorisasi:** Maker-checker, role and scope; no self-approval where prohibited.
- **UI:** Change request, cost impact, approval and rollout progress.
- **Test:** Stale cost, failed/offline rollout, duplicate rollout and self-approval.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** New version activates only after approval; each branch rollout/exception is visible and version-correct.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D06-F01 — Inventory item and branch stock

**Domain:** Inventory & Warehouse  
**Priority:** P0  
**Gap teknis:** Authoritative branch balance and ledger reconciliation not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Inventory items, branch inventory, movement ledger and balance projection.
- **Otorisasi:** Branch scope enforced; balances cannot be edited directly by client.
- **UI:** Stock card with on-hand/reserved/available and movement history.
- **Test:** Negative balance, concurrent post, direct update denial and branch isolation.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Balance equals opening balance plus all valid movements for each item/branch.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D06-F02 — Stock movement ledger

**Domain:** Inventory & Warehouse  
**Priority:** P0  
**Gap teknis:** All POS, production, receiving, transfer and waste movement sources not reconciled.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Append-only stock movement, source refs, UOM and idempotency RPC.
- **Otorisasi:** Only authorized server domain posts; historical ledger immutable.
- **UI:** Movement history linked to source transactions.
- **Test:** Duplicate post, missing source, reversal, negative stock and concurrency.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Each domain movement matches balance delta exactly; no duplicate movement.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D06-F03 — Warehouse, storage and bin hierarchy

**Domain:** Inventory & Warehouse  
**Priority:** P0  
**Gap teknis:** Zone/bin hierarchy and transfer/receiving integration not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Warehouses, zones, bins, tenant/branch composite FKs and capacity/status.
- **Otorisasi:** Warehouse and branch scope; cross-tenant locations denied.
- **UI:** Location tree, bin detail, capacity and status.
- **Test:** Circular hierarchy, duplicate code, invalid destination and cross-tenant FK.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Receiving and transfer place stock in correct bin; per-bin balance reconciles.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D06-F04 — Purchase/use units and conversions

**Domain:** Inventory & Warehouse  
**Priority:** P0  
**Gap teknis:** Precision, rounding and compatible-unit conversion not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** UOM definitions, ratios, precision policy and versioned conversions.
- **Otorisasi:** Only inventory/recipe admin changes conversion; historical snapshots immutable.
- **UI:** UOM setup and conversion preview.
- **Test:** Circular conversion, invalid dimension, rounding and historical version.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** PO, receipt and consumption quantities convert to correct base units.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D06-F06 — Available/reserved/in-transit/blocked balances

**Domain:** Inventory & Warehouse  
**Priority:** P0  
**Gap teknis:** Bucket accounting and transitions are incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Reservation, in-transit, blocked/quarantine bucket events and RPCs.
- **Otorisasi:** Reserve/release/transfer server-side; quarantine release requires approver.
- **UI:** Bucket breakdown and blocked reason.
- **Test:** Expiry, partial ship/receive, duplicate release and negative available.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** On-hand equals defined buckets and every bucket movement has source lineage.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D06-F07 — Min/max, safety stock and reorder point

**Domain:** Inventory & Warehouse  
**Priority:** P0  
**Gap teknis:** Safety stock, supplier lead time and replenishment calculation not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Reorder policies, lead times, demand history, safety stock and recommendation snapshots.
- **Otorisasi:** Inventory planner scope; requisition still follows approval policy.
- **UI:** Min/max, reorder point, recommended quantity and explanation.
- **Test:** Lead-time variation, demand spike, duplicate recommendation and inactive supplier.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Recommendation recomputes from available stock/demand/lead time and creates no duplicate requisition.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D06-F09 — Stock count/cycle count and variance adjustment

**Domain:** Inventory & Warehouse  
**Priority:** P0  
**Gap teknis:** Count freeze, recount, variance approval and posting not fully accepted.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Count sessions/lines, book quantity snapshot, variance, approval and posting refs.
- **Otorisasi:** Counter cannot approve own high-risk variance; branch scope enforced.
- **UI:** Blind count, recount, variance review and post.
- **Test:** Concurrent movements, duplicate post, recount and unauthorized approval.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Approved variance creates exactly one adjustment movement; closing balance recalculates.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D06-F11 — Adjustments with reasons, approvals and audit

**Domain:** Inventory & Warehouse  
**Priority:** P0  
**Gap teknis:** Risk thresholds and dual-control audit trail incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Adjustment requests, reason codes, thresholds, approver decisions and movement refs.
- **Otorisasi:** Maker-checker, threshold and role; all sensitive actions audited.
- **UI:** Request, evidence, approval queue and immutable history.
- **Test:** Missing reason, self-approval, threshold edge and audit failure rollback.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Approved adjustment creates one movement and linked immutable audit event.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D06-F12 — PO receipt → stock ledger → balance reconciliation

**Domain:** Inventory & Warehouse  
**Priority:** P0  
**Gap teknis:** Positive procurement receiving path and quantity parity not fully proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** PO/GRN, accepted/rejected quantities, stock movement and balance; existing receiving RPC.
- **Otorisasi:** Receiver limited to assigned branch/warehouse and valid PO; approval for discrepancy.
- **UI:** Partial receipt, inspection, discrepancy and reconciliation.
- **Test:** Over-receipt, partial, rejected goods, duplicate GRN and concurrency.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** PO, accepted GRN, movement and balance match; rejected quantity never increases available stock.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D07-F03 — Purchase requisition from branch/warehouse/central kitchen

**Domain:** Procurement & Supplier  
**Priority:** P1/P2  
**Gap teknis:** Multi-source demand consolidation and positive runtime acceptance incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Existing requisition schema/RPC plus source/destination allocations and conversion refs.
- **Otorisasi:** Requester location scope; approver by amount/category; destination immutable.
- **UI:** Draft, submit, consolidate, approve and convert to PO.
- **Test:** Duplicate request, cross-branch, partial consolidation and duplicate PO conversion.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Consolidated PO quantities map exactly back to originating requisitions.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D07-F05 — Purchase order lifecycle draft → submit → approve → ordered

**Domain:** Procurement & Supplier  
**Priority:** P1/P2  
**Gap teknis:** Amendment, supplier acknowledgement and idempotent issue not fully accepted.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** PO header/lines/version, approval, supplier acknowledgement and transition RPC.
- **Otorisasi:** Requester/approver/buyer separation; supplier scoped to own PO.
- **UI:** PO composer, approval, issue, acknowledge, amend/cancel.
- **Test:** Illegal transition, stale version, duplicate issue and supplier mismatch.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Approved PO issued once; acknowledgement references exact PO version; receiving validates PO.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D07-F06 — Approval limits by value/category

**Domain:** Procurement & Supplier  
**Priority:** P1/P2  
**Gap teknis:** Configurable thresholds, delegation and escalation not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Approval policies, category/value thresholds, effective dates and delegated approvers.
- **Otorisasi:** Policy admin only; approver role/scope and maker-checker enforced.
- **UI:** Policy matrix and threshold editor with history.
- **Test:** Boundary amounts, policy changed while pending, expired delegation and self-approval.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Requests at different amounts/categories route to correct approver; out-of-policy decisions denied.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D08-F01 — Branch directory, status, timezone and assignments

**Domain:** Branch Operations  
**Priority:** P1/P2  
**Gap teknis:** Branch readiness and 150-branch assignment consistency not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Existing branches, tenant membership, timezone and assignment entities; validation RPC.
- **Otorisasi:** Server derives tenant; branch manager own branch; HQ authorized tenant-wide.
- **UI:** Directory, status, timezone, region, manager and readiness.
- **Test:** Duplicate code, invalid timezone, inactive branch and cross-tenant assignment.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** All fixture branches have valid tenant/timezone/assignment and cross-tenant access is denied.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D08-F02 — Opening and closing checklists

**Domain:** Branch Operations  
**Priority:** P1/P2  
**Gap teknis:** Checklist-to-operating-state linkage and sign-off acceptance incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Checklist templates/versions, runs, item results, evidence and sign-off.
- **Otorisasi:** Assigned staff; critical items require supervisor review.
- **UI:** Opening/closing checklist with blockers and evidence.
- **Test:** Missing critical item, template change, unauthorized sign-off and duplicate close.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Branch cannot be marked ready/closed with incomplete critical checklist; audit is complete.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D08-F05 — SOP and work instructions

**Domain:** Branch Operations  
**Priority:** P1/P2  
**Gap teknis:** Version-controlled SOP publication, effective dates and acknowledgements not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** SOP documents/versions, applicability, effective dates and acknowledgements.
- **Otorisasi:** HQ/quality publishes; branch staff read applicable versions only.
- **UI:** SOP library, search, version history and acknowledgement.
- **Test:** Superseded SOP, unauthorized publish and acknowledgement replay.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Each assigned staff acknowledges the effective SOP version; prior version remains immutable.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D08-F06 — Cleanliness, equipment and safety checks

**Domain:** Branch Operations  
**Priority:** P1/P2  
**Gap teknis:** Inspection evidence, thresholds and corrective action closure incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Inspection templates, equipment refs, measurements, evidence assets and corrective actions.
- **Otorisasi:** Assigned inspector; critical finding escalated; private tenant/branch Storage.
- **UI:** Inspection checklist, photo evidence, failed item and corrective action.
- **Test:** Out-of-range value, missing evidence, wrong equipment and unauthorized download.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Critical finding cannot close until authorized verification and private evidence retention is proven.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D10-F03 — Customer segments

**Domain:** CRM, Loyalty & Marketing  
**Priority:** P1/P2  
**Gap teknis:** Versioned segment rules, refresh and reproducible membership absent/unproven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Segment definitions/rules, membership snapshots, refresh runs and source watermarks.
- **Otorisasi:** CRM admin manages rules; customer data scope/consent and tenant isolation enforced.
- **UI:** Segment builder, preview, member count and refresh history.
- **Test:** Duplicate customer, opt-out, stale source, rule version and cross-tenant.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Membership snapshot is reproducible from reconciled source data and rule version.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D10-F05 — Rewards and vouchers/coupons

**Domain:** CRM, Loyalty & Marketing  
**Priority:** P1/P2  
**Gap teknis:** Eligibility, lifecycle, expiry, reversal and positive staging persistence not fully accepted.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Existing reward/voucher ledger, issuance/redemption/expiry/reversal and audit RPC.
- **Otorisasi:** Customer owns reward; staff permissions; server validates eligibility and redemption.
- **UI:** Reward catalog, issue, redeem, expiry and reversal history.
- **Test:** Expired/ineligible, double redemption, refund after redemption and cross-tenant.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Voucher redeemed once; refund/reversal adjusts ledger correctly without duplicate points or liability.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D11-F01 — Finance overview, expenses and approvals

**Domain:** Finance & Accounting  
**Priority:** P0  
**Gap teknis:** Overview not reconciled across journals, cash, settlement and expenses.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Expenses, approvals, journals, cash/bank and settlements with source lineage.
- **Otorisasi:** Finance role tenant/branch scope; approval thresholds and maker-checker.
- **UI:** Finance dashboard, expense queue, cash position and variance.
- **Test:** Unposted expense, duplicate approval, cross-branch and journal mismatch.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Every dashboard amount traces to expense/journal/settlement sources and totals reconcile.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D11-F04 — AR/AP subledgers and aging

**Domain:** Finance & Accounting  
**Priority:** P0  
**Gap teknis:** Subledger lifecycle and control-account tie-out incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Receivables/payables, invoices, allocations, due dates, aging and GL refs.
- **Otorisasi:** Finance scope; write-off/payment approvals separated.
- **UI:** Partner balances, invoice aging, payment allocation and disputes.
- **Test:** Partial/overpayment, duplicate allocation, credit note and write-off.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** AR/AP balances and aging equal invoice less applications/credits; control accounts tie to GL.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D11-F08 — Tax and invoicing

**Domain:** Finance & Accounting  
**Priority:** P0  
**Gap teknis:** Tax calculation, effective rates, numbering and compliance acceptance incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Tax codes/rates, effective dates, invoice sequence/snapshot, tax lines and credit notes.
- **Otorisasi:** Tax admin restricted; issued invoice immutable; credit note approval.
- **UI:** Tax config, invoice preview/issue, void and credit note.
- **Test:** Inclusive/exclusive tax, rounding, effective rate and duplicate number.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Invoice total equals net plus tax under policy; unique invoice and journal reconciliation.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D11-F11 — Period close/reopen and backdated posting controls

**Domain:** Finance & Accounting  
**Priority:** P0  
**Gap teknis:** Close/reopen snapshots, lock and late-posting controls not fully accepted.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Fiscal periods, close checklist/hash, reopen request/approval and posting guard RPC.
- **Otorisasi:** Finance controller closes; independent approval reopens; backdate permission restricted.
- **UI:** Period status, blockers, close checklist and reopen request.
- **Test:** Posting to closed period, concurrent close, reopen denial and late transaction.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Close reproducible and locked; backdated posting denied or approved/audited by policy.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D15-F01 — User/admin profiles, roles and permission actions

**Domain:** Admin, Identity & Access Control  
**Priority:** P0  
**Gap teknis:** Profile/role mutation and lifecycle workflows not fully evidenced.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Admin profiles, roles, permission grants, session/recovery entities and audit.
- **Otorisasi:** Official Auth Admin path; privileged claims server-side; deny by default.
- **UI:** User directory, role/scope editor and lifecycle controls.
- **Test:** Owner/non-owner, inactive, banned, session and privilege escalation tests.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Only authorized admin can change role; JWT refresh reflects claim and audit is complete.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D15-F02 — Branch assignments and scope enforcement

**Domain:** Admin, Identity & Access Control  
**Priority:** P0  
**Gap teknis:** Branch assignment consistency across UI/API/RLS not fully accepted.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** User-branch memberships, tenant/branch composite relations and scope RPC.
- **Otorisasi:** Scope resolved from verified membership; client-supplied branch never trusted.
- **UI:** Branch assignment management and effective-access preview.
- **Test:** Cross-branch read/write, removed membership, stale JWT and direct API.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Tenant A/B and branch A/B positive-own/negative-cross access tests pass.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D15-F03 — Owner/manager/no-permission/inactive identity probes

**Domain:** Admin, Identity & Access Control  
**Priority:** P0  
**Gap teknis:** Full identity matrix against every protected endpoint not complete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Existing Auth/admin_profiles/allowlist and endpoint policy inventory.
- **Otorisasi:** Owner explicit allowlist plus profile; manager scoped; inactive/unknown denied.
- **UI:** Access-denied states and authorized navigation only.
- **Test:** Owner positive, manager allowed scope, no-role, inactive, banned and cross-tenant.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Exact staging HEAD passes positive and negative matrix on API, RPC, Storage and UI.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D15-F04 — Audit logs for sensitive actions

**Domain:** Admin, Identity & Access Control  
**Priority:** P0  
**Gap teknis:** Coverage and tamper-resistant linkage across sensitive operations incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Append-only audit events with actor, target, before/after, reason and request correlation.
- **Otorisasi:** Audit write server-side; clients cannot update/delete; access restricted.
- **UI:** Audit viewer with filters and entity drill-down.
- **Test:** Missing audit, actor spoofing, direct mutation and rollback consistency.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Every sensitive test action has one immutable correlated audit event.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D15-F05 — Delegated approvals and separation of duties

**Domain:** Admin, Identity & Access Control  
**Priority:** P0  
**Gap teknis:** Delegation policy, expiry, limits and maker-checker not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Delegation grants, approval policy, effective dates and decision history.
- **Otorisasi:** No self-approval; delegated role cannot exceed delegator; scope bounded.
- **UI:** Delegation editor and approval inbox with delegated actor indicator.
- **Test:** Expired/revoked delegation, self-approval, scope escalation and race.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Delegated approval succeeds only within scope/time/limit; all decisions audited.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D15-F08 — API/database deny-by-default and direct-table protection

**Domain:** Admin, Identity & Access Control  
**Priority:** P0  
**Gap teknis:** Full endpoint/RPC/table ACL parity and negative probes incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** RLS policies, function EXECUTE grants, table grants and Storage policies.
- **Otorisasi:** No public privileged function; authenticated role alone is insufficient; explicit policy.
- **UI:** UI hides unavailable actions but server/database remains enforcement point.
- **Test:** Anon/authenticated direct table/RPC denial, service-role boundaries and regression.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Unauthorized direct REST/RPC/Storage requests denied on exact staging HEAD.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D15-F09 — Cross-tenant isolation

**Domain:** Admin, Identity & Access Control  
**Priority:** P0  
**Gap teknis:** Tenant A/B and branch A/B acceptance needs exact-head API/UI/Storage proof.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Tenant/branch keys, composite FKs, RLS, scoped RPCs and private Storage policies.
- **Otorisasi:** Tenant from verified claims/membership; reject client tenant spoofing.
- **UI:** Tenant-scoped UI and clear denial for cross-tenant resources.
- **Test:** A/B read/write denial, branch isolation, upload/download denial and IDOR.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** All tenant A/B and branch A/B positive/negative E2E and data reconciliation pass.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D15-F10 — Permission changes are themselves audited

**Domain:** Admin, Identity & Access Control  
**Priority:** P0  
**Gap teknis:** Atomic permission mutation + audit + rate limit and rollback not fully accepted.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Permission mutation RPC, immutable audit event and rate-limit record.
- **Otorisasi:** Only platform/tenant admin within authority; self-escalation denied.
- **UI:** Permission change confirmation and audit detail.
- **Test:** Audit failure rollback, rate limit, self-grant, duplicate request and concurrency.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Each successful change has one audit event; failed/auditless changes roll back.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D17-F01 — Edge Function API and payment proof flow

**Domain:** Integrations & Automation  
**Priority:** P0  
**Gap teknis:** Protected action authz and provider proof lifecycle not fully proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Existing Edge Functions, payment proof, webhook inbox and idempotency records.
- **Otorisasi:** JWT/role/tenant/branch authorization per protected action; provider signature verified.
- **UI:** Payment proof submit/status/retry and error handling.
- **Test:** Missing/invalid JWT, wrong tenant, invalid proof, replay and duplicate callback.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Valid payment proof advances correct sale once; all unauthorized and replay attempts denied.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D17-F08 — Secret storage and rotation

**Domain:** Integrations & Automation  
**Priority:** P0  
**Gap teknis:** Rotation cadence, dual-key transition and runtime verification not evidenced.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Supabase/GitHub/Vercel secret references and rotation audit metadata; no secret values in DB/UI.
- **Otorisasi:** Secrets server-only, least privilege, no logs/client exposure.
- **UI:** Admin-safe secret status/rotation runbook; never display values.
- **Test:** Old/new key overlap, revoked key, leaked output scan and service availability.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Rotation test confirms new credential works, old is revoked, and no secret appears in logs/build/client.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D18-F05 — Leaked-password protection

**Domain:** Quality, Compliance & Security  
**Priority:** P1/P2  
**Gap teknis:** Auth configuration and enforcement evidence not captured.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Supabase Auth password protection configuration and audit/check evidence.
- **Otorisasi:** Auth provider enforces compromised-password rejection; no client bypass.
- **UI:** Signup/password-change error state with actionable message.
- **Test:** Known compromised password rejected; acceptable password succeeds; no secret logging.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Staging Auth configuration evidence and negative/positive signup/password-change test.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D18-F09 — Monitoring, system health and incident runbooks

**Domain:** Quality, Compliance & Security  
**Priority:** P1/P2  
**Gap teknis:** Operational SLOs, alert routing and tested incident procedures incomplete.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Health checks, alert events, incident records, deployment and DB telemetry references.
- **Otorisasi:** Operational access restricted; incident actions audited.
- **UI:** Health dashboard, alert acknowledgement and runbook links.
- **Test:** Synthetic outage, alert dedup, escalation, recovery and unauthorized access.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Injected staging incident is detected, routed, acknowledged, recovered and postmortem evidence retained.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.

## D18-F15 — Forecast-to-Production

**Domain:** Quality, Compliance & Security  
**Priority:** P1/P2  
**Gap teknis:** Forecast data, production planning integration and variance loop not proven.

- **File/modul:** inspect current code ownership and overlapping PRs first; extend the existing domain module. Any new module path must be agreed in the implementation PR, not assumed to exist.
- **Database/RPC:** Forecast versions, demand inputs, production plans, actual output/consumption and variance.
- **Otorisasi:** Planner scoped by tenant/branch; approval for material plan overrides.
- **UI:** Forecast, planned batches, capacity/material readiness and actual-vs-plan.
- **Test:** Stale forecast, missing source, stock constraint, plan revision and duplicate run.
- **E0–E6:** apply the mandatory evidence gates above. **E6 acceptance:** Forecast produces explainable plan; actual production/consumption variance reconciles to source ledgers.
- **Status awal:** NOT VERIFIED; do not change status until evidence is linked.
