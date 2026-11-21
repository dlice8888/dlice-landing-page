# P0/P1 blocked feature remediation plan — 21 November 2026

This plan is tied to the 189-row feature register in `FNB_OS_IMPLEMENTATION_MATRIX.json`. A BLOCKED feature remains blocked for acceptance until the external/runtime gate is removed; `work_status` is tracked separately so implementation activity is not confused with release acceptance.

## 9 blocked features and required completion work

### 1. Executive Command Center — Company → region → branch → shift → transaction drill-down
**Current gap:** A basic dashboard/summary foundation is not proof that the complete hierarchy can be navigated safely or that each level reconciles to the same underlying transactions.

**Implementation and acceptance work**
1. Define canonical company, region, branch, business-date, shift and transaction dimensions; enforce branch-to-region and branch-to-tenant mapping integrity.
2. Implement paginated drill-down endpoints and UI navigation with stable filters and preserved date/timezone context.
3. Enforce role-aware visibility at every level: Owner/HQ may aggregate authorized tenants; branch roles must not enumerate other branches or tenants.
4. Reconcile totals at every level against source POS sales, orders, refunds, discounts, payment records and finance postings. Define gross/net/margin formulas once.
5. Add loading, empty, partial-data, stale-data and error states; expose source timestamp and drill-down provenance.
6. Test company→region→branch→shift→transaction paths, filter preservation, pagination, role denial, cross-tenant denial and totals matching database fixtures.

**DONE evidence:** browser recording/screenshots for each role, API assertions, SQL reconciliation query and passing workflow with zero skipped probes.

### 2. POS & Checkout — receipt printing / digital receipt
**Current gap:** Receipt gates/schema are not proof that the cashier can print or deliver a correct receipt on supported devices.

**Implementation and acceptance work**
1. Define an immutable receipt snapshot: transaction number, items/modifiers, tax, discount, tender breakdown, payment state, branch identity, business date and refund references.
2. Make receipt creation idempotent and prevent a receipt from showing a payment as successful before authoritative payment confirmation.
3. Implement browser print layout and digital receipt retrieval/share flow; document supported thermal printer/browser combinations.
4. Handle reprint, duplicate click, network retry, void/refund and partial payment without changing the original receipt facts.
5. Add accessible responsive receipt UI, print CSS, failure/retry states and audit event for reprint where required.
6. Run real browser/device tests for supported printer profiles and verify receipt totals against POS/payment database rows.

**DONE evidence:** browser/device evidence, duplicate/retry tests, payment-state tests and receipt-to-ledger reconciliation.

### 3. Order Management — duplicate orders, delayed payment, failed order handling
**Current gap:** Idempotency foundations exist, but timeout, replay, delayed confirmation and compensation behavior are not accepted end-to-end.

**Implementation and acceptance work**
1. Establish a stable idempotency key per client intent and unique database constraint scoped to tenant/channel; persist request hash and canonical result.
2. Separate order, payment, reservation and fulfillment state machines; define allowed transitions and terminal states.
3. Make payment webhook ingestion idempotent and verify provider signatures, event identity, amount, currency and order reference.
4. Handle duplicate submit, client retry, webhook retry, delayed success, out-of-order events, timeout and provider failure.
5. Define compensation: release stock reservation, cancel/expire unpaid order, reverse/void payment where supported, and record manual-review exceptions.
6. Use transactional outbox/retry with bounded backoff, dead-letter visibility and audit trail.
7. Test concurrent duplicate submissions, delayed/duplicate webhooks, failure after reservation, replay after restart and cross-channel status consistency.

**DONE evidence:** race/concurrency tests, provider-sandbox or deterministic signed webhook tests, database uniqueness/ledger checks and end-to-end workflow.

### 4. Kitchen & Production — theoretical vs actual usage / waste variance
**Current gap:** Recipe, production consumption and waste records exist, but expected usage, actual usage and variance are not proven as one reconciled operational report.

**Implementation and acceptance work**
1. Freeze the recipe/BOM version and yield used for each production batch/order.
2. Calculate theoretical ingredient usage from quantity × approved recipe yield, including unit conversion and approved substitutions.
3. Record actual stock consumption and waste as distinct ledger movements with source batch/order and actor.
4. Calculate variance by ingredient, batch, product, branch and business date; define tolerance and escalation thresholds.
5. Prevent double counting waste as both production consumption and a separate stock adjustment.
6. Add review/approval for material variance and immutable adjustment/audit references.
7. Test normal yield, over-consumption, under-consumption, waste, substitution, reversal and duplicate replay; reconcile to stock ledger.

**DONE evidence:** batch-level expected-vs-actual report with SQL proof that opening stock + receipts − consumption − waste ± adjustments = closing stock.

### 5. Menu & Recipe — POS and production use the same approved recipe version
**Current gap:** Atomic recipe-version activation exists, but there is no accepted cross-module proof that POS and production resolve the same approved/effective version, including historical orders.

**Implementation and acceptance work**
1. Define immutable recipe versions with approval state and effective-from/effective-to timestamps.
2. Resolve and persist the approved recipe version at order acceptance; do not dynamically switch a committed order when a new version is activated.
3. Ensure KDS/production batch and stock consumption consume the exact version pinned to the order.
4. Validate branch-specific availability and substitutions against that pinned version.
5. Add concurrency and effective-date tests: order before activation, during cutover and after activation.
6. Reconcile ingredient consumption, cost and version IDs across POS, order, production and inventory records.

**DONE evidence:** cross-module workflow proving the same recipe version ID end-to-end, plus immutable history and race tests.

### 6. Branch Operations — opening readiness changes branch operating status
**Current gap:** Checklist foundations exist, but checklist completion has not been proven to drive an authorized branch operating-state transition.

**Implementation and acceptance work**
1. Define opening readiness criteria, mandatory checklist items, evidence requirements, expiry/recurrence and waiver policy.
2. Define a branch operating state machine (e.g. setup, not-ready, ready-to-open, operating, suspended/closed) and permitted transitions.
3. Require authorized approval for readiness exceptions; do not allow an ordinary checklist edit to open a branch.
4. Make checklist completion and branch status change atomic or explicitly transactional with audit metadata.
5. Update order routing, POS availability and Command Center state from the authoritative branch status.
6. Test incomplete checklist, expired evidence, unauthorized approval, waiver, reopen, concurrent updates and audit rollback.

**DONE evidence:** checklist→approval→branch status→POS/order-routing workflow and database audit trail.

### 7. Finance & Accounting — provider fee and settlement variance
**Current gap:** Settlement matching foundations exist, but provider fees, net settlement and variance are not proven against actual payment-provider statements and finance postings.

**Implementation and acceptance work**
1. Model fee schedules by provider, payment method, merchant/branch, effective date and fixed/percentage components.
2. Calculate expected gross, fee, tax-on-fee (where applicable), net settlement and settlement date.
3. Import or ingest provider settlement lines with idempotent external IDs and source evidence.
4. Match payment records to settlement lines; detect missing, duplicate, partial, late, reversed and fee-mismatch cases.
5. Create exception queue with reason, owner, resolution and audit trail; never silently force-match a variance.
6. Post balanced journal entries only after approved matching; support reversals and period close rules.
7. Test fee calculations, rounding, split settlements, refunds/chargebacks, duplicate statement rows and reconciliation to bank/provider totals.

**DONE evidence:** provider sandbox/statement fixtures, payment-to-settlement reconciliation report and balanced journal query.

### 8. Admin & Access Control — permission changes themselves audited
**Current gap:** The old handler updated permissions and wrote the audit record separately, ignoring audit-insert failure. The new atomic path is implemented on a review branch but not deployed to shared staging.

**Implementation already completed**
- Draft PR #120: https://github.com/dlice8888/dlice-landing-page/pull/120
- Edge Function now calls a service-role-only RPC.
- Database RPC locks the target profile and writes before/after permission sets in the same transaction.
- Owner profile cannot be changed through this action.
- Audit persistence failure rolls back the permission update and the API fails closed.
- Atomic RPCs and source-contract/pgTAP tests are present. The latest branch changes fixed a malformed invite email regex and corrected the release-contract exception for email-bound one-time invite acceptance.
- Previous PR #120 head failed: ERP authorization coverage contract and disposable replay SQL parse. New exact-head quality was queued and disposable migration replay was running at the latest audit; do not call PR #120 green until both finish PASS.

**Remaining work**
1. Independent review of RPC ACL, function authorization, target locking and audit schema.
2. Resolve GitHub release protection and required independent reviewer.
3. After explicit staging authorization, apply the migration and deploy the matching Edge Function to staging only.
4. Run positive permission change, invalid permission, non-service RPC denial, Owner protection, audit-write failure rollback and before/after audit retrieval using staging identities.
5. Confirm audit actor identity is the authenticated administrator and no permission change can bypass this RPC.

**DONE evidence:** independent approval, exact-head CI, authorized staging migration/deployment, runtime positive/negative tests and audit-row verification. No production change is included.

### 9. Quality, Compliance & Security — leaked-password protection
**Current gap:** Supabase Security Advisor currently reports `auth_leaked_password_protection` as WARN / disabled.

**Required external action**
1. An authorized Supabase project owner checks that the staging project plan supports the control (Supabase documentation states Pro and above).
2. In the staging project only, open Authentication → Settings → Password security and enable leaked-password protection.
3. Re-open the setting and retain evidence that it remains enabled.
4. With disposable test identities, verify a known compromised password is rejected on signup/password update and a compliant password is accepted.
5. Verify no existing staff account/password was changed; re-run Security Advisor and retain the result.
6. Do not upgrade a paid plan or change production Auth without explicit approval.

**DONE evidence:** setting enabled on staging, disposable positive/negative tests and Security Advisor warning cleared.

## Cross-cutting prerequisites blocking multiple domains

1. **GitHub release protection:** the latest available audit found a repository ruleset with zero required approvals, empty required checks and deployment reviewers, and always-bypass actors. Branch-specific protection reads returned 403. This is not an adequate release gate.
2. **Independent review:** the current open PR metadata shows no reviewers requested on the 16 open PRs. PR authors must not approve their own changes.
3. **Owner authorization:** live read-only query found zero Auth users with boolean `app_metadata.platform_owner=true`; do not mutate Owner metadata without authorized Auth Admin action and verified existing identity.
4. **Tenant runtime acceptance:** P01–P09 and supplemental probes have not been executed against real protected staging identities; blocked/skipped probes are not passes.
5. **Business-data workflow evidence:** staging currently has zero purchase orders, receipts, production batches, settlements, refunds and finance journal entries. Use isolated, explicitly authorized test fixtures; never fabricate production transactions.
6. **Vercel protection:** project is on Hobby; SSO protection is configured for all deployment types except custom domains. Verify actual staging URL protection before using preview as a protected QA surface.
7. **Staging E2E credentials:** the latest Procurement and KDS/POS/Stock/Offline runs are BLOCKED at preflight because `STAGING_TEST_OWNER_USERNAME`, `STAGING_TEST_OWNER_PASSWORD` and `STAGING_TEST_BRANCH_A_USERNAME` are unavailable. An authorized repository/environment maintainer must verify and restore the correct QA secrets without disclosing their values. Do not substitute identities or weaken the preflight.

## Exit rule

A feature is DONE only when its weighted acceptance score is 100%, all required code/database/workflow/runtime checks pass, there are zero BLOCKED/SKIPPED acceptance probes, reconciliation evidence is attached, and required independent review/release gates are satisfied.
