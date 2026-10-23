# D’Lice FnB OS — PRD Feature Register (evidence-based)
**Snapshot:** 2026-10-23 UTC  
**Target:** SaaS + ERP + POS, 150 branches  
**Implementation boundary:** GitHub \`staging\` + Supabase \`higoadrzxnhzbbwhdbmh\` + Vercel Preview. Production/main are excluded until separate explicit approval.

## Status legend
- **PASS (runtime):** actual deployed behavior has an identifiable passing test.
- **PARTIAL:** code/schema/UI exists, but one or more required behaviors or end-to-end reconciliation is missing.
- **GATE / UNVERIFIED:** cannot be accepted until a live positive/negative test, browser evidence, or operator decision exists.
- **NOT EVIDENCED:** current audit did not find sufficient implementation evidence. This does not imply the feature can never be implemented.
- A database table, menu item, handler, green build, or auth-negative test alone does not earn full feature acceptance.

## Executive score
**Current conservative coverage estimate: ~31.4% across 18 domains** (previous baseline was ~31.1% before the requisition slice). This is the unweighted mean of the domain-level estimates shown below, not a validated count of all PRD subfeatures. This is an engineering estimate, not a validated percentage of every PRD subfeature. This is a feature-coverage estimate from the staging traceability baseline, not percent complete and not readiness for 150 branches. The CORS runtime gate is now closed, but that infrastructure result does not complete any business workflow. No domain is certified fully complete.

## Latest staging checkpoint — 2026-10-24
- Applied the KDS/modifier/idempotency/recipe-stock migration and tenant/branch platform foundation to Supabase staging.
- Staging Edge Function `dlice-orders` is now v54, preserving `verify_jwt=false` and the custom authorization layer.
- Added KDS ticket dispatch/transition, idempotent POS/offline replay, opt-in recipe stock tracking, tenant memberships/invites, branch settings, warehouses, waste ledger, shift handover, integration/outbox metadata and backup/restore metadata.
- 17 new internal tables have RLS enabled and no direct grants to `anon` or `authenticated`.
- **Acceptance is still PARTIAL/GATE:** no authenticated POS→payment→KDS→stock→report reconciliation, offline fault-injection E2E, cross-tenant negative suite, real restore drill, provider sandbox delivery, visual QA, or 150-branch load/recovery run. No second live tenant should be onboarded yet.
- The overall ~31.4% estimate is intentionally unchanged until meaningful end-to-end acceptance evidence exists.

## 18-domain feature-by-feature register

### 1. Executive Command Center — baseline 20%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Company overview / owner dashboard | PARTIAL | Basic ERP overview and funnel metrics exist; authoritative rollups need reconciliation. |
| Live sales monitor (day/week/month) | PARTIAL | Basic reporting UI exists; verify against source orders and business-date cutoff. |
| Branch ranking, region/format comparison | NOT EVIDENCED | No verified 150-branch ranking/cohort output. |
| Gross/net sales, discounts, refunds, margin, AOV, item counts | PARTIAL | Some source tables/metrics exist; KPI dictionary and totals reconciled to transaction fixtures are missing. |
| Critical stock, expiry, waste alerts | NOT EVIDENCED | Lot/expiry/waste alert workflow not proven. |
| Sales-drop / food-cost anomaly detection | NOT EVIDENCED | No verified anomaly rule, assignment, acknowledgement, or closure. |
| Approval center and pending approvals | PARTIAL | Some PO/expense/refund approvals exist; unified queue and delegated policies not proven. |
| Target vs actual and executive reports | NOT EVIDENCED | Official targets, scheduled reports, and exports not proven. |
| Company → region → branch → shift → transaction drill-down | GATE | Role-aware drill-down and row-level consistency need browser and API tests. |
| Alert → assign task → resolve → audit result | NOT EVIDENCED | Assignment and action-outcome workflow not proven. |

### 2. POS & Checkout — baseline 45%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| POS workspace, shifts, cash reconciliation | PARTIAL | POS sales/shifts and cash reconciliation structures exist; complete operating-day E2E still needed. |
| Cart, product selection, quantity updates | PARTIAL | Checkout/cart foundations exist; full modifier and concurrency coverage not proven. |
| Dine-in, takeaway, pickup, delivery parity | PARTIAL | Pickup/delivery fields exist; all order types and downstream behavior need E2E. |
| Variants, toppings, special instructions | NOT EVIDENCED | Complete modifier-group flow not proven. |
| Discounts, coupons, vouchers, special pricing | NOT EVIDENCED | Rule engine, approvals, and audit evidence missing. |
| Cash, QRIS, card, transfer and other provider methods | PARTIAL | Payment-proof/status foundations exist; live provider confirmation and settlement parity not proven. |
| Split bill, partial payment, final settlement | NOT EVIDENCED | Partial/split tender lifecycle not proven. |
| Hold/resume order | NOT EVIDENCED | No verified workflow found. |
| Void, refund, return with reason and approval | PARTIAL | Refund records/request/approval/processing exist; POS void/return policy and positive E2E are incomplete. |
| Receipt printing/digital receipt | GATE | Receipt behavior needs device/browser/provider acceptance. |
| Cash in/out, drawer reconciliation, shift close | PARTIAL | Cash reconciliation/shift structures exist; positive and variance fixtures need end-to-end proof. |
| Offline sales queue and safe resynchronization | NOT EVIDENCED | Offline persistence, deduplication and replay recovery not proven. |
| Separate order, payment, fulfillment statuses | PARTIAL | Status separation foundations exist; all transitions and retry/idempotency cases need positive E2E. |

### 3. Order Management — baseline 55%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Online and POS orders / shared queue | PARTIAL | Online order flow and ERP queue foundations exist. |
| WhatsApp, marketplace, additional channels | NOT EVIDENCED | Provider integrations and contract tests missing. |
| Hours, cutoff, menu availability, branch capacity | PARTIAL | Branch routing/capacity and WIB/WITA/WIT cutoff contract exist; full browser E2E still needed. |
| Branch assignment by area/capacity | PARTIAL | Routing foundation exists; overload/failover cases not proven. |
| Unique business order number | PARTIAL | DLC date/sequence formatter exists; uniqueness and concurrency acceptance needed. |
| Consistent status/timeline across channels | PARTIAL | Order status history exists; cross-channel parity not proven. |
| Duplicate orders, delayed payment, failed order handling | GATE | Idempotency, replay, timeout and compensation tests missing. |
| Preparation ETA and exception escalation | NOT EVIDENCED | SLA prediction and escalation workflow missing. |
| Cancellation/refund and customer order history | PARTIAL | Status/refund/history foundations exist; complete lifecycle and notification proof missing. |
| Customer notifications on each state | PARTIAL | Notification log/retry foundations exist; actual delivery and idempotent event handling unverified. |

### 4. Kitchen & Production — baseline 35%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| KDS and kitchen order tickets | NOT EVIDENCED | Station-level dispatch and live KDS behavior not proven. |
| Station routing (hot/cold/beverage/packing) | NOT EVIDENCED | No verified station configuration and routing. |
| Queue priority and prep SLA | NOT EVIDENCED | Priority and overdue escalation missing. |
| Waiting → in progress → ready → handed over | PARTIAL | Fulfillment/status foundations exist; kitchen-specific state machine and E2E missing. |
| Recipes, portion/yield and waste tolerance | PARTIAL | Recipe/BOM and actual consumption structures exist; yield/tolerance calculations incomplete. |
| Prep lists and batch planning | PARTIAL | Production batches exist; forecast-driven prep planning not proven. |
| Actual material consumption | PARTIAL | Atomic production consumption RPC exists; positive recipe-to-stock reconciliation needed. |
| QC, temperature, shelf life and spoilage | NOT EVIDENCED | Food safety checks and corrective actions not proven. |
| Made-to-order vs batch production separation | PARTIAL | Batch/consumption foundations exist; distinct planning/fulfillment paths need acceptance. |
| Theoretical vs actual usage / waste variance | GATE | No verified variance report reconciled against stock ledger. |

### 5. Menu, Recipe & Product Engineering — baseline 45%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Central product catalog and categories | PARTIAL | Product catalog exists; full category/variant/modifier lifecycle needs proof. |
| Per-branch availability | PARTIAL | Branch capacity/availability foundations exist; real branch parity unverified. |
| Central, regional and branch-specific pricing | NOT EVIDENCED | Pricing policy and effective date approval missing. |
| Recipe/BOM and ingredient mapping | PARTIAL | Recipe ingredients and version activation exist. |
| Nested BOM, unit conversions, yield and prep loss | NOT EVIDENCED | Nested sub-recipes and conversion engine not proven. |
| Recipe versions and effective dates | PARTIAL | Atomic activation exists; historical version immutability/effective-date tests missing. |
| Cost per serving and contribution margin | NOT EVIDENCED | Costing engine and reconciled margin outputs missing. |
| Allergens and regulated product information | NOT EVIDENCED | Structured allergen/product compliance flow missing. |
| Availability by schedule and stock | PARTIAL | Capacity/availability foundations exist; stock-aware availability not proven. |
| Recipe change request → costing → approval → rollout | PARTIAL | Version activation exists; full approval/simulation/branch verification missing. |
| POS/production uses the same approved recipe version | GATE | Cross-module version parity needs E2E proof. |

### 6. Inventory & Warehouse — baseline 55%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Inventory item and branch stock | PARTIAL | Inventory items and branch inventory exist. |
| Stock movement ledger | PARTIAL | Stock movement table and atomic receiving/production flows exist; all movement sources need reconciliation. |
| Warehouse/storage/bin hierarchy | NOT EVIDENCED | Multi-warehouse and storage-location hierarchy not proven. |
| Purchase/use units and conversions | PARTIAL | Item/recipe quantity structures exist; conversion and rounding policy incomplete. |
| FIFO/FEFO, lot/batch and expiry | NOT EVIDENCED | Lot traceability and expiry allocation missing. |
| Available/reserved/in-transit/blocked balances | PARTIAL | Transfer lifecycle exists; full stock-bucket accounting not proven. |
| Min/max, safety stock and reorder point | NOT EVIDENCED | Reorder rules and purchase recommendations missing. |
| Transfer lifecycle draft → approve → pick → ship → receive → reconcile | PARTIAL | Transfer states and ledger hooks exist; positive quantity/idempotency/cross-branch E2E required. |
| Stock count/cycle count and variance adjustment | PARTIAL | Count/posting foundations exist; full positive reconciliation and approval limits required. |
| Stock valuation | NOT EVIDENCED | Valuation method and historical valuation reports not proven. |
| Adjustments with reasons/approvals/audit | PARTIAL | Restricted workflow/audit foundations exist; risk thresholds and full review trail missing. |
| PO receipt → stock ledger → balance reconciliation | PARTIAL / GATE | Receipt-reconciliation endpoint exists; positive procurement workflow has not been run. |

### 7. Procurement & Supplier — baseline 40% (requisition slice implemented; E2E pending)
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Supplier directory | PARTIAL | Supplier master exists. |
| Supplier price lists, contracts and price history | NOT EVIDENCED | No verified contract/effective price lifecycle. |
| Purchase requisition from branch/warehouse/central kitchen | PARTIAL | PR #36 adds branch-scoped multi-line requisitions, draft/submit/Owner approve-or-reject/convert-to-PO, service-role-only atomic RPCs, audit trail, and ERP UI. Positive runtime E2E has not yet run; warehouse/central-kitchen consolidation remains missing. |
| Consolidated demand across branches | NOT EVIDENCED | Multi-branch buying/consolidation missing. |
| Purchase order draft, submit, approval, ordered | PARTIAL | PO state transitions exist; positive-path test still needed. |
| Approval limits by value/category | PARTIAL | Approval actions exist; configurable thresholds/delegation not proven. |
| Goods received note and quantity/quality inspection | PARTIAL | Atomic receiving RPC and GRN structures exist; live positive E2E pending. |
| Three-way match: PO, receipt, supplier invoice | NOT EVIDENCED | Invoice matching and tolerance/exception handling missing. |
| AP handoff and supplier payment | NOT EVIDENCED | Procurement-to-AP-to-payment reconciliation missing. |
| Supplier return and supplier performance | NOT EVIDENCED | Return and scorecard workflows missing. |

### 8. Branch Operations — baseline 50%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Branch directory, status, timezone and assignments | PARTIAL | Branch master, timezone and job assignments exist; 150 branch data readiness is not established. |
| Opening and closing checklists | PARTIAL | Checklist runs, item status and critical-item completion gates exist. |
| Opening readiness changes branch operating status | GATE | Real branch lifecycle integration not proven. |
| Daily tasks, due dates and escalation | NOT EVIDENCED | Task assignment/scheduling/notification workflow missing. |
| SOP and work instructions | PARTIAL | Operating model/docs exist; in-app versioned SOP delivery not proven. |
| Cleanliness, equipment and safety checks | PARTIAL | Checklist foundations exist; calibrated evidence and full templates missing. |
| Photo evidence | NOT EVIDENCED | Evidence upload/storage/retention workflow missing. |
| Incidents and corrective actions | NOT EVIDENCED | Incident severity, assignment, escalation and closure missing. |
| Equipment maintenance | NOT EVIDENCED | Work orders, preventive maintenance and downtime records missing. |
| Branch audit and compliance score | NOT EVIDENCED | Audit scoring and executive roll-up missing. |

### 9. Delivery & Fulfillment — baseline 20%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Pickup/delivery selection and fulfillment queue | PARTIAL | Order type and fulfillment state foundations exist. |
| Address validation and delivery quote | NOT EVIDENCED | Live quote provider and validation missing. |
| Courier booking / Biteship integration | NOT EVIDENCED | No provider credentials, contract tests or live integration evidence. |
| Dispatch and shipment tracking | NOT EVIDENCED | Courier lifecycle and tracking callbacks missing. |
| Proof of delivery | NOT EVIDENCED | POD capture and access policy missing. |
| Cancel/retry/provider exception handling | NOT EVIDENCED | Idempotent retry, cancellation and compensation missing. |
| Customer fee, subsidy and actual courier cost separation | NOT EVIDENCED | Cost model and reconciliation report missing. |
| Delivery completion notification | PARTIAL | Notification foundation exists; provider event → customer status E2E missing. |

### 10. CRM, Loyalty & Marketing — baseline 10%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Unified customer profile across channels | PARTIAL | Customer/order identity fields and history foundations exist; deduplication not proven. |
| Consent and communication preferences | NOT EVIDENCED | Consent lifecycle, withdrawal and audit missing. |
| Customer segments | NOT EVIDENCED | Segment rules and refresh jobs missing. |
| Loyalty points and tiers | NOT EVIDENCED | Ledger, expiry, reversal and duplicate-event protection missing. |
| Rewards and vouchers/coupons | NOT EVIDENCED | Issuance, eligibility, redemption and reversal missing. |
| Referral program | NOT EVIDENCED | Attribution and fraud controls missing. |
| Campaign management and ROI | NOT EVIDENCED | Campaign lifecycle and attribution metrics missing. |
| Feedback/reviews/support cases | NOT EVIDENCED | Ticketing, SLA and escalation missing. |
| Repeat purchase and customer lifetime analysis | NOT EVIDENCED | Canonical customer identity and verified BI metrics missing. |

### 11. Finance & Accounting — baseline 35%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Finance overview, expenses and approvals | PARTIAL | Branch expense approval foundations exist. |
| Cash/bank, settlement creation and matching | PARTIAL | Settlement and cash reconciliation structures/RPCs exist; source-to-bank positive E2E pending. |
| Payment provider fee and settlement variance | GATE | Full fee/variance reconciliation not proven. |
| AR/AP subledgers and aging | NOT EVIDENCED | Complete AR/AP workflows and control-account tie-out missing. |
| Chart of accounts and general ledger | PARTIAL | Journal-entry table exists; full COA/posted balanced journal lifecycle not proven. |
| Automated journals from POS/procurement/payroll | NOT EVIDENCED | Source mapping and balanced journal posting missing. |
| Bank reconciliation | PARTIAL | Cash/bank reconciliation foundations exist; statement import and independent matching not proven. |
| Tax and invoicing | PARTIAL | Tax settings exist; tax calculations, invoice numbering and compliance tests missing. |
| Budgets and branch P&L | NOT EVIDENCED | Budget-vs-actual and branch P&L not reconciled. |
| Consolidated financial statements | NOT EVIDENCED | Group consolidation missing. |
| Period close/reopen and backdated-posting controls | PARTIAL | Fiscal period guards exist; close/reopen and full GL acceptance missing. |
| Revenue vs cash received/settlement distinction | PARTIAL | Payment/settlement concepts exist; end-to-end reconciliation is incomplete. |

### 12. HR & Workforce — baseline 15%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Employee directory and lifecycle | NOT EVIDENCED | Employee hire/change/termination lifecycle missing. |
| Organization hierarchy and job positions | PARTIAL | Job positions and branch assignments exist. |
| Attendance and timesheets | NOT EVIDENCED | Clock-in/out, approvals and exception handling missing. |
| Shift scheduling and replacement | NOT EVIDENCED | Demand-based scheduling and shift swaps missing. |
| Leave and overtime | NOT EVIDENCED | Approval and policy engine missing. |
| Payroll calculation/integration | NOT EVIDENCED | Provider integration and payroll reconciliation missing. |
| Labor cost by branch | NOT EVIDENCED | Approved payroll-to-branch allocation missing. |
| Training/certification and performance reviews | NOT EVIDENCED | Course, certificate expiry and review workflow missing. |
| Recruitment/onboarding/offboarding | NOT EVIDENCED | Onboarding checklist and access revocation missing. |

### 13. Franchise & Expansion — baseline 5%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Branch ownership model | PARTIAL | Branch master foundation exists; ownership policies not proven end-to-end. |
| Franchise directory/application | NOT EVIDENCED | Application and due diligence workflow missing. |
| Site selection and feasibility | NOT EVIDENCED | Site scorecard, financial forecast and approval missing. |
| Opening project and readiness | PARTIAL | Branch setup/checklist foundations exist; full project workflow missing. |
| Agreements and contract expiry | NOT EVIDENCED | Document/version/renewal controls missing. |
| Royalty calculation and reconciliation | NOT EVIDENCED | Contract-driven royalty ledger and settlement missing. |
| Territory and franchise-specific access | NOT EVIDENCED | Geographic scope and tenant/franchise isolation missing. |
| Franchise compliance and performance | NOT EVIDENCED | Audit, corrective action and partner reporting missing. |

### 14. BI & Analytics — baseline 20%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Basic overview, funnel metrics and reports | PARTIAL | Basic overview/funnel metrics exist. |
| Official KPI dictionary and versioning | NOT EVIDENCED | Formula, source, timezone, refresh SLA and owner missing. |
| Net sales/AOV/gross margin | PARTIAL | Source data exists; canonical totals and reconciliation tests missing. |
| Food cost %, labor cost %, waste % | NOT EVIDENCED | Actual vs theoretical cost data and formula definitions missing. |
| Stock variance and fulfillment/cancellation rates | PARTIAL | Source entities exist; canonical metric outputs not proven. |
| Branch benchmarking by comparable cohorts | NOT EVIDENCED | Format/region/hours cohort definitions missing. |
| Demand forecasting and accuracy monitoring | NOT EVIDENCED | Forecast pipeline, evaluation and override audit missing. |
| Data quality monitoring and anomaly detection | NOT EVIDENCED | Freshness/completeness checks and alert lifecycle missing. |
| Export and scheduled executive reports | NOT EVIDENCED | Controlled exports and schedules missing. |
| Alert → action → measured outcome | NOT EVIDENCED | Closed-loop workflow missing. |

### 15. Admin, Identity & Access Control — baseline 55%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| User/admin profiles, role and permission actions | PARTIAL | Admin profile and action-level permission foundations exist. |
| Branch assignments and scope enforcement | PARTIAL | Server-side branch checks exist; full matrix testing is ongoing. |
| Owner/manager/no-permission/inactive identity probes | PASS (negative/role suite) | Existing suite reports 21 PASS / 0 FAIL; this is not full business E2E. |
| Audit logs for sensitive actions | PARTIAL | Audit log table and events exist; coverage of all sensitive mutations not proven. |
| Delegated approval policies and separation of duties | PARTIAL | Some approval gates exist; configurable policy matrix missing. |
| Sessions/devices and access reviews | NOT EVIDENCED | Session inventory, revocation and periodic review missing. |
| Recovery and offboarding | NOT EVIDENCED | Safe account recovery and immediate access revocation not proven. |
| API/database deny-by-default and direct-table protection | PARTIAL | All 45 public tables have RLS; most internal tables have no direct anon/authenticated SELECT. Public catalog access is intentionally exposed and still requires policy review. |
| Cross-tenant isolation | NOT EVIDENCED | Current single-organization model does not prove SaaS tenant isolation. |
| Permission changes themselves audited | GATE | Full audit and access review acceptance missing. |

### 16. SaaS Tenant Management — baseline 5%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Tenant directory, tenant onboarding | NOT EVIDENCED | No demonstrated multi-tenant onboarding lifecycle. |
| Tenant/member isolation in database and APIs | NOT EVIDENCED | No proven tenant entity/scope across tables, functions, storage, caches and jobs. |
| Plans, subscriptions, entitlements and quotas | NOT EVIDENCED | Server-enforced entitlements and usage limits missing. |
| Billing, invoices and usage metering | NOT EVIDENCED | Subscription billing and idempotent usage ledger missing. |
| Tenant settings and suspension | NOT EVIDENCED | Lifecycle and grace/suspension behavior missing. |
| Support access with approval/audit | NOT EVIDENCED | Just-in-time scoped support access missing. |
| Export/offboarding and data deletion policy | NOT EVIDENCED | Audited export, retention and deletion workflow missing. |
| Multiple companies sharing one platform safely | NOT EVIDENCED | One D’Lice org with branch slots is not proof of multi-tenant SaaS. |

### 17. Integrations & Automation — baseline 20%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| Edge Function API and payment proof flow | PARTIAL | Shared \`dlice-orders\` endpoint and payment proof/status paths exist. |
| Payment provider callback signature and status validation | NOT EVIDENCED | No verified live provider webhook evidence. |
| Delivery/e-commerce/WhatsApp/accounting connectors | NOT EVIDENCED | Provider-specific integrations not proven. |
| Webhooks and event log | PARTIAL | Notification logs/retry actions exist; durable event delivery contract missing. |
| Idempotency and replay protection | PARTIAL | Some atomic/idempotent operations exist; complete per-action coverage not proven. |
| Retry/backoff/dead-letter queue | PARTIAL | Notification retry foundation exists; durable retry/dead-letter behavior missing. |
| Integration health and alerting | NOT EVIDENCED | Health dashboards, lag/error alerts and recovery runbooks missing. |
| Secret storage/rotation | PARTIAL | Secret-based CORS config is active; integration credential rotation/least privilege not audited end-to-end. |
| Import/export and catalog synchronization | NOT EVIDENCED | Validated imports, conflict resolution and scheduled sync missing. |

### 18. Quality, Compliance & Security — baseline 35%
| PRD feature | Current status | Evidence / acceptance still needed |
|---|---|---|
| RLS on exposed public tables | PASS (database configuration) | Read-only SQL found 45/45 public tables with RLS enabled; policy correctness still needs per-table tests. |
| Direct access to internal stock/procurement/audit data | PARTIAL | No direct anon/authenticated SELECT grants on key internal tables; endpoint-level scope tests still required. |
| Exact-origin CORS | PASS (runtime) | GitHub Actions run 39979764381: registered staging origin HTTP 200 with exact ACAO; foreign origin HTTP 403/no ACAO; no Origin HTTP 200/no ACAO. |
| Custom auth/permission checks on shared endpoint | PARTIAL | \`verify_jwt=false\` remains; custom action authentication is present, so every action must remain covered by regression tests. |
| Leaked-password protection | GATE / WARN | Supabase Security Advisor reports it disabled; enabling requires an explicit platform configuration decision. |
| Food safety, temperature, allergens, recall | NOT EVIDENCED | Operational compliance records and recall traceability missing. |
| Supplier quality, quarantine, corrective actions | NOT EVIDENCED | Inspection, quarantine and CAPA lifecycle missing. |
| Backup and restore drill / RPO / RTO | NOT EVIDENCED | No restore rehearsal evidence found. |
| Monitoring, system health and incident runbooks | PARTIAL | Rate limits and logs exist; production-grade alert/runbook acceptance missing. |
| Load/concurrency test for 150 branches | NOT EVIDENCED | No approved realistic workload test or latency/error SLO evidence. |
| Pilot, rollout and rollback | NOT EVIDENCED | No signed-off pilot operating-day reconciliation or tested rollback evidence. |

## Cross-domain workflows
| Workflow | Current state | Exit criteria |
|---|---|---|
| Order-to-Cash | PARTIAL / E2E GATE | Create order → verify payment → route → kitchen/fulfillment → stock consumption exactly once → settlement/cash match → customer/BI update. Reconcile source and totals. |
| Procure-to-Pay | PARTIAL / E2E GATE | PR → consolidation → approval → PO → GRN → stock movement/balance → invoice 3-way match → AP → supplier payment. Positive E2E and artifact are still required. |
| Forecast-to-Production | PARTIAL | Forecast → recipe requirements → available/expiry-valid stock → PR/transfer → batch/prep → actual consumption/waste → stock and cost reconciliation. Forecasting itself is not proven. |
| Record-to-Report | PARTIAL | POS/procurement/payroll/expenses → source mapping → balanced journal → settlement/stock/AP reconciliation → period close → branch P&L → group consolidation. |
| Stock transfer and count | PARTIAL | All states, correct source/destination quantities, one ledger event per transition, retries safe, variance approved, branch scope verified. |
| Authentication and permissions | PARTIAL | Positive and negative role tests per action, anonymous 401, unauthorized 403, cross-branch/tenant deny, inactive-user deny, audit event, browser path. |
| Responsive UX and accessibility | UNVERIFIED | Accepted screenshots and interactions on mobile/tablet/desktop; keyboard/focus, reduced motion, contrast, labels, validation and screen-reader checks. |
| Backup, recovery, scale and rollout | NOT DEMONSTRATED | Restore drill, measured RPO/RTO, concurrency test, branch pilot and rollback rehearsal. |

## Data architecture / platform readiness
| Requirement | Current status |
|---|---|
| Central product, order, payment, stock, procurement and finance foundations | PARTIAL — multiple tables and RPCs exist; complete source-to-ledger reconciliation missing. |
| 150 real operational branches | NOT READY — 150 numbered slots are planning placeholders; branch addresses, timezones, managers, schedules and controls must be configured. |
| SaaS tenant boundary | NOT EVIDENCED — one organization with many branches is not multi-tenant isolation. |
| Branch scope in APIs and RLS | PARTIAL — explicit server-side branch authorization and RLS exist; broader adversarial acceptance remains. |
| Immutable/traceable stock and financial records | PARTIAL — stock movements, audit logs, refund records and settlement entities exist; full ledger/GL acceptance missing. |
| Unique business identifiers and idempotency | PARTIAL — transaction code and atomic RPC foundations exist; concurrency/replay acceptance missing. |
| Local business date and WIB/WITA/WIT cutoffs | PARTIAL — timezone contract tests exist; complete branch-day reconciliation still needed. |
| Responsive mobile/tablet/desktop workspaces | UNVERIFIED — code has responsive styling intent; protected-preview screenshot audit and real interaction tests are still required. |

## Superpowers implementation plan (mandatory for each slice)
1. **Specify:** convert the row(s) selected for the slice into acceptance criteria, permissions/scopes, audit event, error behavior and reconciliation equations.
2. **Plan:** choose one vertical slice with dependencies and rollback plan; staging-only.
3. **Tests first:** add failing contract/unit tests and positive + negative staging E2E harness before implementation.
4. **Implement:** schema/migration, server authorization, atomic RPC, UI, audit and idempotency in the same slice.
5. **Verify:** run quality checks, positive/negative role tests, source-to-ledger reconciliation, Supabase advisors, and responsive smoke.
6. **Review:** PR evidence must identify commit, CI run, runtime deployment version and artifacts. No green static test may be relabeled as E2E.
7. **Deploy staging:** migrate/deploy only staging; compare source and live function; run live acceptance.
8. **Accept:** mark only the tested slice accepted, update this register, then move to the next dependency.

## Recommended execution sequence
- **P0 close-out:** CORS runtime is now PASS; review leaked-password protection warning, auth-per-action regression coverage, migration/runtime parity and cross-branch/anonymous probes.
- **P1 core operating loop:** finish positive procure-to-pay E2E; then order-to-cash, recipe-to-production consumption, stock transfer/count, shift/cash close. Do not start many modules in parallel.
- **P2 controls and accounting:** finish balanced journal/GL, AP/AR, settlement/bank reconciliation, period close, branch P&L, SOP/incident controls.
- **P3 automation and customer intelligence:** delivery integrations, CRM/consent/loyalty, canonical KPI dictionary, forecasting and anomaly/alert lifecycle.
- **P4 people, franchise and SaaS:** workforce/payroll, franchise workflows, tenant isolation/onboarding/entitlements/billing.
- **Scale gate:** load/concurrency, restore drill, observability/runbooks, real pilot branch and rollback evidence.

## Current release caveats
- \`dlice-orders\` is ACTIVE at staging version 51 with \`verify_jwt=false\`; keep per-action custom authentication and authorization regression coverage mandatory.
- Supabase Security Advisor reports leaked-password protection disabled.
- Performance Advisor reports 69 unused-index findings. Do not bulk-drop indexes; assess with workload and query plans.
- PR #35 is merged to staging and the receipt reconciliation action is present in the deployed function, but the positive procurement E2E has not yet been evidenced by a workflow run.
- Vercel Preview is READY; the project enables SSO protection for non-custom domains. The fetched HTML response is not a substitute for screenshot-based visual acceptance.
- Figma account metadata reports Starter/View seat, with Code Layers disabled. Product Design screenshot audit must be run from a supported Work/browser session with authorized access; do not mark design QA passed without current screenshots.
- Production \`main\`, production Supabase and production deployment remain untouched.


## Latest staging implementation snapshot — 2026-10-23 16:06 UTC

- PR #36 merged to `staging` at `c1c61e2706397576e560d0274d84034959de118f`. It adds the Purchase Requisition workflow; the Owner-only reconciliation action is also deployed in Supabase Edge Function `dlice-orders` v53.
- Remote migration history records `purchase_requisitions` as version `20261023160257` and `purchase_requisition_conversion_index` as version `20261023160440`. Source migration filenames now match those remote versions.
- Public base tables increased from 45 to 47; both new requisition tables have RLS enabled, and read-only privilege checks confirm `anon` and `authenticated` cannot SELECT either table directly.
- Contract CI run [39983296168](https://github.com/dlice8888/dlice-landing-page/actions/runs/39983296168) passed; the latest run after self-approval guard also passed the contract and free quality checks. This is static/contract evidence, not live requisition E2E.
- The positive procurement workflow has been extended to exercise branch-manager requisition creation/submission, non-Owner approval denial, Owner approval, PO conversion, PO ordering, GRN, stock movement and audit reconciliation. It requires Owner and Branch A manager disposable credentials in the protected GitHub `staging` environment and is deliberately manual because it writes retained QA records. It has not yet been dispatched.
- Supabase Security Advisor still warns that leaked-password protection is disabled. Performance Advisor no longer reports an unindexed FK for the converted PO reference after the targeted index migration; 74 unused-index suggestions remain and were not bulk-dropped.
- Runtime CORS run [39984466037](https://github.com/dlice8888/dlice-landing-page/actions/runs/39984466037) passed against deployed function v53: registered staging origin HTTP 200 with exact ACAO; foreign origin HTTP 403 without ACAO; missing Origin HTTP 200 without ACAO.
- Vercel and Figma screenshot-based UX acceptance remain unverified. No production deployment, `main` changes, or real business data were part of this slice.


## Latest verification addendum — 2026-10-23 16:10 UTC

- Staging Edge Function `dlice-orders` v53 is ACTIVE, `verify_jwt=false` remains preserved, source hash `f3eb25d25c4ea04c5839eb516686e9002e34d616d623b389ca9908139f182f9a`. Read-back confirms secret-only CORS, no hard-coded origin fallback, and the Owner-only requisition reconciliation action.
- CORS runtime run [39984466037](https://github.com/dlice8888/dlice-landing-page/actions/runs/39984466037) completed PASS for all three required scenarios on v53.
- Contract run [39984465957](https://github.com/dlice8888/dlice-landing-page/actions/runs/39984465957) and quality run [39984465988](https://github.com/dlice8888/dlice-landing-page/actions/runs/39984465988) passed. Test PR #39 was merged at `17571890d29e2fe9f4410cb57f53de073427b9f5`.
- The manual positive P2P workflow now covers branch-manager PR creation/submission, non-Owner approval denial, Owner approval, PO conversion, lifecycle audit reconciliation, PO ordering, GRN, stock movement, and balance delta. **The manual E2E has not been dispatched**, so requisition-to-stock remains PARTIAL/GATE.
- Current public base tables: 47; RLS enabled: 47; RLS disabled: 0. New requisition tables have no direct SELECT grant to `anon` or `authenticated`.
- Migration filenames now align with remote migration versions `20261023160257` and `20261023160440`. Targeted index `purchase_requisitions_converted_po_idx` is present.
- Security Advisor still warns leaked-password protection is disabled. Performance Advisor reports 74 unused-index suggestions; no unused indexes were dropped.
- Production/main remain unchanged. UI visual acceptance remains blocked by Vercel SSO protection in this chat context and requires an authenticated browser session.
