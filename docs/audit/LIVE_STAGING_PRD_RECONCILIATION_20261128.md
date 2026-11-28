# D’Lice FnB OS — Live staging / PRD reconciliation
**Audit date:** 28 November 2026 (Asia/Jakarta)  
**Repository:** `dlice8888/dlice-landing-page`  
**Code branch:** `staging`  
**Vercel preview commit:** `5b559b3203d5bfb2732111fe0507abfed5cec3b6`  
**Supabase project:** `dlice-staging` (`higoadrzxnhzbbwhdbmh`, ACTIVE_HEALTHY, PostgreSQL 17.11)

## 1. Executive result

The user-provided rollup (189 total / 145 partial / 39 unproven / 5 blocked) is an older snapshot. The canonical staging ledger `docs/audit/PRD_FEATURE_EVIDENCE_LEDGER_20261126.json`, generated 2026-11-28, currently classifies **189 total / 188 PARTIAL / 0 NOT VERIFIED / 1 BLOCKED / 0 DONE**. This is an implementation-start classification, not a completion claim.

- 53 features have a numeric score (46 explicit partial-credit + 7 provisional).
- 135 PARTIAL features remain unscored at feature level; the single BLOCKED feature is also unscored (136 unscored rows total).
- Overall mean of the 53 scored features: **40.6%**. This is a mean of the scored subset only, not a weighted score for all 189 features.
- Evidence dimensions across the 189 rows: code/UI 3 verified, 48 partial, 138 unverified; database 8 verified, 0 partial, 181 unverified; authorization 5 verified, 46 partial, 138 unverified; automated tests 51 verified, 0 partial, 138 unverified; E2E workflow 0 verified, 0 partial, 189 unverified; reconciliation/observability 0 verified, 30 partial, 159 unverified.
- Therefore, **0/189 features currently meet the complete workflow/E2E evidence gate**. DONE remains 0.

## 2. Reconciled domain rollup

| Domain | Total | Partial | Not verified | Blocked | Scored features | Mean of scored subset | Unscored |
|---|---:|---:|---:|---:|---:|---:|---:|
| Executive Command Center | 10 | 9 | 0 | 1 | 2 | 38.0% | 8 |
| POS & Checkout | 13 | 13 | 0 | 0 | 6 | 62.2% | 7 |
| Order Management | 10 | 10 | 0 | 0 | 2 | 38.0% | 8 |
| Kitchen & Production | 10 | 10 | 0 | 0 | 3 | 38.0% | 7 |
| Menu, Recipe & Product Engineering | 11 | 11 | 0 | 0 | 4 | 35.5% | 7 |
| Inventory & Warehouse | 12 | 12 | 0 | 0 | 2 | 38.0% | 10 |
| Procurement & Supplier | 10 | 10 | 0 | 0 | 3 | 33.0% | 7 |
| Branch Operations | 10 | 10 | 0 | 0 | 6 | 33.8% | 4 |
| Delivery & Fulfillment | 8 | 8 | 0 | 0 | 0 | Belum ada | 8 |
| CRM, Loyalty & Marketing | 9 | 9 | 0 | 0 | 5 | 41.0% | 4 |
| Finance & Accounting | 12 | 12 | 0 | 0 | 3 | 38.0% | 9 |
| HR & Workforce | 9 | 9 | 0 | 0 | 3 | 43.0% | 6 |
| Franchise & Expansion | 8 | 8 | 0 | 0 | 0 | Belum ada | 8 |
| BI & Analytics | 10 | 10 | 0 | 0 | 3 | 38.0% | 7 |
| Admin, Identity & Access Control | 10 | 10 | 0 | 0 | 2 | 38.0% | 8 |
| SaaS Tenant Management | 8 | 8 | 0 | 0 | 3 | 42.0% | 5 |
| Integrations & Automation | 9 | 9 | 0 | 0 | 3 | 38.0% | 6 |
| Quality, Compliance & Security | 20 | 20 | 0 | 0 | 3 | 38.0% | 17 |
| **TOTAL** | **189** | **188** | **0** | **1** | **53** | **40.6% (scored subset only)** | **136** |

Do not interpret the per-domain mean as a domain completion percentage where features remain unscored. "Belum terbukti" at the status-rollup level is zero because every feature has a concrete implementation-start record; the underlying evidence gaps remain open inside PARTIAL.

## 3. Live Supabase evidence

Read-only checks against `dlice-staging`:

- Project status ACTIVE_HEALTHY; PostgreSQL 17.11.
- 146/146 public base tables have RLS enabled.
- 161 public functions; direct EXECUTE is available to neither `anon` nor `authenticated` for the inspected public function set (0/161 each).
- 73 migrations are recorded in the live migration ledger.
- Active Edge Functions: `branch-operations` (verify_jwt=true), `hr-payroll-provider-webhook` (verify_jwt=false), and `dlice-orders` (verify_jwt=false). The latter two require their own complete request authentication/signature authorization tests; verify_jwt=false is not itself proof of a vulnerability, but it is a mandatory review point.
- Domain tables exist for CRM, HR/payroll, Delivery, Franchise, BI, SaaS, Executive and Branch Operations, but the sampled workflow tables have zero persisted rows. Schema existence is not workflow proof.

### Critical Owner authorization discrepancy

The live Auth read-only query found 4 Auth users, 4 admin profiles, 3 active tenant memberships, and 1 Owner-role profile, but **0 Auth users with `app_metadata.platform_owner` as JSON boolean true** (also 0 users with any `platform_owner` claim). This contradicts the prior narrative that Owner Auth had been fixed. The Owner drill-down gate remains blocked until the existing Owner account is updated through the official Supabase Auth Admin path and verified from a refreshed authenticated session. Do not use SQL to edit Auth metadata.

### POS persisted-data reconciliation snapshot

- POS sales: 6; KDS tickets: 6; stock movements: 26.
- POS sale tenders: 0; immutable POS receipts: 0; held orders: 0; checkout idempotency rows: 0.
- Cash reconciliations: 0; Finance journal entries: 0.
- CRM customers/loyalty entries, HR payroll runs, Delivery dispatches, Franchise agreements, BI snapshots, SaaS subscriptions, Executive rankings, Branch Operations tasks/incidents: 0 in the queried tables.

This is not a positive POS reconciliation. The six sales cannot be called reconciled to tenders, immutable receipts, cash drawer, Finance or inventory based on these counts.

## 4. Migration source/ledger drift discovered after PR #154

PR #154 recorded an earlier parity checkpoint of 72 source migration files / 72 applied versions. PR #156 was subsequently squash-merged into `staging` as commit `243ca3e3237d9a233258fa56719325b860ccafdb`. The merged source file is `20261128083515_revoke_service_role_receipt_trigger_execute.sql`, matching the live ledger version `20261128083515` and name `revoke_service_role_receipt_trigger_execute`. A fresh source listing now contains **73 migration files** and the live Supabase ledger contains **73 applied versions**. The ACL was independently queried after merge: `anon`, `authenticated`, and `service_role` cannot directly execute `public.prevent_pos_sale_receipt_mutation()`; `postgres` retains execution, and the immutable receipt trigger remains attached. The migration was already applied to staging before the source merge, so **no DDL was re-applied**. Source/ledger count and the final migration version/name now align; continue exact per-version parity checks as part of release validation.

## 4. Vercel evidence

The latest staging Preview deployment is READY at commit `243ca3e3237d9a233258fa56719325b860ccafdb` (PR #156 receipt-trigger ACL source merge). READY establishes build/deployment success only; it does not establish runtime workflow acceptance. No production deployment or release action is authorized by this audit.

## 5. Supabase Advisor findings

- Security: 1 warning — native leaked-password protection is disabled. The application-level password guard does not replace native Auth protection for direct Auth password changes.
- Performance: 168 unindexed foreign-key findings. Review the exact FK definitions and existing indexes, generate only missing supporting indexes, then validate plans and disposable replay. Do not apply guessed blanket index SQL.
- Health: no lints returned.

## 6. Priority gap register (feature-level detail remains in the canonical ledger)

### Executive Command Center
- **D01-F01 — Company overview / owner dashboard:** PR #145 adds snapshot, branch KPI and executive alert primitives. Owner-level live consolidated overview is not end-to-end proven; source collectors and staging E2E remain missing.
- **D01-F02 — Live sales monitor (day/week/month):** Basic reporting UI exists; verify against source orders and business-date cutoff.
- **D01-F03 — Branch ranking, region/format comparison:** PR #145 adds branch KPI snapshots and cohort/benchmarking metadata. Comparable cohort data population and live 150-branch reconciliation remain unproven.
- **D01-F04 — Gross/net sales, discounts, refunds, margin, AOV, item counts:** PR #145 adds formula-versioned metric definitions and reconciliation-gated snapshot publishing. POS/Order/Finance gross-to-net source collectors and margin evidence remain incomplete.

### POS & Checkout
- **D02-F01 — POS workspace, shifts, cash reconciliation:** POS sales/shifts and cash reconciliation structures exist; complete operating-day E2E still needed.
- **D02-F02 — Cart, product selection, quantity updates:** Checkout/cart foundations exist; full modifier and concurrency coverage not proven.
- **D02-F03 — Dine-in, takeaway, pickup, delivery parity:** Pickup/delivery fields exist; all order types and downstream behavior need E2E.
- **D02-F06 — Cash, QRIS, card, transfer and other provider methods:** Payment-proof/status foundations exist; live provider confirmation and settlement parity not proven.

### Order Management
- **D03-F01 — Online and POS orders / shared queue:** Online order flow and ERP queue foundations exist.
- **D03-F03 — Hours, cutoff, menu availability, branch capacity:** Branch routing/capacity and WIB/WITA/WIT cutoff contract exist; full browser E2E still needed.
- **D03-F04 — Branch assignment by area/capacity:** Routing foundation exists; overload/failover cases not proven.
- **D03-F05 — Unique business order number:** DLC date/sequence formatter exists; uniqueness and concurrency acceptance needed.

### Kitchen & Production
- **D04-F01 — KDS and kitchen order tickets:** KDS tables and dispatch/transition RPCs exist; staging has 6 tickets and 6 items. Station routing and positive live workflow remain unproven.
- **D04-F03 — Queue priority and prep SLA:** kitchen_tickets.priority exists and is persisted; SLA targets, overdue escalation and station-level queue behavior are not implemented/proven.
- **D04-F04 — Waiting → in progress → ready → handed over:** Fulfillment/status foundations exist; kitchen-specific state machine and E2E missing.
- **D04-F05 — Recipes, portion/yield and waste tolerance:** Recipe/BOM and actual consumption structures exist; yield/tolerance calculations incomplete.

### Menu, Recipe & Product Engineering
- **D05-F01 — Central product catalog and categories:** Product catalog exists; full category/variant/modifier lifecycle needs proof.
- **D05-F02 — Per-branch availability:** Branch capacity/availability foundations exist; real branch parity unverified.
- **D05-F03 — Central, regional and branch-specific pricing:** branch_settings has a pricing category and branch settings read/write handlers exist; central/regional hierarchy, effective-date approvals and branch parity remain unproven.
- **D05-F04 — Recipe/BOM and ingredient mapping:** Recipe ingredients and version activation exist.

### Inventory & Warehouse
- **D06-F01 — Inventory item and branch stock:** Inventory items and branch inventory exist.
- **D06-F02 — Stock movement ledger:** Stock movement table and atomic receiving/production flows exist; all movement sources need reconciliation.
- **D06-F03 — Warehouse/storage/bin hierarchy:** warehouses table and ERP list/create handlers exist; storage zones/bins, location hierarchy and transfer integration remain unproven.
- **D06-F04 — Purchase/use units and conversions:** Item/recipe quantity structures exist; conversion and rounding policy incomplete.

### Procurement & Supplier
- **D07-F01 — Supplier directory:** PR #145 adds explicit tenant-to-supplier relationship, pending/active/suspended/revoked lifecycle and independent approval. Supplier master and branch directory remain in existing base schema; price-list/contract history remains unproven.
- **D07-F03 — Purchase requisition from branch/warehouse/central kitchen:** PR #36 adds branch-scoped multi-line requisitions, draft/submit/Owner approve-or-reject/convert-to-PO, service-role-only atomic RPCs, audit trail, and ERP UI. Positive runtime E2E has not yet run; warehouse/central-kitchen consolidation remains missing.
- **D07-F05 — Purchase order draft, submit, approval, ordered:** PO state transitions exist; positive-path test still needed.
- **D07-F06 — Approval limits by value/category:** Approval actions exist; configurable thresholds/delegation not proven.

### Branch Operations
- **D08-F01 — Branch directory, status, timezone and assignments:** Branch master, timezone and job assignments exist; 150 branch data readiness is not established.
- **D08-F02 — Opening and closing checklists:** Checklist runs, item status and critical-item completion gates exist.
- **D08-F05 — SOP and work instructions:** Operating model/docs exist; in-app versioned SOP delivery not proven.
- **D08-F06 — Cleanliness, equipment and safety checks:** Checklist foundations exist; calibrated evidence and full templates missing.

### Delivery & Fulfillment
- **D09-F01 — Pickup/delivery selection and fulfillment queue:** PR #145 adds atomic delivery dispatch lifecycle and outbox adapter/worker with tenant-scoped actions; provider sandbox and staging E2E remain unproven.
- **D09-F02 — Address validation and delivery quote:** PR #145 adds address/quote and delivery workflow adapter contracts. Real provider quote validation remains blocked on credentials/fixtures.
- **D09-F03 — Courier booking / Biteship integration:** PR #145 adds provider-neutral courier booking workflow; Biteship provider credentials and sandbox E2E are not supplied and not enabled.
- **D09-F04 — Dispatch and shipment tracking:** PR #145 adds dispatch and tracking event ingestion/outbox path. Provider-signed runtime tracking and reconciliation are not proven.

### CRM, Loyalty & Marketing
- **D10-F02 — Consent and communication preferences:** PR #145 includes consent preferences and signed campaign receipt/unsubscribe workflow; channel provider callback and consent enforcement across all dispatchers remain unproven.
- **D10-F03 — Customer segments:** Segment rules and refresh jobs missing.
- **D10-F05 — Rewards and vouchers/coupons:** PR #145 base CRM schema contains rewards/vouchers, atomic reward redemption and voucher consume/void paths. Expiry extension now allocates redeemed points to source lots; reward lifecycle E2E and staging persistence remain unverified.
- **D10-F07 — Campaign management and ROI:** PR #145 adds campaign approval, provider config approval, audience preparation, outbox dispatch and signed receipt/ROI evidence. Provider delivery and ROI reconciliation remain unproven.

### Finance & Accounting
- **D11-F01 — Finance overview, expenses and approvals:** Branch expense approval foundations exist.
- **D11-F02 — Cash/bank, settlement creation and matching:** PR #146 adds payroll payout settlement/reconciliation primitives; bank statement ingestion and live settlement matching remain unproven.
- **D11-F04 — AR/AP subledgers and aging:** Complete AR/AP workflows and control-account tie-out missing.
- **D11-F05 — Chart of accounts and general ledger:** PR #145/#146 extend Finance journal and payroll clearing source references. Full GL posting, period close and chart-of-accounts runtime are not proven.

### HR & Workforce
- **D12-F01 — Employee directory and lifecycle:** PR #144/#145 add employee lifecycle and HR UI/schema contracts; actual recruitment/onboarding/offboarding integration and staging E2E remain gaps.
- **D12-F02 — Organization hierarchy and job positions:** PR #144/#145 add organization/position lifecycle data and UI contracts; complete branch/role permission E2E remains unproven.
- **D12-F03 — Attendance and timesheets:** PR #144/#145 add attendance/timesheet workflows; device/punch source integration and approved payroll reconciliation remain unproven.
- **D12-F04 — Shift scheduling and replacement:** PR #144/#145 add shift schedule and replacement workflow contracts; real shift coverage/attendance E2E remains unproven.

### Franchise & Expansion
- **D13-F01 — Branch ownership model:** PR #144/#145 extend branch ownership and franchise tenant-scope model; full production tenant-provisioning E2E is not run.
- **D13-F02 — Franchise directory/application:** PR #145 adds franchise application and agreement workflow; legal document and applicant conversion E2E remain unproven.
- **D13-F03 — Site selection and feasibility:** PR #145 adds site feasibility and evidence-backed review primitives; geospatial/site scoring data integration remains a gap.
- **D13-F04 — Opening project and readiness:** PR #145 adds ten opening gates and independent review; provisioning and opening-to-first-sale E2E remains unproven.

### BI & Analytics
- **D14-F01 — Basic overview, funnel metrics and reports:** PR #144/#145 add KPI snapshot, funnel/branch views and publish controls; live source collectors and scheduled reporting remain gaps.
- **D14-F02 — Official KPI dictionary and versioning:** PR #144/#145 add metric dictionary, formula version, unit, owner domain and source lineage approval; complete catalogue approval remains unproven.
- **D14-F03 — Net sales/AOV/gross margin:** PR #144/#145 add net-sales/AOV/gross-margin metric definitions and reconciliation gates; authoritative POS/Order/Finance source collectors remain incomplete.
- **D14-F04 — Food cost %, labor cost %, waste %:** PR #144/#145 add food-cost/labor/waste KPI definition and lineage structures; actual stock/recipe/payroll data ingestion is not wired.

### Admin, Identity & Access Control
- **D15-F01 — User/admin profiles, role and permission actions:** Admin profile and action-level permission foundations exist.
- **D15-F02 — Branch assignments and scope enforcement:** Server-side branch checks exist; full matrix testing is ongoing.
- **D15-F03 — Owner/manager/no-permission/inactive identity probes:** An existing negative/role suite reports 21 PASS / 0 FAIL. This is concrete test work, but it is not complete positive business E2E or live acceptance for all roles and inactive identities.
- **D15-F04 — Audit logs for sensitive actions:** Audit log table and events exist; coverage of all sensitive mutations not proven.

### SaaS Tenant Management
- **D16-F03 — Plans, subscriptions, entitlements and quotas:** PR #145 adds plan version, subscription, trial conversion, entitlement and quota RPCs; database replay and API-wide enforcement remain unproven.
- **D16-F04 — Billing, invoices and usage metering:** PR #145 adds invoice issuance, payment-state/partial settlement RPC and usage metering worker. Provider-signed payment webhook and Finance reconciliation remain gaps.
- **D16-F05 — Tenant settings and suspension:** PR #145 adds cancel/suspend and grace-period billing lifecycle; complete suspend/reactivate enforcement across all tenant APIs remains unproven.
- **D16-F07 — Export/offboarding and data deletion policy:** PR #145 adds independent offboarding approval, retention/legal-hold guard and completion evidence; export and deletion execution are intentionally not implemented.

### Integrations & Automation
- **D17-F01 — Edge Function API and payment proof flow:** Shared \dlice-orders\ endpoint and payment proof/status paths exist.
- **D17-F02 — Payment provider callback signature and status validation:** PR #146 adds Xendit callback signature/token verification and normalized payout event handling; real provider webhook fixture and sandbox E2E remain blocked.
- **D17-F04 — Webhooks and event log:** PR #145/#146 add CRM/delivery/payroll event outbox and webhook handling contracts; provider receipt runtime and end-to-end retry evidence remain incomplete.
- **D17-F05 — Idempotency and replay protection:** PR #123/#127/#146 add idempotency and replay guards for checkout/payment/payout paths; complete provider event replay E2E remains pending.

### Quality, Compliance & Security
- **D18-F01 — RLS on exposed public tables:** Live read-only SQL on 2026-11-20: 64/64 public tables have RLS enabled and 64 public policies exist. Per-table policy correctness and full role/tenant negative runtime tests remain outstanding, so this is PARTIAL rather than PASS.
- **D18-F02 — Direct access to internal stock/procurement/audit data:** No direct anon/authenticated SELECT grants on key internal tables; endpoint-level scope tests still required.
- **D18-F03 — Exact-origin CORS:** Staging CORS runtime run 44307838539 passed registered-origin OPTIONS (200/exact ACAO), foreign-origin OPTIONS (403/no ACAO), and no-Origin OPTIONS (200/no ACAO). POST/authenticated action coverage and full endpoint regression remain outstanding.
- **D18-F04 — Custom auth/permission checks on shared endpoint:** \verify_jwt=false\ remains; custom action authentication is present, so every action must remain covered by regression tests.

## 7. Required execution sequence

1. **P0 Owner authorization:** resolve the one Owner profile against the correct existing Auth user via official Auth Admin; verify boolean `app_metadata.platform_owner=true`, Edge allowlist, refreshed JWT, positive Owner hierarchy drill-down, and negative non-Owner/other-tenant cases. Keep the executive drill-down feature BLOCKED until proven.
2. **P0 POS operating-day E2E:** on an approved staging fixture, exercise checkout with split tenders, hold/resume, immutable receipt, KDS dispatch, offline replay, refund/void, cash drawer close and finance posting. Reconcile sale total = tender allocation = receipt total; cash allocation = drawer delta; KDS ticket item/modifier snapshot = sale; stock consumption = approved recipe; immutable receipt and audit events persist exactly once.
3. **P1 CRM + Loyalty:** wire customer identity/consent to POS and Order, award/expiry/reversal ledger, voucher redemption, campaign outbox/provider receipt, attribution and Finance-reconciled ROI. Add authenticated adapters/UI and positive/negative tenant E2E.
4. **P1 HR + Finance:** employee lifecycle, attendance, schedules, leave/coverage, timesheets, approved compensation, payroll calculation, independent approval, Finance journal posting, provider callback and payment/bank reconciliation.
5. **P1 Delivery + Integrations:** provider-specific approved adapter, signed webhook, replay/dedupe, dispatch state machine, POD evidence, COD/courier-cost settlement, retries/dead-letter and Finance reconciliation. No provider is to be claimed configured without an approved account and credentials.
6. **P1 Franchise + SaaS:** independently approved effective-dated agreements, verified signature provider, ten opening gates, separate tenant/branch provisioning, royalty settlement; plans, entitlements, subscription billing, signed payment callbacks, API-wide quota enforcement, suspension and export/offboarding.
7. **P1 BI + Executive:** authoritative POS/Order/Inventory/HR/Finance collectors, source lineage/watermarks, formula versions, reconciliation-gated snapshots, KPI targets, branch cohorts, alert assignment/resolution and company→region→branch→shift→transaction drill-down.
8. **P1 Branch Operations + Quality:** complete equipment/tasks/incidents/work orders/compliance evidence lifecycle; food safety policy, lot traceability, recall, quarantine, supplier CAPA and independent release.
9. **P2 Platform quality:** resolve the 168 exact unindexed FK findings, enable native leaked-password protection where supported, verify every exposed-table policy and every privileged RPC, test 150-branch concurrency, backup/restore, responsive accessibility, observability and rollback.
10. Re-score all 189 feature rows from the six evidence dimensions (20/20/15/15/20/10). Do not fill unknown scores with invented percentages. Mark DONE only after exact-head tests, disposable migration replay, database authorization, staging browser E2E and financial/operational reconciliation all pass.

## 8. Safety and release controls

- Scope all implementation and validation mutations to `dlice-staging`.
- Production remains read-only.
- Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.
- No automatic merge, no force-push, no release, and no production changes. The manually authorized staging-only merge of PR #156 was completed after disposable migration replay and ACL verification.
- Do not apply further staging migrations or run business-data mutation E2E until the final validation batch is explicitly authorized; use disposable replay for schema/test iteration first.
- This document is an audit reconciliation. It does not mark any feature DONE or claim unrun tests as PASS.

## 9. Sources of truth

- Canonical feature ledger: `docs/audit/PRD_FEATURE_EVIDENCE_LEDGER_20261126.json` on `staging`.
- Feature matrix: `docs/audit/FNB_OS_IMPLEMENTATION_MATRIX.json` on `staging`.
- Live Supabase project catalog, migration history, RLS/function privilege queries and Advisor results captured 2026-11-28.
- Vercel staging Preview deployment metadata for commit `243ca3e3237d9a233258fa56719325b860ccafdb`.


## 8. Exact staging HEAD re-check — 2026-11-28

**Exact staging HEAD:** `5b559b3203d5bfb2732111fe0507abfed5cec3b6`  
**Vercel Preview:** READY for this exact commit. This is deployment/build evidence only.

### Owner Auth Admin and allowlist

A fresh read-only query against the existing Owner UUID `378f02bc-2719-4b07-9107-4ce94299aa27` confirms:

- `admin_profiles.role = 'owner'`, `is_active = true`, and the Auth user is not banned.
- `raw_app_meta_data->'platform_owner'` is NULL; it is not JSON boolean `true`.
- The staging Edge Function source requires both the exact Owner UUID in `DLICE_PLATFORM_OWNER_USER_IDS` and `auth.getUser(token).app_metadata.platform_owner === true`.
- PR #158 exact head `8de35d89863862d1a6d88b2534fd9892d489b263` has Free quality checks PASS (run `46128998100`), but its manually gated Auth Admin workflow has not been executed. The Edge Function secret value is not exposed by the connected tools, so allowlist membership is NOT VERIFIED.

Do not edit `auth.users` metadata through SQL. Do not infer allowlist membership from the source parser or from PR checks.

### Tenant A/B and Branch Operations

- The existing QA fixture branches resolve to Tenant A / `QA-DLICE-A` and Tenant B / `QA-TENANT-B`; both are active.
- Staging Tenant Isolation Acceptance run `46132419164` passed P01–P09 on commit `243ca3e3237d9a233258fa56719325b860ccafdb`.
- The current exact HEAD `5b559b3203d5bfb2732111fe0507abfed5cec3b6` has a passing Free quality check (run `46132560932`), but no tenant-isolation run is recorded on this exact SHA. The prior P01–P09 pass is therefore a parent-commit result, not exact-HEAD acceptance.
- Live Branch Operations persistence has 7/7 tables with RLS and one policy each; 14 `branch_ops_*` RPCs exist, and the `branch-ops-evidence` bucket is private.
- PR #153 Branch Operations disposable replay passed on its exact candidate head `b107f20b1629b8b20e7359da0e644c9da99809fb` (run `46100334022`), including the 92-assertion Branch Operations pgTAP suite and full migration replay.
- The seven Branch Operations tables currently contain no operational rows. Live authenticated Tenant A/B, Branch A/B, Storage upload/download and browser workflow acceptance remain unproven.

### POS, cash drawer and Finance reconciliation

PR #143 remains open at head `0e3539b02c65a6411ccca0d37bb3ee94d912c740`; it is not the current staging HEAD.

- Static checks and disposable migration replay for the PR candidate passed, but its positive staging POS E2E failed before business mutations with `STAGING_AUTH_BLOCKED`.
- The current six persisted QA sales have six items and six KDS tickets, but zero tender rows, zero immutable receipts, zero cash reconciliations and zero Finance journal entries.
- The PR #143 candidate E2E source covers split tender exact-sum, cash-vs-noncash drawer delta, split-tender idempotency, stock movements, KDS, immutable receipt retrieval and audit events. None of those new positive-path assertions ran in the blocked staging E2E.
- The current reconciliation endpoint does not provide a Finance journal posting path. The inspected staging schema has no general chart-of-accounts table; `fiscal_periods`, `payment_settlements` and `finance_journal_entries` each currently contain zero rows. The POS E2E does not create/review a `cash_reconciliations` record or verify a posted Finance journal.
- Therefore split tender, immutable receipt, expected cash-drawer delta, inventory, KDS and audit reconciliation remain NOT ACCEPTED on staging. Cash reconciliation and POS-to-Finance journal integration are additional implementation gaps; do not fabricate account mappings or journal entries.

### Canonical 189-feature matrix

The canonical machine-readable ledger and matrix currently agree on 189 unique feature IDs:

| Audit status | Count |
|---|---:|
| PARTIAL | 188 |
| NOT VERIFIED | 0 |
| BLOCKED | 1 |
| DONE | 0 |
| **Total** | **189** |

53 features have numeric scores; 136 remain unscored. The single BLOCKED row remains an explicit blocker, and 0/189 meet the complete E2E + reconciliation gate. PR #155's canonical-rollup correction derives matrix totals and scoring counts from the evidence ledger; its exact-head Free quality run `46120733474` passed. It remains a draft and has not been merged.

### Execution boundary

This re-check made no staging database, Auth, Storage, Edge Function secret, deployment or release mutation. No production resource was changed. Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`; keep `BRANCH_OPS_WORKFLOWS_RELEASED=false` until live acceptance is complete.
