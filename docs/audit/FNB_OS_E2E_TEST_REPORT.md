# FnB OS Operational E2E Test Report

**Snapshot:** 18 November 2026  
**Target:** staging only

## Tenant P01–P09

| Probe | Required behavior | Status |
|---|---|---|
| P01 | Login Worker A and validate session | BLOCKED / NOT RUN |
| P02 | Login Worker B and validate session | BLOCKED / NOT RUN |
| P03 | Different Auth users, active memberships, exact tenant and exact one-branch assignment | BLOCKED / NOT RUN; Worker A has 2 active branch assignments |
| P04 | Worker A reads own branch inventory rows | BLOCKED / NOT RUN |
| P05 | Worker A cross-tenant read rejected | BLOCKED / NOT RUN |
| P06 | Worker B reads own branch inventory rows | BLOCKED / NOT RUN |
| P07 | Worker B cross-tenant read rejected | BLOCKED / NOT RUN |
| P08 | Worker A cross-tenant stock-transfer write rejected | BLOCKED / NOT RUN |
| P09 | Worker B cross-tenant stock-transfer write rejected | BLOCKED / NOT RUN |

The last known runtime workflow run `44208204366` stopped during configuration preflight before network access. It is not a failed authorization result and not a PASS. The exact-head Free quality workflow `44303062590` passed but is not runtime acceptance.

## P04/P06 deployed-code blocker

On deployed Edge Function v69, `erp-list-inventory` is rejected by the global uncertified-action guard with HTTP 423 for non-Owner users before branch authorization. Therefore P04/P06 cannot pass against the current deployment even with valid worker credentials. PR #85 changes the candidate handler to require inventory permission, branch ID, active membership and exact active assignment before returning only branch-associated stock rows. Its static quality CI passed (44304941471), but the PR is not merged/deployed and no P04/P06 runtime request has been made.

## Required operational flows

| # | Flow | Current status | Missing evidence |
|---:|---|---|---|
| 1 | POS → Order → Payment → KDS → Recipe Consumption → Inventory Ledger → Shift Closing → Finance Reconciliation | PARTIAL / NOT RUN | Positive browser/API workflow, source-to-ledger quantities and amounts, idempotency, concurrency, rollback |
| 2 | Procurement Request → Approval → PO → Goods Receipt → Stock Movement → AP | PARTIAL / NOT RUN | Manual positive E2E not dispatched; Owner approval, GRN, stock delta, AP reconciliation |
| 3 | Inventory Transfer → Approval → Shipping → Receiving → Reconciliation | PARTIAL / NOT RUN | Full state transitions, cross-tenant denial, ledger/balance invariants |
| 4 | Waste Recording → Stock Adjustment → Audit Trail | PARTIAL / NOT RUN | Real fixture, one stock movement, exact before/after quantity, audit event |
| 5 | Refund and Void → Approval → Payment Reconciliation | PARTIAL / NOT RUN | Full refund/void state machine and payment-provider/source reconciliation |
| 6 | Offline POS → Queue → Idempotent Replay → Duplicate Prevention | NOT VERIFIED | Browser fault injection, replay after restart, duplicate/concurrency assertions |
| 7 | Branch Reporting → Regional Reporting → Owner Consolidated Dashboard | PARTIAL / NOT RUN | Trusted Owner auth, branch-to-region totals, source transaction reconciliation |

Historical workflow #31 reported 21 authorization/role checks PASS; its own description says that is not positive-path purchase-to-stock or order-to-cash E2E. It does not close the above flows.

## Required assertions for every transaction

- Record before/after inventory, payment, receivable/payable and journal balances.
- Prove atomic commit or rollback; no partial side effects.
- Prove idempotent retry and concurrent duplicate prevention.
- Capture request/response status, masked actor/tenant/branch, timestamp, run ID and commit SHA.
- Never record credentials, JWTs, publishable secrets or payment proof content in logs.

## Additional P03 identity blocker

A fresh staging inventory confirms both candidate users have active Auth accounts, distinct tenant memberships, identical `branch_manager` permission sets and no cross-tenant assignment rows. However, both global profile roles are `sales_admin`, and the database constraint currently allows only `sales_admin` and `owner`. They therefore do not yet satisfy the requirement for ordinary workers who are not Admin. Worker A also has two active same-tenant branch assignments versus the exact-one P03 fixture requirement.

PR #86 adds a safe, Owner-only `branch_worker` classification path. Its migration is not applied and no account was changed. P03 remains BLOCKED.
