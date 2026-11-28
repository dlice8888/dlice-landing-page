# Integrations & Automation — Connector, Health and Catalog Sync (2026-11-27)

## Feature IDs started
- D17-F03 — Delivery/e-commerce/WhatsApp/accounting connectors.
- D17-F07 — Integration health and alerting.
- D17-F09 — Import/export and catalog synchronization.

## Implemented
`src/integration-connector-health-sync-workflows.mjs` adds:
- tenant-scoped resolution of approved provider configurations and explicitly approved capabilities;
- vault secret-reference resolution without returning the reference or secret to the caller;
- health classification from persisted authoritative telemetry, with durable alerts for degraded/unhealthy connectors;
- verified import-batch validation, duplicate external-key rejection, conflict detection and atomic catalog application with durable source checkpoint.

Contract tests cover capability boundaries, secret-reference non-disclosure, health classification, authoritative telemetry, cross-tenant catalog rows, duplicate keys, conflict rejection and atomic apply contracts.

## Remaining acceptance
- Provider-specific signed webhook adapters and raw-body verification.
- Production-grade vault/secret manager connection, secret rotation and least-privilege scopes.
- Concrete Supabase repository and outbox adapters; retry/backoff/dead-letter recovery.
- Private integration logs with redaction and retention.
- Provider contract tests for approved delivery, e-commerce, WhatsApp and accounting providers.
- Catalog mapping, unit/tax/currency conversion, conflict review UI and import rollback.
- Scheduled health probes, lag/error dashboards, on-call routing and runbooks.
- Authenticated Edge Function routes and staging tenant A/B tests.
- End-to-end reconciliation of provider order/payment/settlement events into POS, Inventory and Finance.

No external provider has been marked connected. No secrets or live database were changed.
