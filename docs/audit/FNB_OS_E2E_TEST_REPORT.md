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

The current P01–P09 fixture contract expects sales_admin as the global profile role and branch_manager as the tenant membership role. Both existing Supabase identities satisfy these database prerequisites; their live login and authorization probes remain NOT RUN. Worker A's second assignment is within its own tenant and is valid; PR #87 removes the old exact-one-branch test constraint.

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


## Superseding E2E status — 21 November 2026, 19:42 WIB

### Tenant A/B P01–P09

| Probe | Required behavior | Current status | Evidence / blocker |
|---|---|---|---|
| P01 | Authenticate existing Tenant A Auth identity | NOT RUN | Existing Auth user and magic-link path implemented in PR #126; protected staging service-role secret and workflow dispatch still required |
| P02 | Authenticate existing Tenant B Auth identity | NOT RUN | Same as P01 |
| P03 | Distinct users, active memberships, matching tenant permissions and correct branch assignments | DB FIXTURE VERIFIED; runtime probe NOT RUN | Read-only joins confirm separate tenants/branches, active memberships and identical six-item tenant permission sets |
| P04 | Tenant A reads own branch inventory | NOT RUN | Membership includes inventory permission; no authenticated Edge Function request executed |
| P05 | Tenant A cross-tenant inventory read denied | NOT RUN | No authenticated negative request executed |
| P06 | Tenant B reads own branch inventory | NOT RUN | No authenticated Edge Function request executed |
| P07 | Tenant B cross-tenant inventory read denied | NOT RUN | No authenticated negative request executed |
| P08 | Tenant A cross-tenant stock-transfer write denied | NOT RUN | No authenticated negative request executed |
| P09 | Tenant B cross-tenant stock-transfer write denied | NOT RUN | No authenticated negative request executed |

P01–P09 have not been dispatched on the current passwordless workflow. The job is manual-dispatch-only and has `if: github.ref == 'refs/heads/staging'`; integrate/reconcile the workflow into staging through the authorized staging path after required tests pass, verify the protected Environment and service-role secret, then dispatch from staging. Do not select a feature branch; the job condition would not run. No credential values were read or logged.

### Transaction E2E work

| Flow | Code/contract evidence | Live E2E status | Required next proof |
|---|---|---|---|
| Online checkout retry (PR #123) | Exact-head CI + disposable replay PASS | NOT RUN | Drop committed HTTP response, retry same idempotency key, concurrent duplicate requests, verify one order/reservation |
| Unpaid reservation expiry (PR #125/#127) | Exact-head CI + disposable replay PASS | NOT RUN | Install only after approval; run worker against disposable/live-approved fixture; prove expiry and no-proof compensation |
| Payment proof upload (PR #127) | Atomic proof pgTAP/contract + replay PASS | NOT RUN | Storage upload/RPC failure compensation, same-key retry, concurrent upload, orphan object cleanup |
| Payment attempt supersession (PR #127) | Supersession pgTAP + replay PASS | NOT RUN | Approve/reject race, one-paid-per-order invariant, preserve proof-bearing sibling for manual review |
| Tenant invitation (PR #126) | 15 pgTAP assertions pass; full replay PASS | NOT RUN | Actual issue, delivery/manual copy, correct-email accept, wrong-email reject, replay reject, expiry/audit E2E |
| Permission mutation (PR #120) | Atomic RPC contract + migration replay PASS | NOT RUN | Positive/negative role tests; atomic before/after/audit row verification; direct mutation denial |

No browser/API runtime E2E, shared staging mutation, migration application, or production mutation occurred in this continuation.

## Current staging execution status — 21 November 2026

### Tenant isolation P01–P09

The current PR #126 workflow .github/workflows/staging-tenant-isolation-acceptance.yml is manual-dispatch-only and uses the two existing Supabase Auth identities via Auth Admin magic links. It defines nine required probes plus six supplemental direct-RLS/RPC probes. It must finish with P01–P09 = 9/9 PASS, zero FAIL/BLOCKED/SKIPPED, and all supplemental probes PASS. **No P01–P09 run has been dispatched in this continuation**; do not infer PASS from database fixture presence or local pgTAP.

Read-only Supabase evidence confirms two tenants, three active membership rows, four Auth users, two distinct QA branches (QA-DLICE-A, QA-TENANT-B) and distinct existing Auth identities assigned to their own tenant branches. The required service-role Environment secret and staging Environment protection could not be queried through the connected GitHub integration; no secret was read or exposed. The workflow-dispatch action is not available in the connected tools.

### Invitation tests and migration replay

PR #126 disposable run 44903918177 passed all seven pgTAP files, **134 total assertions**, including tenant_invite_atomic.test.sql with plan(15) (15 invitation assertions). This is disposable database evidence, not shared-staging mutation or real invitation delivery.

### Online checkout and payment lifecycle

PR #123 and PR #126 still have an unresolved migration version collision: both source branches use 20261121130000 with different SQL contents. Each branch's own exact-head disposable replay passes, but the combined candidate set cannot be replayed until one migration is re-versioned. PR #123's browser response-drop/concurrency runtime remains NOT RUN. PR #127 disposable tests pass; PR #125 is closed as superseded by #127; browser concurrency, payment webhook timing, Storage orphan recovery and end-to-end order/payment/reservation reconciliation remain NOT RUN.

### Operational staging baseline (read-only)

| Measure | Current staging |
|---|---:|
| Orders | 7 |
| Reservations | 21 (9 active expired, 9 consumed, 3 held expired) |
| Payment records | 6 (3 paid, 3 pending verification) |
| Recipes / ingredients | 1 / 2 |
| Kitchen tickets / items | 6 / 6 |
| Stock movements | 26 |
| Inventory items / branch inventory rows | 2 / 4 |
| Production batches / consumption | 0 / 0 |
| Stock transfers / counts | 0 / 0 |
| Procurement requisitions / POs / receipts | 0 / 0 / 0 |
| Finance journal entries / cash reconciliations | 0 / 0 |
| Scheduled online-order expiry worker | 0 |

The current staging data proves table/schema presence, not completion of the business workflows. Do not mark Kitchen, Inventory, Procurement, Finance or Order Management DONE from these counts.


## Current exact-head execution — 21 November 2026

| PR | Exact head | Automated CI / disposable replay | Focused DB test plan | Runtime E2E |
|---:|---|---|---:|---|
| #120 | 471f4a330a4da0cb13afe60ddeeb520e28dc0e88 | 6/6 PASS | 35 profile mutation + 11 permission + 11 invitation assertions | Staging mutation paths NOT RUN |
| #123 | 31976673a9289add4c1bb10d6f29f3ff6c3c15a5 | 6/6 PASS | 7 online idempotency assertions | Concurrent checkout / response-drop / late webhook NOT RUN |
| #125 | 1c97dd74ac3e17bf1cfdfa926cd6ab5f5a40156d | 3/3 PASS | 27 expiry/compensation assertions | Live expiry scheduler/worker NOT RUN |
| #126 | 07d7c51c2cbea21b9cd49a480614e004fe7bf417 | 6/6 PASS | 35 RLS + 17 onboarding + 15 invitation assertions | P01–P09 NOT RUN |
| #127 | 5c597c2ec37a130501ed19591cfc9383396ba1b6 | 6/6 PASS | 16 proof + 14 supersession assertions | Proof upload concurrency / Storage orphan sweep NOT RUN |

The pgTAP plans are per disposable test file; they are not shared-staging execution or browser/API runtime evidence. No staging migration or Edge Function deployment was performed. PR #124 is closed as superseded by #120.

### Current P01–P09 fixture facts

Two existing Supabase Auth identities were verified read-only and mapped to different active tenants. Tenant A has active branch assignments QA-DLICE-A and DLC-B001; Tenant B has QA-TENANT-B. Both last signed in on 2026-10-25. This verifies fixture existence and mapping only; no current login, JWT session, own-read/write or cross-tenant negative probe has run. The staging Environment protection and STAGING_SUPABASE_SERVICE_ROLE_KEY presence are NOT VERIFIED; the secret value was not read or exposed. The connected GitHub tool does not expose workflow_dispatch.

- Vercel exact-head Preview: PR #123 READY at https://dlice-landing-page-loho5y7oz-dlice8888-7332.vercel.app; PR #125 READY at https://dlice-landing-page-96j5eiu7k-dlice8888-7332.vercel.app. No exact-head deployment record exists for #120, #126 or #127. Preview READY does not establish runtime feature acceptance; production remains unchanged.


## Authoritative execution update — 21 November 2026

### Existing Supabase Tenant A/B fixtures

Read-only staging queries confirm two distinct existing Auth identities, two distinct active tenant memberships, active profiles and branch assignments. Both have tenant role branch_manager and global profile role sales_admin. Tenant A's active QA branch is QA-DLICE-A (it also has an assignment to DLC-B001, whose branch status is planned); Tenant B's active QA branch is QA-TENANT-B. No account, password, Auth metadata, membership or assignment was changed.

### PR #126 passwordless test path and exact-head tests

PR #126 now uses Supabase Auth Admin generate_link for the existing email identities and verifies the one-time magic-link hash. It does not require the four old username/password secrets or create/reset any user. The workflow validates the service-role key's presence/shape without printing it, verifies the returned Auth identity matches the requested account, revokes temporary sessions after probes, and derives tenant/branch UUIDs from authenticated membership responses.

A test-evidence defect was found and corrected: blocked preflight records previously inherited executed=true. recordProbe now accepts the explicit execution flag; preflight BLOCKED records are executed=false, and the contract test asserts this. The fix is in PR #126 exact head bb008c55a4d98afe5264b4ccde4f28f129bc162; exact-head quality checks PASS. Disposable replay 44909241076 PASS: 7 pgTAP files / 134 assertions, including 35 tenant RLS, 17 onboarding and 15 invitation assertions. KDS, CORS and procurement contract workflows also PASS.

P01–P09 remain NOT RUN. The workflow is manual-dispatch-only on trusted staging; the connected GitHub integration does not expose workflow dispatch or staging Environment settings. Presence of STAGING_SUPABASE_SERVICE_ROLE_KEY is NOT VERIFIED; its value was not read or exposed. No probe is to be marked PASS based on fixture existence or disposable pgTAP.

### Order/payment lifecycle tests

- PR #123 exact head 6788c4d7da34144d279da06edea84f6d0763b796: quality, disposable replay, KDS, CORS and procurement contracts PASS; checkout response-drop, retry, concurrency and late-webhook E2E NOT RUN.
- PR #127 exact head 5c597c2ec37a130501ed19591cfc9383396ba1b6: quality, disposable replay, KDS, CORS and procurement contracts PASS; proof upload retry/concurrency, expiry worker, compensation and payment-attempt supersession E2E NOT RUN. PR #125 is CLOSED as superseded by #127.
- PR #124 is CLOSED as superseded by #120. No shared staging migration or Edge Function deployment was performed.
