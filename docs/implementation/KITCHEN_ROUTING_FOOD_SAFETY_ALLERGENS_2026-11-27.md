# Kitchen, Food Safety and Product Allergens (2026-11-27)

## Feature IDs started
- D04-F02 — Station routing (hot/cold/beverage/packing).
- D04-F08 — QC, temperature, shelf life and spoilage.
- D05-F08 — Allergens and regulated product information.

## Implemented
`src/kitchen-routing-food-safety-allergens.mjs` adds:
- approved tenant/branch/category station routing with active station and capacity checks;
- food-safety evaluation against approved branch policy, temperature range, use-by date and allergen/cross-contact requirements; failed checks require quarantine;
- allergen declaration validation derived from same-tenant recipe ingredient allergen metadata, with explicit approved may-contain evidence.

Contract tests cover routing, missing rules, capacity, approved policy, quarantine, expiry and allergen completeness/scope.

## Remaining acceptance
- Canonical kitchen station/routing schema, effective-dated policies, temperature observation and quarantine tables, RLS and immutable evidence.
- Connect KDS dispatch and ticket status transitions to routed station queues.
- Integrate ingredient lot lineage, receipt/production checks, recall and spoilage/waste stock movements.
- Authoritative recipe version and ingredient allergen master, cross-contact policy approval, label/export compliance and product-specific regulatory requirements.
- Private Storage evidence capture and retention, authenticated RPC/Edge adapters and ERP/tablet UI.
- Staging E2E for hot/cold/beverage/packing stations, capacity contention, failed temperature checks and quarantine release.
