# Order fulfillment, production and finance — staging rollout

## Environment guardrail
- Target branch: `feat/staging-order-fulfillment-finance-production`
- Staging Supabase: `higoadrzxnhzbbwhdbmh`
- Production Supabase `gdjlkrmlsurcdbwnmqgg` and production domain remain untouched.
- Staging migration applied and verified: `20261020194817_order_fulfillment_production_finance_controls`.
- All new tables have RLS enabled and direct `anon`/`authenticated` grants revoked.

## Schema added
- Online order routing: nullable branch association, selection source, fulfillment lifecycle, branch coordinates/service radius and online/pickup/delivery/capacity settings; branch/product/date capacity ledger.
- Purchasing: separate receipt and receipt-item records, designed to retain partial receiving and audit history.
- Production: approved/versioned recipes, BOM ingredients, production batches, measured ingredient consumption and actual yield/waste records.
- Finance: settlement batches and matching items, refund requests/approvals/processing, cash/bank/QRIS reconciliation, effective-dated tax settings, fiscal periods and immutable journal-event records.

## Critical limitations — do not treat schema as completed workflows
This PR establishes data structures only. The following server-side transitions must be implemented and tested before operational use:
1. Checkout must estimate a branch from server-side IP geolocation only as a low-confidence suggestion, filter to active serviceable branches, lock branch/date/product capacity in one transaction, and reserve capacity atomically. Customer must be able to correct the branch. Do not persist raw IP or infer a delivery address from IP.
2. Route an order to the selected branch and display only orders assigned to that branch to staff. Do not expose branch selection to the customer as proof of service coverage until real branch coordinates, radius and hours have been configured.
3. Receiving endpoint must lock PO and line rows, reject over-receipt, write receipt rows, invoke stock movement and update PO state in the same transaction; idempotency key required.
4. Production completion must lock batch and inventory balances, calculate expected BOM quantities, capture actual consumption and yield/waste, write stock movements atomically and prevent duplicate completion.
5. Refunds require reviewer separation, amount cap against remaining refundable balance, external payment reversal reference and immutable audit trail. Do not mark a refund processed merely because it was requested.
6. Settlement matching must prevent a payment or POS sale being matched twice and reconcile gross, fees, net and received amount.
7. Tax configuration must be approved by Finance/Owner and effective-dated according to the business's tax advice; this schema does not decide the legally applicable rate.
8. Period close must reject new journal postings into closed periods; reopening requires Owner authorization and an audit event.

## Acceptance gates before production
- Checkout: IP estimate fallback, customer branch override, unsupported/out-of-radius address, pickup/delivery eligibility, capacity full, capacity race (two requests for last slot), expired reservation and idempotent retry.
- Branch security: Owner, Head Ops, Area Manager, Branch Manager, Cashier, Kitchen, Inventory, Procurement, Finance, Customer Service and Auditor; verify denied cross-branch reads/writes on every endpoint, not just hidden UI.
- Purchasing: draft → submitted → approved → ordered → partial receipt → full receipt; reject receipt on wrong branch, over-receipt, duplicate retry and inactive SKU; verify balance equals ledger sum.
- Production: recipe approval/versioning, missing ingredient, insufficient stock, actual consumption differs from BOM, waste/yield variance, concurrent completion and duplicate completion.
- Finance: duplicate settlement matching, fee variance, partial refund, refund > remaining balance, self-approval, duplicate journal source, tax effective-date boundary, cash variance, closed-period posting and authorized reopening.
- Concurrency/load: two cashiers on same branch, duplicate POS submit, stock movement racing with production consumption, concurrent receiving and order capacity race.
- Confirm transaction totals are server-calculated, all financial amounts are integer IDR, and no secrets/service-role key enter client code.
- Run browser acceptance tests on Android, iOS, tablet and desktop; confirm latest Vercel Preview SHA matches this PR and run Security Advisor.
- Keep production unchanged until all gates pass and Owner explicitly approves.

## Automatic branch selection
DNS is not a reliable customer-location signal. Use IP geolocation from trusted server request metadata only as a coarse, low-confidence suggestion; never ask for device geolocation permission, never persist the raw IP, and always permit branch correction. VPNs, carrier NAT and privacy relays can mislocate users. If no eligible branch can be confidently chosen, show available branches or ask the customer to choose rather than silently assigning an unserviceable outlet.
