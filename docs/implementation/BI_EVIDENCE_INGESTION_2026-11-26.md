# BI evidence-first ingestion workflow — 2026-11-26

Status: implementation increment in PR #145. Draft SQL only; no hosted migration.

## Processing flow

1. The ingestion worker receives a tenant, explicit period, active metric definitions, source collectors and a calculator. No cross-tenant aggregation is permitted by the worker contract.
2. For each declared source entity, the worker records a tenant-scoped source watermark with source window, maximum source update time, expected count, observed count and stable ingestion run ID. Missing expected counts or count mismatches are recorded as partial, never complete.
3. The worker calculates the metric and expected/observed reconciliation totals, then creates a pending reconciliation run.
4. The worker creates a draft snapshot referencing all source watermark IDs and the pending reconciliation ID. It never reviews or publishes its own work.
5. A separate Platform Owner reviewer can pass/fail/waive the reconciliation. Passing requires variance within tolerance and a reviewer different from the run creator; waiver requires a reason.
6. A separate publisher can publish a snapshot only after lineage, source completeness/freshness and passed reconciliation checks succeed. The publisher must differ from the snapshot creator.

## Database and code

- BI SQL adds idempotent RPCs for source watermark recording, reconciliation creation/review, metric source lineage approval and draft snapshot creation.
- Existing publish RPC and trigger validate source lineage, formula version, tenant-scoped watermark IDs, freshness, expected-vs-observed completeness and passed reconciliation periods.
- Every write appends audit evidence in the same transaction.
- Supabase adapter invokes one RPC per state change.
- Worker accepts injected source collectors and metric calculator; it returns pending_review and never publishes.
- Edge actions are Platform Owner gated and scope reconciliation/snapshot reads to the selected tenant.
- ERP UI now lists draft/published snapshots, allows reconciliation review and publishes only after database guards pass.

## Not yet proven

- No scheduled invocation, source collector implementation for POS/Order/Finance/Inventory/HR, or actual metric formulas/lineage catalog is deployed.
- No exact-head CI run, disposable SQL replay, pgTAP, staging E2E or tenant data reconciliation is observed.
- Forecasting, cohort benchmarking, anomaly detection, controlled exports and scheduled executive reports remain separate gaps.
