# Procurement & Supplier — Price, Consolidated Demand and Returns (2026-11-27)

## Feature IDs started
- D07-F02 — Supplier price lists, contracts and price history.
- D07-F04 — Consolidated demand across branches.
- D07-F10 — Supplier return and supplier performance (return workflow started; scorecard remains open).

## Implemented source
`src/procurement-supplier-workflows.mjs`:
- selects approved effective supplier prices by tenant, supplier, item, branch, date and minimum quantity; rejects ambiguous competing contracts;
- consolidates branch demand by tenant/item/base unit and nets available stock, reservations, safety stock and open purchase orders;
- requests returns only against received, not-yet-returned GRN quantities and derives credit value from the approved receipt price;
- requires independent supplier-return approval, then posts stock reversal and AP credit evidence atomically.

Contract tests cover effective-date selection, ambiguous price conflicts, cross-tenant demand rejection, net-demand calculation, receipt quantity limits, cross-branch denial, independent approval and stock/AP posting.

## Remaining acceptance
- Persist contract versions, effective price lists, currency/tax and supplier/branch entitlement in canonical Supabase schema.
- Add RLS, immutable price history and approved supplier-link policies.
- Connect authoritative forecast, inventory reservation, open PO and GRN data sources.
- Add concrete Supabase repository adapter and authenticated RPC/Edge Function routes.
- Integrate PO, goods receipt, quality inspection, supplier invoice, AP credit note and bank settlement.
- Add supplier return reason codes, inspection, logistics and credit-note reconciliation.
- Implement supplier scorecard from measured OTIF, defects, returns, invoice variance and response SLA.
- Test two tenants and multiple branches in disposable database and staging E2E.

Implementation-start only; no schema migration or live database mutation in this batch.
