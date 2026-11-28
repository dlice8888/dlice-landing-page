# BI & Analytics — Forecasting, Scheduled Reports and Alert Closure (2026-11-27)

## Feature IDs started
- D14-F07 — Demand forecasting and accuracy monitoring.
- D14-F09 — Export and scheduled executive reports.
- D14-F10 — Alert → action → measured outcome.

## Implemented
`src/bi-forecast-report-alert-workflows.mjs` adds:
- deterministic weighted-moving-average forecast from same-tenant reconciled daily actuals, with bounded 1–28 day horizon;
- WAPE and forecast bias evaluation from published forecasts paired with reconciled actuals;
- forecast publication from an approved model and authoritative repository adapter;
- scheduled report creation from approved report definitions and active same-tenant recipients;
- KPI alert lifecycle open → assigned → resolved → independently verified, with measured reconciled improvement required for verification.

Contract tests cover invalid/unreconciled data, duplicate dates, cross-tenant rows/recipients, approved models, report definitions, and independent alert verification.

## Remaining acceptance
- Canonical DB migration for forecast runs, model versions, forecast accuracy observations, report definitions/schedules and alert action evidence.
- RLS, tenant/branch scoping and append-only audit history.
- Concrete source adapters for POS, Order, Inventory, Payroll and Finance; approved metric lineage and freshness watermarks.
- Forecast backtesting, seasonal model evaluation, overrides and accuracy thresholds by item/branch.
- Secure private export generation, signed download URLs, retention, recipient consent and delivery retries.
- Alert assignment UI, SLA timers, escalation and measured outcome dashboards.
- Staging multi-tenant E2E and reconciliation against source ledgers.

Implementation-start only; no schema or live database mutation.
