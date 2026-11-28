# Executive Command Center — Stock, Expiry, Waste and Anomaly Alerts (2026-11-27)

## Feature IDs started
- D01-F05 — Critical stock, expiry and waste alerts.
- D01-F06 — Sales-drop and food-cost anomaly detection.

## Implemented
`src/executive-stock-waste-anomaly-alerts.mjs` adds:
- critical/low stock alerts from reconciled branch stock facts;
- near-expiry lot alerts using an explicit horizon;
- waste-rate alerts against a governed threshold;
- sales-drop and food-cost increase detection from reconciled comparison windows;
- severity classification and source-branch scoping.

Contract tests cover stockout, expiry, waste, sales drop, food-cost variance and rejection of unreconciled/cross-branch data.

## Remaining acceptance
- Persist alerts, metric definitions, threshold versions and alert action history in canonical Supabase schema/RLS.
- Load authoritative POS net sales, recipe theoretical cost, actual inventory consumption and posted waste from server-side adapters.
- Add regional/company roll-up and branch-to-transaction drill-down with Owner dual authorization.
- Connect alert assign/resolve/verify loop to the BI action workflow and audit.
- Add notification routing, alert deduplication, threshold governance, false-positive tuning and SLA.
- Stage two-tenant/150-branch acceptance and reconcile every alert to source ledgers.


## Reconciled multi-branch Command Center read model — candidate implementation

Added `src/executive-command-center-reconciled-read-model.mjs` and
`tests/contracts/executive-command-center-reconciled-read-model.test.mjs`.

- Reads branch facts only when POS, Finance, Inventory, Delivery, HR and KDS
  source revisions are reconciled and fresh within the configured age limit.
- Rejects cross-tenant/branch facts, duplicate branch rows and unsafe metric values.
- Aggregates only accepted branch facts; missing/stale branches remain explicit
  source gaps and never contribute fabricated totals.
- Reports active/reconciled branch coverage and the 150-branch scale target.
  Status remains partial until all active branches and the expected target count
  are covered.
- Snapshot persistence and audit are required within the same authorized
  tenant transaction.

**Not yet runtime accepted:** canonical server-side adapters and Owner group-read
authorization must be bound to existing POS/Finance/Inventory/Delivery/HR/KDS
tables and verified with tenant A/B and 150-branch staging evidence.
