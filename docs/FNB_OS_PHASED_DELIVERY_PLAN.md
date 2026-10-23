# D’Lice FnB OS — Phased Delivery Plan

## Guardrails

- Implement in staging and feature branches only.
- Never merge or deploy production before acceptance tests pass and the Owner explicitly approves.
- Treat every mutation as auditable; require branch assignment scope and server-side authorization.
- Prefer atomic database functions for multi-row inventory, payment, fulfillment, and accounting transitions.
- Use idempotency keys for retryable create/transition requests and optimistic concurrency where operators edit shared records.
- A green static test is not evidence of end-to-end operational readiness. Record browser, role/branch, reconciliation, recovery, and load evidence separately.

## P1 — Core commerce and operations

**Scope:** POS/order/payment/fulfillment; menu and versioned recipes; KDS; inventory ledger; stock transfer/count; PR/PO/GRN; shifts and cash control.

**Acceptance gates**
1. Order lifecycle is traceable from cart/checkout through payment, fulfillment, stock consumption, and settlement.
2. Repeated submissions/retries do not duplicate sales, stock movements, receipts, or payment transitions.
3. Stock transfer reduces source stock only on ship and increases destination stock only on receive; both entries link to the same transfer.
4. Stock count cannot post until every line has a physical count; posting atomically reconciles balances and records variance movements.
5. PO/GRN quantity, received amount, stock movement, and audit event reconcile.
6. Shift open/close and cash variance are branch-scoped and auditable.

**Current work slice:** server-side stock transfer lifecycle and cycle-count posting, with branch-scoped UI, ledger movement entries, idempotent create keys, and restricted database access. This slice is implemented in the feature branch but is **not staging-accepted** until the migration is applied, the Edge Function is deployed, and authenticated branch-role E2E is run.

## P2 — Finance, people and controls

**Scope:** COA, balanced journal entries, AP/AR, bank and settlement reconciliation, period close, branch P&L, workforce and payroll integration.

**Acceptance gates**
1. Every posted journal balances (debits equal credits); posted entries are immutable and corrections reverse rather than overwrite.
2. Payment-provider fees, bank receipts, refunds, and settlement variances reconcile by source transaction.
3. AP/AR aging reconciles to control accounts and subledgers.
4. Fiscal-period close blocks backdated posting unless an authorized reopen is audited.
5. Branch P&L reconciles to sales, COGS, labor, discounts, waste, fees, and expenses.
6. Payroll integration is idempotent and maps approved attendance/payroll runs to accounting entries.

## P3 — Intelligence and automation

**Scope:** command center, canonical KPI definitions, alert/approval routing, CRM/loyalty, forecasting, delivery integrations, retry/idempotency.

**Acceptance gates**
1. Each KPI has a formula, timezone, refresh SLA, owner, and source-of-truth definition.
2. Alerts have severity, owner, escalation/acknowledgement state, and audit history.
3. Delivery webhooks and outbound actions are signature-verified where supported, deduplicated, retried with backoff, and dead-lettered after exhaustion.
4. Forecasts expose source data, horizon, accuracy tracking, and human override history.
5. Loyalty balances and redemptions are ledgered; duplicate events cannot double-credit or double-redeem.

## P4 — SaaS and 150-branch scale

**Scope:** tenant isolation, onboarding, plans/entitlements, usage/billing, support/offboarding, load tests, backup/restore drills, pilot branches.

**Acceptance gates**
1. Cross-tenant read/write isolation is proven with adversarial tests for every exposed data path.
2. Onboarding/offboarding is repeatable, audited, and does not require undocumented manual SQL.
3. Plans/entitlements are enforced server-side; usage and billing records are deduplicated and reconcilable.
4. Capacity tests use realistic 150-branch workload profiles and publish latency/error/queue targets.
5. Backup restoration is rehearsed in an isolated environment; RPO/RTO are measured and approved.
6. Pilot branches complete real operating-day reconciliation before wider rollout.

## Current known release blockers

- The staging Edge Function CORS allowlist must include the current feature preview origin before browser acceptance.
- Owner, branch manager, no-permission, and inactive test identities/secrets must be provisioned in GitHub Environment before authenticated P0/P1 E2E.
- The new stock workflow migration and matching Edge Function version must be applied/deployed together; frontend-only deployment is not sufficient.
- No evidence yet certifies 150-branch capacity, cross-tenant isolation, backup restore, or production readiness.


## P1 slice — Purchase Requisition (PR #36, staging candidate)

### Scope
- Branch-scoped purchase requisition with multiple inventory item lines, requested quantities, estimated unit costs, purpose, needed-by date and notes.
- State machine: `draft → submitted → approved/rejected`; approved requisitions can be converted to a draft purchase order; cancellation is auditable.
- Owner-only approve/reject/convert; the requester or Owner may cancel; every API action requires the procurement permission and server-side branch authorization.
- RLS is enabled on both new tables and direct `anon`/`authenticated` table access is revoked.
- Service-role-only atomic RPCs create header + lines and transition/convert requisitions. Conversion snapshots item names/costs into PO lines and writes an audit event.

### Tests-first and CI
- Contract test: `tests/staging/procurement-requisition-contract.mjs`.
- Workflow: `.github/workflows/procurement-requisition-contract.yml`.
- Contract run [39982985731](https://github.com/dlice8888/dlice-landing-page/actions/runs/39982985731) completed successfully.
- Free quality checks passed the runtime, dependency-free quality, and staging release-contract steps, but the release workflow correctly failed its migration documentation gate until this rollout note was added. Re-run CI after this commit.

### Not yet accepted
- PR #36 is a staging candidate, not yet deployed.
- Apply `20261023170000_purchase_requisitions.sql` to Supabase staging only after PR CI is green.
- Deploy the matching Edge Function source to staging only after the migration succeeds.
- Run authenticated positive and negative tests for requester, Owner, no-procurement-permission user, wrong branch, inactive user, invalid transition, duplicate submit/retry, and conversion.
- Reconcile requisition item totals to generated PO header/lines and confirm audit events.
- Do not claim this slice complete from the contract test alone. No production resources are in scope.


## Post-deploy advisor follow-up — 2026-10-23

- Staging PR #36 merged as `c1c61e2706397576e560d0274d84034959de118f`; migration `20261023170000_purchase_requisitions.sql` applied to staging as migration version `20261023160257`.
- `purchase_requisitions` and `purchase_requisition_items` are both RLS-enabled; read-only privilege checks confirm neither `anon` nor `authenticated` can SELECT them directly.
- Edge Function `dlice-orders` deployed to staging v52 with the three requisition actions; `verify_jwt=false` is preserved and custom per-action authentication/authorization remains in force.
- Supabase Performance Advisor identified an unindexed FK on `purchase_requisitions.converted_purchase_order_id`. Migration `20261023160430_purchase_requisition_conversion_index.sql` adds the targeted partial index. This is a targeted fix; no unused indexes were dropped.
- The contract CI passed, but runtime requisition E2E (authenticated create/submit/approve/convert, generated PO/lines, audit and branch isolation) is still required before marking the slice accepted.
