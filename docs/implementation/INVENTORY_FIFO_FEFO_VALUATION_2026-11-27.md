# Inventory & Warehouse — FIFO/FEFO and Valuation (2026-11-27)

## Feature IDs started
- D06-F05 — FIFO/FEFO, lot/batch and expiry.
- D06-F10 — Stock valuation.

## Implemented
`src/inventory-lot-valuation-workflows.mjs` adds:
- FIFO and FEFO lot selection with tenant/branch/item validation, expiry cutoff and deterministic tie-breaking;
- fail-closed allocation when unexpired available quantity is insufficient;
- historical inventory valuation snapshots using remaining lot layers and an approved FIFO/weighted-average policy;
- transactional allocation and valuation persistence adapters with idempotency and audit.

Contract tests cover FEFO/FIFO ordering, expiry exclusion during allocation, insufficient quantity, cross-tenant lot rejection, historical cutoff, and persistence contracts.

## Remaining acceptance
- Canonical lot/batch schema, expiry dates, quarantine/release, recall lineage and immutable stock movement migration.
- RLS, same-tenant/branch predicates and approved inventory policy versioning.
- Concrete Supabase repository adapters and authenticated Edge Function/RPC routes.
- Reconcile allocation layers against POS recipe consumption, production, transfers, returns, waste and stock counts.
- Define accounting treatment for expired/quarantined stock, impairment/write-off and valuation adjustments; valuation snapshot must reconcile to Finance GL.
- Staging E2E with duplicate allocation, concurrency, lot expiry, recall and branch isolation.
