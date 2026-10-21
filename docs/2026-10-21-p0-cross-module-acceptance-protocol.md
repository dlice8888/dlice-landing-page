# P0 and Cross-Module Acceptance Protocol — Staging Only
Date: 2026-10-21
Environment: Supabase staging project `higoadrzxnhzbbwhdbmh`, Vercel Preview only.
Related audit: `docs/2026-10-21-fnb-os-staging-capability-audit.md`.
Do not run against production. Use synthetic fixtures only; do not create real customer orders.

## Live baseline verified
- 39 public tables and 15 public functions are present in staging.
- Key ERP tables inspected (orders, order_items, payment_records, POS, inventory, recipe/production, purchasing, journals, admin_profiles, branch_assignments) all have RLS enabled and one policy. For internal ERP tables, that policy is the restrictive `deny_direct_client_access`; `FORCE ROW LEVEL SECURITY` is false. This is acceptable only if the client has no direct table grants and all access routes through the audited Edge Function/service-role layer.
- Planned branch slots are not active test branches: first 10 inspected are `planned`, `accepts_online_orders=false`. Do not treat the 150 planned slots as live operational branches.
- Current CORS OPTIONS/POST and authenticated role-negative cases have not been executed in this audit session because there are no disposable test identities/tokens supplied in the connected context. Do not mark these tests passed from schema inspection.
- No production changes performed.

## Test identity matrix (create only in staging)
Prepare unique disposable identities:
1. Owner
2. Branch A manager with active assignment to A
3. Branch B manager with active assignment to B
4. Cashier A with POS permission only
5. Staff A with explicit empty/insufficient permission array
6. Inactive staff profile
7. Unauthenticated caller
Use separate identities for requester and approver to test separation of duties. Record IDs, branch IDs, timestamp, HTTP status, response body with secrets redacted, and before/after row counts.

## P0 negative-access gate
| Test | Action | Expected | Evidence |
|---|---|---|---|
| P0-AUTH-01 | Call each admin/ERP action without bearer token | 401; no write | Request/response + row-count diff |
| P0-AUTH-02 | Expired/invalid token | 401; no write | Request/response + row-count diff |
| P0-AUTH-03 | Inactive profile | 401; no write | Request/response + row-count diff |
| P0-AUTH-04 | Valid staff, missing action permission | 403; no write | Request/response + row-count diff |
| P0-AUTH-05 | Branch A identity requests Branch B order/proof/refund/shift/inventory/capacity | 403 or empty scoped result; no write | Request/response + row-count diff |
| P0-AUTH-06 | Permission but no active branch assignment | no branch data; writes denied | Request/response + row-count diff |
| P0-AUTH-07 | Branch staff attempts global catalog/recipe/inventory master write | 403 | Request/response + row-count diff |
| P0-AUTH-08 | Refund requester attempts to approve/process own refund | 403 | Request/response + refund state |
| P0-RLS-01 | Use anon/authenticated Data API key to SELECT/INSERT/UPDATE/DELETE internal ERP tables | denied/no rows changed | HTTP responses + row-count diff |
| P0-AUTH-09 | Owner uses authorized global action | allowed only after validation | request/response + audit row |

**Important:** SQL executed through the privileged database connector is not evidence that anonymous/authenticated API access is denied. P0-RLS-01 must use the public Data API with an anon key and, separately, a normal authenticated user's access token. Never use service-role keys in client tests.

## CORS acceptance gate
Run from a client or runner outside the Supabase connector. Use the actual current Preview origin from the Vercel deployment metadata and the configured stable branch alias. Do not hardcode an old per-deployment URL as permanent configuration.

For each origin:
- Allowed origin OPTIONS request must return 2xx and exact `Access-Control-Allow-Origin` equal to the request origin.
- Allowed origin POST without bearer token must return 401, not a CORS denial, and must not mutate data.
- Deliberately unlisted HTTPS origin OPTIONS and POST must return 403.
- Unlisted origin must never receive its own value in `Access-Control-Allow-Origin`.
- `Access-Control-Allow-Origin: *` is forbidden.
Record response status and CORS headers. Do not mark complete based on source inspection alone.

## Timezone/cutoff acceptance gate
The database checkout RPC derives local date/time from each active branch timezone. Use active staging fixtures only and inject or safely control a deterministic clock in the test harness; do not wait for actual local 17:59/18:00 unless a controlled clock is unavailable.
- Asia/Jakarta, Asia/Makassar, Asia/Jayapura: same-day checkout before 18:00 local is allowed only if branch/product capacity and all other checks pass.
- At exactly 18:00 local and after, same-day checkout returns `same_day_cutoff_passed`.
- Previous branch-local date returns `date_in_past`.
- Order stores the expected branch timezone and transaction code date matches that timezone.
- Failed checkout leaves no order, order_items, or reservations behind.
- Concurrent checkouts cannot exceed branch/product capacity.
- Test pickup/delivery restrictions and delivery address validation.
If the clock cannot be controlled safely, mark the exact boundary test BLOCKED rather than using a guessed result.

## Workflow 1 — Order-to-Cash
1. Create synthetic order with known branch, items, expected prices and idempotency/correlation key.
2. Verify order creation alone leaves payment as unpaid/pending; never infer payment from order existence.
3. Apply a valid staging payment confirmation via the supported action; reject forged/invalid payment proof.
4. Verify branch assignment and fulfillment state transitions, with an audit/status-history entry for each transition.
5. Process the order into kitchen/fulfillment.
6. Apply stock consumption only at the configured consumption point and exactly once; retry the same event and confirm no duplicate movement.
7. Verify revenue/payment/settlement/journal entries use the correct branch, business date and amount.
8. Compare order total, verified payment, refund balance, stock movements and journal totals. Cleanup synthetic fixtures using reviewed cleanup tooling.
Pass only when all totals reconcile and duplicate processing has no additional effect.

## Workflow 2 — Procure-to-Pay
1. Create a synthetic supplier and PR/PO for a known quantity and unit cost.
2. Submit and approve with separate identities; requester cannot approve their own request.
3. Receive part of the PO, verify GRN quantity and stock movement once.
4. Retry the same receipt request/correlation key; inventory must not increment again.
5. Receive remaining quantity and verify ordered, received and outstanding amounts.
6. Match supplier invoice to PO + accepted receipt; block quantity/price variance outside configured tolerance.
7. Verify AP and journal entries after approval/payment; reconcile stock ledger, receipt lines and finance entries.
Pass only when PO, GRN, stock and finance totals reconcile.

## Workflow 3 — Forecast-to-Production
1. Create synthetic forecast/demand for a branch and service date.
2. Select the effective recipe/BOM version and calculate ingredient requirement using explicit units/yield.
3. Compare requirement with available, reserved, expired/blocked and on-hand stock.
4. Block or create a replenishment/transfer task for shortages; do not silently permit negative stock.
5. Create a batch, record actual good output, ingredient consumption and waste.
6. Retry completion; it must not duplicate output or ingredient consumption.
7. Verify finished quantity, waste, inventory ledger, batch record and food-cost calculation.
Pass only when theoretical versus actual variance is visible and traceable.

## Workflow 4 — Record-to-Report
1. Create synthetic POS sale, payment, purchase receipt, operating expense and (if supported) refund records.
2. Verify every journal source is linked to the originating business record and branch.
3. Validate debits equal credits for each journal entry; reject zero/negative/invalid entries and closed-period postings.
4. Reconcile cash drawer, verified payments, settlement, receipts, stock and expense totals.
5. Close a disposable test fiscal period; confirm subsequent posting is blocked or requires an audited adjustment period.
6. Produce branch-level totals and compare to source ledgers; do not claim group consolidation until tenant/company dimensions are proven.
Pass only when source-to-ledger totals reconcile and closed periods cannot be silently changed.

## Evidence template
For each test record:
- Test ID and build commit
- Staging project ID and Preview URL
- Fixture identifiers (synthetic only)
- Actor identity/role/branch scope
- Request/action and sanitized payload
- Expected result and actual HTTP/RPC result
- Before/after counts and financial/stock totals
- Audit event/status-history reference
- Pass / Fail / Blocked, tester, timestamp
- Cleanup confirmation

## Release gate
Do not merge PRs or change production until:
- all P0 negative-access tests pass;
- CORS allowlist tests pass against current Preview and an unlisted origin;
- timezone and capacity tests pass;
- all four cross-module workflows reconcile;
- desktop/mobile authenticated browser acceptance is recorded;
- CI is green on the final head;
- rollback and backup/restore evidence is attached;
- Owner explicitly approves the merge/deployment.
