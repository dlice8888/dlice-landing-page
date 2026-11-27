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
