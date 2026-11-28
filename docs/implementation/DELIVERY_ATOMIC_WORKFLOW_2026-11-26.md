# Delivery atomic workflow implementation — 2026-11-26

Status: implementation increment in PR #145. This is not a migration or release approval.

## Dependency order

1. DELIVERY_FULFILLMENT_SCHEMA_DRAFT.sql — dispatch, provider event and proof-of-delivery base entities.
2. DELIVERY_PROVIDER_STORAGE_SCHEMA_DRAFT.sql — provider config/quotes, private-storage evidence metadata, cost reconciliation and outbox.
3. DELIVERY_ATOMIC_ADAPTERS_EXTENSION_DRAFT.sql — booking, verified-event application, outbox claims/results and Finance cost reconciliation.
4. src/supabase-delivery-adapter.mjs — one RPC call per state-changing operation.
5. src/workers/delivery-outbox-worker.mjs — injected carrier adapter and secret resolver; no hardcoded provider or credential.

All SQL remains a draft. No hosted staging schema was changed.

## Atomic workflow

- Provider configuration is requested as pending and requires a different Platform Owner to approve it.
- Quotes are limited to paid/verified/settled orders in ready fulfillment state, tenant/branch scoped, expire within two hours and use idempotency keys.
- Booking locks the quote, order and dispatch scope; it creates a pending provider booking plus one outbox job in the same transaction. Order fulfillment changes to dispatched only as part of this DB transaction.
- The worker claims jobs using FOR UPDATE SKIP LOCKED. It obtains only a secret reference from the database; the caller resolves the secret from a secret store and supplies a provider adapter. The provider request reuses the outbox idempotency key.
- Provider success/failure is committed through a separate atomic result RPC. Transient failures retry; a dead-lettered booking closes the dispatch as failed.
- Webhook application requires a verified signature flag, stable provider event ID, payload SHA-256 and valid state transition. Delivered status requires proof-of-delivery metadata.
- Cost reconciliation requires a delivered, confirmed dispatch and a matching posted Finance journal entry with source type, source ID, branch and exact amount. COD, merchant subsidy, courier cost, provider fee and settlement are compared; mismatches are recorded as exceptions. Reconciliation evidence is append-only.

## Authorization and data boundaries

- The Edge actions are Platform Owner-only while tenant release remains locked, then check the requested branch using the authenticated actor's existing branch access helper and derive tenant ID from the branch row.
- RPCs revoke PUBLIC, anon and authenticated execution and grant only service_role.
- Evidence tables reject UPDATE/DELETE. Provider credentials are never stored as plaintext; only a secret reference is persisted.
- Provider network calls are not made from SQL or browser code.

## Verification added

- delivery-atomic-adapter-worker.test.mjs: adapter RPC boundaries and worker fail-closed behavior.
- delivery-sql-contract.test.mjs: SQL dependency, state-transition, immutability, ACL and Edge authorization source contracts.
- eight-domain-sql-delimiter-contract.test.mjs: balanced dollar-quoted SQL function bodies including the new Delivery extension.
- tenant-runtime-probe-contract.test.mjs and runtime probe inventory are aligned to 214 actual admin/ERP actions.

The GitHub connector has not exposed a current Actions run for the latest PR head; the only combined status currently visible is a Vercel build-rate-limit failure. Therefore these contracts are wired into CI but are NOT YET OBSERVED PASSING.

## Remaining blockers

- No carrier account credentials, provider webhook secret, approved provider fixture or carrier sandbox transaction is configured.
- A scheduled/hosted worker invocation and private Storage upload/download E2E still need wiring and evidence.
- The customer delivery completion notification workflow still needs an outbox/template/provider receipt integration.
- Apply nothing to staging until exact-head disposable SQL replay, pgTAP, Edge typecheck, E2E and reconciliation pass and are reviewed.
