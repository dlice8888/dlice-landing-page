# Staging schema reconnaissance for eight priority domains

**Read-only source:** Supabase staging project `higoadrzxnhzbbwhdbmh`, public schema, inspected 2026-11-25. No data rows were read or changed for this inventory. No migration was applied.

## Existing domain entities found

| Domain | Existing staging entities | Implication |
|---|---|---|
| CRM, Loyalty & Marketing | `orders` includes customer_name/customer_whatsapp; `pos_sales` includes customer_reference. No dedicated CRM/loyalty entity was found in the public table inventory. | A real CRM requires a tenant-scoped customer identity and consent model, with explicit linkage to order/POS records. Do not treat customer_reference as a customer master or create loyalty balance fields on transactions. |
| HR & Workforce | `admin_profiles`, `job_positions`, `branch_assignments`, `pos_shifts`, `shift_handover_records` | Staff identity, role and branch assignment foundations exist. No dedicated attendance-event, roster/schedule, leave, timesheet or payroll tables were found. |
| Delivery & Fulfillment | `orders`, `order_status_history`, `payment_records`, `notification_log` | Order and payment state already exist separately, including fulfillment_status. Dedicated courier quote, provider callback/event, dispatch/POD and delivery-cost ledger entities were not found. Extend order fulfillment without conflating payment_status and operational_status. |
| Franchise & Expansion | `tenants`, `branches`, `tenant_memberships`, `tenant_invites`, `branch_settings` | Tenant and branch provisioning foundations exist. Franchise applications, due diligence, territory rights, versioned agreements and royalty ledgers were not found. |
| BI & Analytics | `funnel_daily_metrics`, `admin_audit_logs`, operational transaction/stock/finance entities | Some source data and funnel aggregation exist. A versioned KPI catalogue, source watermarks, snapshot completeness/reconciliation and governed cohort definitions were not found. |
| SaaS Tenant Management | `tenants`, `tenant_memberships`, `tenant_invites`, `integration_connections`, `integration_outbox`, `backup_restore_runs` | Core tenant membership/integration foundations exist. Dedicated subscription plans, entitlement catalogue, usage metering, invoice/payment lifecycle and offboarding evidence were not found. |
| Procurement & Supplier | `suppliers`, `purchase_requisitions`, `purchase_requisition_items`, `purchase_orders`, `purchase_order_items`, `purchase_receipts`, `purchase_receipt_items` | A requisition → PO → receipt path exists. Verify approval transitions, supplier tenant ownership, immutable receipt/stock linkage, invoice matching and AP posting before extending. |
| Executive Command Center | `branches`, `tenants`, `pos_sales`, `orders`, inventory, procurement, finance and operational checklist entities | Operational sources exist for some KPIs. A governed metric catalogue and verified 150-branch company→region→branch→shift→transaction drilldown still require source/role/reconciliation proof. |

## Security and ownership observations

- `branches` has `tenant_id`; `tenant_memberships` binds `tenant_id` to `user_id`, role, permissions and active status.
- `admin_profiles` is a global profile table. It must not be treated as sufficient tenant authorization.
- `branch_assignments` stores `branch_id` and `user_id` but has no direct `tenant_id`; authorization must join through the branch and active tenant membership. `pos_shifts`, `pos_sales`, `purchase_requisitions`, `purchase_orders`, and `purchase_receipts` also rely on branch references rather than storing tenant_id directly.
- `suppliers` has no `tenant_id` column in staging. The current supplier master therefore cannot be assumed tenant-isolated; a supplier-to-tenant ownership model or approved shared-supplier model is needed before exposing Procurement supplier writes to tenant users.
- `orders` has nullable `branch_id` and no `tenant_id`; historical/unassigned orders cannot be safely assigned to a CRM tenant by guessing from customer phone or name.
- Existing tenant-aware tables include composite tenant/branch foreign keys, for example branch settings, warehouses, inventory waste and integration outbox. New branch-scoped entities should follow this referential-integrity pattern.
- The inspected public tables had RLS enabled. Read-only policy inspection showed `admin_profiles`, `orders`, and `admin_audit_logs` use service-role-only access; `branches`, `tenant_memberships`, `suppliers`, `purchase_orders`, `purchase_receipts`, and `pos_sales` deny direct `anon`/`authenticated` access. This is a deliberate server-mediated pattern, not evidence that every Edge action is correctly authorized. Policy-by-policy and cross-tenant negative tests remain required.
- Edge Function `dlice-orders` has server-side service-role access. New commands must authenticate with the caller JWT, derive tenant and branch scope from active membership, authorize the specific command, and append audit evidence. Never trust client-supplied tenant_id as authority.
- Existing global owner authorization remains dual-gated by the server UUID allowlist and boolean `app_metadata.platform_owner === true`. Do not change that path here.

## Implementation sequence based on actual schema

1. CRM: add the missing tenant-owned customer, consent-event, reward/voucher and append-only loyalty ledger model; link customer IDs to order and POS through explicit nullable foreign keys only after duplicate/identity migration rules are defined.
2. HR: extend existing employee/profile and branch-assignment model with schedules, attendance events, leave and approved timesheets; payroll must reconcile to finance journals.
3. Delivery: extend the existing fulfillment lifecycle with quote snapshots, provider event idempotency, proof of delivery and fee/subsidy/cost accounting.
4. Franchise: build application, due diligence, territory and effective-dated agreement records; royalty postings must reconcile to tenant sales/finance.
5. BI: define versioned metrics and source lineage; publish snapshots only after freshness, completeness and reconciliation checks.
6. SaaS: define plan versions, entitlements, metering and billing lifecycle over existing tenant records; enforce entitlement server-side and preserve isolation flags.
7. Procurement: reuse the existing requisition/PO/receipt entities; close the supplier ownership, approval separation, receipt-to-stock and invoice three-way-match gaps.
8. Executive: use only reconciled source metrics and enforce role-safe drilldown at every level.

## CRM source implementation added after reconnaissance

- Added `erp.html` CRM workspace and server action source for Platform Owner customer list/create, consent event append, loyalty ledger read/post, and reward draft create/list.
- Added a non-executable schema design draft at `docs/implementation/sql/CRM_LOYALTY_SCHEMA_DRAFT.sql`, including tenant-composite customer/branch references, append-only consent and loyalty records, service-role-only RLS, transactional loyalty posting and reward redemption RPCs, and same-transaction audit triggers.
- CRM Edge actions intentionally return a fail-closed response for non-Platform-Owner callers while `TENANT_ISOLATION_RELEASED=false`. This is a temporary implementation boundary, not final role coverage.
- The CRM workspace will not function against staging until the draft is reconciled, generated as a proper Supabase migration, reviewed, replayed and applied during the final batch.

## CRM transaction identity linking increment (2026-11-25)

- Added the `erp-crm-link-paid-transaction` Edge action, still Platform-Owner-only while tenant isolation is unreleased.
- The action accepts only `online_order` or `pos_sale` source IDs, reloads the source record server-side, requires `payment_status='paid'`, derives its branch from the source row, and verifies that branch belongs to the selected tenant. A nullable/unassigned online-order branch is rejected rather than guessed.
- Online-order customer identity is matched from the order WhatsApp number. POS `customer_reference` is treated as a phone only when the entire value is phone-shaped; arbitrary labels are never converted to digits. Otherwise an explicit CRM customer selection is required.
- The action creates or reuses a tenant-scoped CRM customer, inserts the unique `crm_transaction_links` record, returns an idempotent success for the same link, and rejects relinking a source transaction to a different customer. It does not grant loyalty points.
- Added a CRM workspace form to link a paid online order or POS sale to a customer. The UI does not decide whether a sale is eligible for points.
- Automatic loyalty earning remains intentionally blocked until the actual Finance/POS reconciliation source and authoritative net-sales fields are mapped. Payment status alone is not proof of reconciled net sales. No fabricated points or revenue basis is used.

## HR source implementation added after CRM reconnaissance

- Added an HR workspace to `erp.html` for active branch staff and attendance event capture.
- Added Edge Function commands for branch-scoped staff lookup and attendance read/write. Attendance writes call the proposed `hr_record_attendance` database RPC; that RPC serializes each employee/branch stream, checks active membership and assignment, enforces clock-in/break/clock-out order, and relies on an audit trigger.
- Added `docs/implementation/sql/HR_WORKFORCE_SCHEMA_DRAFT.sql` for schedules, attendance, leave, timesheets and payroll, with service-role-only RLS and audit triggers.
- The HR workspace will not function against staging until the draft is reconciled, generated as a proper Supabase migration, replayed and applied during the final batch. Leave, schedule, timesheet and payroll commands are not yet wired end-to-end.

## Release decision

This is reconnaissance only. No DDL, DML, RPC, Auth Admin, Edge Function deployment, Vercel deployment, or Production operation was performed. SQL migration authoring and all merge/migration/runtime validation remain deferred to the agreed final batch. The schema inventory is not a completion claim.


## Follow-up read-only finance/source reconciliation inspection (2026-11-25)

A second read-only inspection of staging project `higoadrzxnhzbbwhdbmh` queried `information_schema.columns` and PostgreSQL constraints for POS, orders, refunds, settlements, cash reconciliation and journal entries. No business rows were read or changed.

### Confirmed source fields and lifecycle constraints

- `pos_sales`: `id`, `branch_id`, `shift_id`, `subtotal_idr`, `discount_idr`, `total_idr`, `payment_method`, `payment_status`, `created_at`; payment status is constrained to `paid|pending|refunded|voided`. A POS sale is branch- and shift-linked, but the inspected schema does not itself expose a customer UUID or a dedicated reconciled-net-sales field.
- `pos_sale_items`: item snapshots, quantity, unit price and line total are available, but item-level refund allocation was not established by this inspection.
- `orders`: separate `payment_status` and `operational_status`, nullable `branch_id`, `product_subtotal_idr`; payment status includes `refunded`. Orders can be unassigned, so CRM attribution must continue to reject missing branch/tenant attribution.
- `refund_records`: supports POS sale, order or payment-record references; amount and status are present. Status is constrained to `requested|approved|rejected|processed|failed`. A production earning calculation must subtract only authoritative processed refunds and must guard against duplicate/multiple source references and refund totals exceeding captured value.
- `payment_settlements`: contains gross, fee, nullable net and received amounts, plus status `pending|matched|disputed|reversed`; settlement items can point to either a payment record or POS sale. `matched` is not the same as a formally reconciled/approved sales close.
- `cash_reconciliations`: is keyed by branch, business date and shift; status is `draft|submitted|approved|exception`, with reviewer metadata. It can support a POS shift close gate, but the schema inspection alone does not prove the row's amount composition or that each sale is included exactly once.
- `finance_journal_entries`: exposes `source_type`, nullable `source_id`, `branch_id`, `entry_date`, debit/credit account labels, positive `amount_idr`, and status `draft|posted|reversed`. This is a single-sided journal-entry shape in the inspected table; no balanced journal-batch or source-reconciliation relation was established. Do not infer that a `posted` row alone proves net sales are reconciled.

### CRM automatic earning decision

Automatic earning remains **BLOCKED pending source-of-truth mapping**, not because the operational tables are absent. Before implementing the award RPC, map and verify the authoritative POS/online sale financial close: source amount, discount treatment, refund allocation, settlement inclusion, cash/shift reconciliation status, journal posting/reversal lineage, and idempotent source identity. The candidate sources above are not sufficient to calculate a trustworthy eligible net-sales basis by themselves. In particular, never award points merely from `payment_status='paid'`, `pos_sales.total_idr`, or a `payment_settlements.status='matched'` row.

### Campaign delivery decision

The current CRM draft can approve campaigns and prepare a consent-filtered recipient queue. No approved email/SMS/WhatsApp delivery provider, credentials, callback signing contract, webhook secret, delivery receipt semantics or retry/idempotency contract was established in this read-only schema pass. Keep recipients queued; do not mark them sent or build a fake provider success path. The provider adapter and signed callback ingress must be added only after a real provider and its contract are selected and verified.

### Security and release boundary

This inspection was read-only. No migrations, SQL writes, Auth Admin changes, Edge deployments, staging data mutations, production operations, tests, merges or release-flag changes were performed. `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false` remain mandatory.


## Payroll-to-Finance schema mapping (read-only, 2026-11-25)

The next payroll slice was grounded against live staging columns in `branch_expenses`, `cash_reconciliations`, `fiscal_periods`, `finance_journal_entries`, `payment_settlements`, `payment_settlement_items`, `refund_records`, `pos_sales`, `pos_sale_tenders`, and `pos_shifts`.

### Confirmed journal contract (and its limitation)

- `finance_journal_entries` has one row per entry with `entry_code`, nullable `fiscal_period_id` and `branch_id`, `source_type`, nullable `source_id`, `entry_date`, `debit_account`, `credit_account`, positive `amount_idr`, `description`, status defaulting to `posted`, optional `reverses_entry_id`, and `created_by`.
- This is a paired-account single-row journal model, not a multi-line journal batch. It has no explicit tenant id, journal-batch id, independent approval fields, posting idempotency key, or payroll source FK in the inspected columns. A single row may express a debit/credit pair, but a complete payroll journal needs multiple balanced entries and a durable batch-level balance invariant.
- `fiscal_periods` provides date boundaries and open/closed state with close/reopen actor/time metadata. Posting must be rejected outside an open period and must not infer a valid period from a client date alone.
- `branch_expenses` has branch, category, amount, payment method, approval status and reviewer metadata, but zero staging rows were reported in the table catalogue.
- `payment_settlements` has gross, fee, optional net/received amount, provider reference, status, and reconciliation actor/time. Settlement items can reference payment records or POS sales. `matched`/received is distinct from a posted payroll journal and a reconciled payroll liability.
- `cash_reconciliations` is a shift/business-date record with cash/bank/QRIS expected and received values plus review status. It is not an AP/payroll liability ledger.
- `refund_records` carries order/payment/POS source refs, amount, requested/reviewed/processed lifecycle and actor/time fields. Only processed refunds can reduce eligible transaction revenue; refund-to-line allocation and over-refund prevention must be enforced before any CRM award or BI net-sales snapshot.
- `pos_sales` exposes branch/shift, subtotal, discount, total and payment status. `pos_sale_tenders` records tender method and amount per sale. Neither alone establishes Finance close or payroll expense posting.

### Payroll implementation consequence

The existing HR payroll outbox remains a safe handoff draft only. The Finance table is not yet adequate evidence for claiming an atomic, balanced, tenant-scoped payroll journal. The next implementation must either extend Finance with an immutable journal-batch/header plus lines, source references, idempotency, independent approval, period validation, balanced debit/credit totals, reversal linkage, and audit events—or formally model payroll postings as a sequence of paired entries under a new immutable batch envelope. Do not insert one arbitrary journal row or mark the HR outbox posted.

Required account mapping must be explicitly approved: wage expense by branch, employer contribution/benefit expense where applicable, payroll tax/deduction liabilities, net wages payable, and payment clearing/cash. The payroll calculation itself must first support the applicable effective-dated compensation components (hourly/monthly, overtime, allowances, benefits, tax, deductions) and independently reviewed net pay. No component rates, tax tables, or payment provider may be invented.

### Staging evidence and restrictions

The live table catalogue showed zero rows in `finance_journal_entries`, `fiscal_periods`, `payment_settlements`, `payment_settlement_items`, `refund_records`, `cash_reconciliations`, and `branch_expenses` at the time of inspection. This is absence of positive workflow fixtures, not proof that the schemas are unusable. No data was read or written for this mapping. No migration, Auth change, Edge deployment, test, merge, or release-flag change was performed.


## Payroll calculation kernel implementation (source-only, 2026-11-25)

Added `src/hr-payroll-calculation.mjs` as a deterministic, side-effect-free payroll line calculation kernel. It supports:

- hourly regular wages from approved minute inputs;
- overtime only when an explicit approved multiplier is supplied;
- monthly salary only with an explicit proration ratio (no implicit calendar/workday assumption);
- effective-dated, approved fixed-IDR or basis-point components for earnings/allowances, deductions/tax, and employer contributions/benefits;
- non-negative net pay, safe-integer IDR amounts, duplicate component rejection, and a versioned calculation result.

The module intentionally does not invent statutory tax tables, contribution rates, overtime rules, or payment providers. It is not yet wired into the persisted payroll run/line schema or Finance journal batch. Edge authorization, approval provenance for every input, database constraints, payment execution, journal posting, reversal and reconciliation remain outstanding. No tests were run, as requested; this source change is queued for the final test batch. No migration or staging/production mutation was performed.


## Payroll-to-Finance batch construction kernel (source-only, 2026-11-25)

Added `src/hr-payroll-finance-batch.mjs`. It accepts only an approved payroll run and immutable payroll line snapshots, requires explicit Finance account mappings for wage expense, net wages payable, each deduction liability and each employer-contribution expense, and emits a draft multi-line journal batch. It checks per-employee gross minus deductions equals net, unique employee lines, safe integer IDR values, component-to-total balance, and aggregate debit/credit equality. It deliberately returns `paymentStatus=not_paid` and `reconciliationStatus=not_reconciled`; it does not write the Finance ledger or claim posting.

This kernel is not yet connected to a persisted Finance batch header/lines, open fiscal-period lock, independent Finance approval, posting/reversal RPC, payment execution, or settlement reconciliation. Finance must approve account codes and the payroll calculation policy before runtime wiring. No tests, migrations, shared staging writes, merges or production operations were run.


## CRM eligible net-sales earning gate (source-only, 2026-11-25)

Added `src/crm-eligible-net-sales.mjs`. The pure gate rejects raw POS/order/payment rows and requires a canonical reconciled close with tenant/branch/source identity, approved shift reconciliation, settlement reconciliation (not merely `matched`), posted Finance journal batch plus source reconciliation, and complete processed-refund evidence. It validates discounts/refunds against subtotal, reconciles refund evidence totals, requires an approved versioned earning rule, and emits an idempotent award candidate. It does not write a loyalty ledger entry or award points by itself.

The required canonical financial-close projection is not yet present in the inspected staging schema. The module therefore documents and enforces the required contract at the domain boundary but is not wired to a source-of-truth DB/RPC. Do not connect it to `payment_status=paid` or settlement `matched`. Campaign provider delivery remains blocked until an actual approved provider and signed callback contract are selected. No tests/migrations/staging writes were run.


## Eight-domain workflow kernel progress (source-only, 2026-11-25)

Added the following provider-neutral/domain-boundary modules on the active feature branch:

- `src/delivery-webhook-verification.mjs`: HMAC-SHA256 verification over timestamp + raw body, timestamp replay window, constant-time signature comparison, stable event/dispatch identity, payload-hash collision detection and private proof-upload intent with MIME/size/path checks. No provider is selected and no Storage upload is performed.
- `src/franchise-opening-governance.mjs`: active/reserved territory city/postal conflict detection and opening eligibility requiring a signed versioned contract, approved site evidence, ten named checks, independent verifier and verified tenant/branch provisioning.
- `src/bi-lineage-freshness.mjs`: metric/formula version, declared source lineage, tenant-scoped source IDs/hashes, complete period-covering freshness watermarks and reviewed source reconciliation gate.
- `src/saas-post-commit-metering.mjs`: refuses metering before an authoritative commit ID; calls a server-side usage RPC adapter after commit and surfaces failures with retry context.
- `src/procurement-ap-journal.mjs`: balanced AP journal draft from approved, fully matched invoice lines with explicit expense/AP accounts; explicitly not paid or reconciled.
- `src/executive-drilldown-authorization.mjs`: fail-closed tenant and company→region→branch→shift→transaction ancestry/scope authorization helper.
- Payroll batch correction: employer contribution components now debit the explicit expense account and credit the explicit payable liability account; component subtotals must reconcile to payroll line totals.

These are source-level workflow kernels, not end-to-end feature completion. The matrix now moves four features from NOT VERIFIED/BLOCKED to PARTIAL because concrete work has started: Delivery cancel/retry, Franchise territory controls, Procurement AP handoff, and Executive drill-down authorization. Their remaining persistence, adapters, runtime and reconciliation gaps are explicit. No feature was marked DONE. No tests, merge, migration, Supabase mutation, deployment or release change was performed, per the agreed sequencing.


## CRM financial-close contract extension (source-only, 2026-11-25)

Added `src/crm-financial-close.mjs`. This is a server-side projection contract, not a DB transaction or authorization layer. It requires tenant/branch/source-scoped source identity, the complete processed-refund set, source-linked reconciled settlement with gross/fee/net/received arithmetic, approved shift close containing the source exactly once with expected=received totals, and a posted/reconciled balanced Finance batch whose amount matches the approved source mapping. It derives eligible net sales only after those checks. Callers must load all records server-side under verified tenant scope; never accept this projection from a browser/client.

The contract does not prove the existing staging schema currently stores one canonical close snapshot or provides a transactionally atomic RPC. That persistence/RPC and actual POS/order/refund/settlement/shift/Finance adapters remain a blocker before automated award writes. Loyalty earning must remain disabled until these are implemented and verified.

## Payroll journal balance correction (source-only, 2026-11-25)

Reviewed `src/hr-payroll-finance-batch.mjs`: employer contribution expense now has an explicit matching payable credit, and line-level component totals are checked against deductions, earnings and employer contribution totals. Both expense and liability account mappings are required. The batch remains a draft-only projection, not a Finance posting. This change is source-only; no tests, migrations or database writes were run.


## Eight-domain workflow continuation — source-level kernels (2026-11-25)

The following additional domain-boundary modules were added on the active feature branch. They intentionally stop before claiming a persisted workflow or successful external operation:

- `src/crm-campaign-delivery.mjs`: consent is checked for tenant/customer/channel/purpose and expiry before dispatch; dispatch requires an approved provider adapter and durable idempotent outbox claim; provider acceptance is recorded separately from delivery; retry is requested on provider failure; delivery receipts and unsubscribe callbacks require provider-specific signature verification and event collision protection. No provider is selected/configured, no webhook endpoint or durable receipt inbox has been deployed, and contribution-margin attribution is still needed for true ROI.
- `src/hr-payroll-payment-reconciliation.mjs`: payment is reconciled only when an approved payroll run has an executed payment batch, unique final provider settlements exactly equal net pay, and the Finance batch is posted and source-reconciled. No payment rail or payment execution has been performed.
- `src/delivery-financial-reconciliation.mjs`: delivered dispatch, order/tenant identity, final carrier settlement, customer charge, subsidy, COD and Finance amounts must reconcile exactly. No provider-specific fields or live settlement evidence were invented.
- `src/franchise-contract-lifecycle.mjs`: contract versions form an immutable document-hash chain; signature evidence and independent reviewer are required; closure requires settled obligations, paid/reconciled final royalty, tenant export checksum, retention approval and independent approval. Signing and lifecycle persistence are not wired.
- `src/bi-branch-performance.mjs`: target-vs-actual aggregation refuses incomplete populations; it requires exactly 150 active branches in the supplied tenant, one approved target and one reconciled exact-period fact per branch, then returns rankings and variance. This is not evidence that 150 live branches or facts currently exist.
- `src/saas-entitlement-enforcement.mjs`: fail-closed tenant/subscription/entitlement/quota precondition and suspension eligibility requiring grace expiry, approval, invoice resolution and reconciled settlements. API-wide enforcement and atomic quota reservation remain open.
- `src/procurement-payment-reconciliation.mjs`: supplier payment is reconciled only after executed payment, final unique settlements, exact invoice amount and posted/reconciled AP journal. No payment was initiated.
- `src/executive-finance-kpi.mjs`: Executive KPI requires approved Finance metric/formula, posted facts and reviewed source reconciliations plus an approved target.
- `src/crm-campaign-delivery.mjs` additionally enforces consent expiry and handles signed receipt/unsubscribe event contracts with duplicate collision protection and bounded retry/dead-letter decisions.

The feature matrix evidence was refreshed for these workflows. Overall counts remain 126 PARTIAL / 59 NOT VERIFIED / 4 BLOCKED / 0 DONE out of 189; no feature was promoted to DONE. These are implementation starts, not E2E acceptance. Tests, merges, migrations and staging/production mutations remain deferred to the final batch as requested. CI may run automatically from source commits and is tracked separately.
