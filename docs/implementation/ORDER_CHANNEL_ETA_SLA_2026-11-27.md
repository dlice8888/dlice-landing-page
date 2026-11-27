# Order Management — External Channels, Preparation ETA and SLA (2026-11-27)

## Feature IDs started
- D03-F02 — WhatsApp, marketplace and additional channels.
- D03-F08 — Preparation ETA and exception escalation.

## Implemented
`src/order-channel-eta-workflows.mjs` adds:
- normalization of provider-verified, replay-checked external orders to canonical IDR order facts;
- idempotent ingestion from verified provider events and approved product/branch mappings;
- station-based preparation ETA using approved prep standards, queue telemetry and approved buffers;
- durable SLA escalation when estimated ready time exceeds the order SLA.

Contract tests cover provider authenticity, cross-branch denial, mapping approval, station workload aggregation and SLA escalation.

## Remaining acceptance
- Provider-specific webhook raw-body signature verification, timestamp/replay window and retry/outbox.
- Actual WhatsApp/marketplace credentials and approved provider contracts; no provider is marked connected yet.
- Product/branch mapping UI, customer identity/consent and duplicate-order resolution.
- Canonical order tables/RLS, Supabase adapters and authenticated Edge Function endpoints.
- ETA recalculation on every KDS queue/status change, customer notification and exception ownership/escalation SLA.
- POS/Order/Delivery/Settlement/Finance reconciliation and tenant A/B staging E2E.
