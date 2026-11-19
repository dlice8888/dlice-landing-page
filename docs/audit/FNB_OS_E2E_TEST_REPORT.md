# FnB OS Operational E2E Test Report

**Snapshot:** 18 November 2026  
**Target:** staging only

## Tenant P01–P09

| Probe | Required behavior | Status |
|---|---|---|
| P01 | Login Worker A and validate session | BLOCKED / NOT RUN |
| P02 | Login Worker B and validate session | BLOCKED / NOT RUN |
| P03 | Different Auth users, active memberships, ordinary worker profile, equal role/permissions, valid branch assignment | BLOCKED / NOT RUN; both profiles are sales_admin; PR #87 adds the corrected assertions |
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

A fresh staging inventory confirms both candidate users have active Auth accounts, distinct tenant memberships, identical `branch_manager` permission sets and no cross-tenant assignment rows. However, both global profile roles are `sales_admin`, and the database constraint currently allows only `sales_admin` and `owner`. They therefore do not yet satisfy the requirement for ordinary workers who are not Admin. Worker A's second assignment is within its own tenant and is valid; PR #87 removes the old exact-one-branch test constraint.

PR #86 adds a safe, Owner-only `branch_worker` classification path. Its migration passed disposable local replay (run 44306779612) but is not applied to staging and no account was changed. PR #87's exact-head quality workflow 44307838730 passed 7/7 tenant runtime contract tests; this is not P03 runtime acceptance. P03 remains BLOCKED.


## Latest staging execution evidence — 2026-11-18

- Tenant isolation run [44207773570](https://github.com/dlice8888/dlice-landing-page/actions/runs/44207773570): 0 PASS / 0 FAILED / 9 BLOCKED / 0 SKIPPED. Preflight accepted the staging URL and public key but found empty values for both worker username/password pairs and Tenant A/B tenant, branch and user IDs. All P01–P09 were recorded BLOCKED with `executed:false`; no authenticated probe ran.
- Existing-identity negative probe [44208204366](https://github.com/dlice8888/dlice-landing-page/actions/runs/44208204366) blocked because canonical Tenant A credentials or Tenant B branch fixture are missing. It explicitly did not create accounts.
- P0 HTTP run [44207773489](https://github.com/dlice8888/dlice-landing-page/actions/runs/44207773489) blocked because Owner QA username/password are absent. No disposable QA bootstrap ran.
- Fresh database inspection found two real active worker candidates, both `sales_admin` profile classifications with `branch_manager` membership and six permissions. Their active assignment counts are one and two, each confined to its own tenant. This is fixture inventory only, not authentication evidence.

All seven operational E2E flows remain PARTIAL / NOT RUN or NOT VERIFIED as shown above. Existing contract tests and CORS probes do not substitute for the positive transaction workflows. No E2E data mutation was initiated in this continuation.


### Canonical QA branch assignment cross-check
A second read-only query confirmed the configured branch fixtures already exist and are actively assigned: tenant `dlice-default` has `QA-DLICE-A` (the same worker also has `DLC-B001`), and tenant `dlice-qa-isolation-b` has `QA-TENANT-B`. Both memberships have role `branch_manager`, six permissions, and the same permission-set fingerprint. The two candidate users are distinct membership rows in different tenants. This confirms branch assignment data is present; it does not provide passwords or prove either login. Populate the canonical GitHub variables from the existing records—do not create substitute tenants, branches, users, or assignments.


## Correction to the prior staging fixture status — 2026-11-18

The earlier wording that Tenant A/B credentials and all six fixture variables were currently "empty/missing" was too broad and is superseded by this correction.

- The user-provided GitHub Environment `staging` inventory already lists the four canonical Tenant A/B username/password secrets and all six Tenant A/B tenant/branch/user variables. The staging acceptance workflow at the exact run commit declares `environment: staging` and references those same names. Therefore the inventory names are present; do not instruct the user to recreate them.
- The historical run [44207773570](https://github.com/dlice8888/dlice-landing-page/actions/runs/44207773570), created 2026-11-18 00:26 UTC, logged empty values for those ten inputs at execution time. This proves that run did not receive their values; it does not establish that the current Environment inventory is empty. The connected GitHub tool cannot inspect decrypted secret values or Environment-scoped variable values, so the reason for the resolution discrepancy is not yet established.
- Read-only Supabase verification now confirms all six configured fixture UUIDs exist in their respective tables and match the intended records exactly: Tenant A `dlice-default` / branch `QA-DLICE-A` / existing user A; Tenant B `dlice-qa-isolation-b` / branch `QA-TENANT-B` / existing user B. No fixture IDs need to be recreated or replaced.
- Both users have active `branch_manager` tenant memberships, six equal permissions, and active assignments within their own tenant. User A has two active same-tenant branches (`DLC-B001` and `QA-DLICE-A`); user B has one (`QA-TENANT-B`). The P03 runtime script on staging still requires exactly one branch for each identity, which incorrectly rejects User A's valid same-tenant second assignment. This is a code/test defect, not a missing assignment.

Next diagnostic: execute a fresh `Staging Tenant Isolation Acceptance` workflow_dispatch on branch `staging` without changing/recreating configuration. If the ten inputs still resolve empty, inspect the exact GitHub Environment scope/name and access settings with repository administration access. Before treating P03 as valid, correct its one-branch-only assertion to require the configured QA branch and reject only cross-tenant visibility. Inventory action authorization must also be repaired/deployed before P04/P06 can prove own-branch reads.


## Latest staging runtime results — 2026-11-20

| Workflow | Run | Result | What actually executed |
|---|---:|---|---|
| Tenant isolation P01–P09 | [44579674471](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674471) | BLOCKED | Preflight only; 9 probes BLOCKED, 0 executed, 0 skipped |
| KDS/POS/Stock positive E2E | [44579674219](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674219) | BLOCKED | Owner credential preflight failed; business-flow step skipped |
| P0 HTTP bootstrap | [44579674185](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674185) | BLOCKED | Owner credential preflight failed; HTTP/security probe step skipped |
| Authenticated tenant negative probes | [44579674333](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674333) | BLOCKED | Tenant A credentials and Tenant B branch fixture missing in runner |
| Staging CORS probes | [44579674771](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674771) | PASS | Runtime CORS probe workflow completed successfully |
| KDS offline contract | [44579674589](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674589) | PASS | Contract/static assertions only; not positive POS transaction E2E |
| Procurement receiving contract | [44579674180](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674180) | PASS | Contract assertions only; not procurement positive E2E |
| Disposable migration replay | [44579674275](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674275) | PASS | 52 migrations replayed locally; 67 pgTAP assertions passed |

The P01–P09 run logs show that the staging URL and publishable key were available, while both Tenant A/B username/password pairs and all six fixture IDs resolved empty. The probes were emitted as BLOCKED with executed:false; the workflow reports 0 skipped. This is not a tenant authorization test result.

The positive KDS/POS/Stock workflow did not reach order creation, payment, KDS, stock consumption, offline replay, or reconciliation. The procurement receiving contract is not a substitute for PR → approval → PO → GRN → stock movement → AP E2E. These operational flows remain NOT RUN.
