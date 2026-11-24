# D’Lice FnB OS — Audit refresh 189 fitur
Tanggal: 24 November 2026
Repository: `dlice8888/dlice-landing-page`
Audit target: branch `staging` @ `cc880ef648ee89248462c75b4fde50842689a131`
PRD source: `docs/FNB_OS_PRD_FEATURE_REGISTER_2026-10-23.md`
Feature matrix source snapshot: `2026-11-24 00:00 WIB`

## Ringkasan status fitur

| Domain | Total | Partial | Belum terbukti | Blocked | DONE | Cakupan Partial |
|---|---:|---:|---:|---:|---:|---:|
| Executive Command Center | 10 | 4 | 5 | 1 | 0 | 40.0% |
| POS & Checkout | 13 | 7 | 5 | 1 | 0 | 53.8% |
| Order Management | 10 | 8 | 2 | 0 | 0 | 80.0% |
| Kitchen & Production | 10 | 7 | 2 | 1 | 0 | 70.0% |
| Menu, Recipe & Product Engineering | 11 | 7 | 3 | 1 | 0 | 63.6% |
| Inventory & Warehouse | 12 | 10 | 2 | 0 | 0 | 83.3% |
| Procurement & Supplier | 10 | 5 | 5 | 0 | 0 | 50.0% |
| Branch Operations | 10 | 4 | 5 | 1 | 0 | 40.0% |
| Delivery & Fulfillment | 8 | 2 | 6 | 0 | 0 | 25.0% |
| CRM, Loyalty & Marketing | 9 | 1 | 8 | 0 | 0 | 11.1% |
| Finance & Accounting | 12 | 7 | 4 | 1 | 0 | 58.3% |
| HR & Workforce | 9 | 1 | 8 | 0 | 0 | 11.1% |
| Franchise & Expansion | 8 | 2 | 6 | 0 | 0 | 25.0% |
| BI & Analytics | 10 | 3 | 7 | 0 | 0 | 30.0% |
| Admin, Identity & Access Control | 10 | 8 | 2 | 0 | 0 | 80.0% |
| SaaS Tenant Management | 8 | 2 | 6 | 0 | 0 | 25.0% |
| Integrations & Automation | 9 | 5 | 4 | 0 | 0 | 55.6% |
| Quality, Compliance & Security | 20 | 12 | 8 | 0 | 0 | 60.0% |
| **TOTAL** | **189** | **95** | **88** | **6** | **0** | **50.3%** |

- Total: **189 fitur / 18 domain**.
- Status terbaru pada register: **95 PARTIAL + 88 NOT VERIFIED + 6 BLOCKED + 0 DONE**.
- Cakupan Partial: **95/189 = 50.3%**. Ini ukuran fitur yang sudah memiliki fondasi implementasi, bukan rata-rata penyelesaian fitur Partial.
- Progress berbobot: **2 fitur memiliki skor sementara (30% dan 58%); 93 fitur Partial belum memiliki breakdown skor yang dapat diaudit**. Jangan mengisi persentase berdasarkan tebakan.
- Belum ada domain yang memenuhi DONE 100% dengan UI/API/database/authorization/E2E dan rekonsiliasi operasional.
- Release flags tetap `TENANT_ISOLATION_RELEASED=false` dan `PUBLIC_TENANT_ROUTING_RELEASED=false`.

## Progress terukur pada fitur Partial

1. **Tenant directory / tenant onboarding — 30% provisional.** Sudah ada atomic tenant creation + owner membership + audit RPC dan database test; belum ada onboarding browser/API E2E, invitation acceptance, default branch, billing, atau offboarding reconciliation.
2. **Tenant/member isolation in database and APIs — 58% provisional.** 64/64 tabel public RLS-enabled, 35 pgTAP assertions pada 17 tabel sensitif, direct RLS/RPC probes dan live P01–P09; masih kurang coverage seluruh route, Storage, cache, jobs, multi-branch concurrency, browser E2E, dan 150-branch operational reconciliation.
3. **93 Partial lainnya — belum dinilai.** Pecah tiap acceptance criteria ke enam dimensi: code/UI, database, authorization, automated tests, browser/API E2E, operational reconciliation. Skor hanya setelah bukti per dimensi tersedia.

## Bukti platform pada audit ini

### GitHub
- Staging head: `cc880ef648ee89248462c75b4fde50842689a131`.
- [P01–P09 acceptance run](https://github.com/dlice8888/dlice-landing-page/actions/runs/45383998161): PASS 9, FAILED 0, BLOCKED 0, SKIPPED 0 pada staging head tersebut.
- [PR #138](https://github.com/dlice8888/dlice-landing-page/pull/138): migration replay sebelumnya PASS, tetapi boundary regression dan static checks gagal pada head sebelumnya. Perbaikan pada branch `audit/stock-transfer-tenant-boundary-20261124` menambahkan tenant equality check pada jalur create dan release note; static checks, contract, boundary regression, CORS dan KDS contract telah PASS pada head `529545b1805c0149e6b087a79a7e3e431c35a374`; disposable migration replay kemudian selesai PASS pada run `45385436068`; 234 database contract tests lulus. PR #138 masih open dan belum diterapkan ke shared staging.
- [PR #139](https://github.com/dlice8888/dlice-landing-page/pull/139): static checks, KDS offline contract, dan disposable migration replay PASS pada head `b367c785c3041c4742bc36e439251fa47c8149c5`; belum merge dan belum diterapkan ke Supabase staging.
- PR #138 dan #139 tetap source-only; tidak boleh diperlakukan sebagai perubahan staging sebelum integrasi resmi.

### Supabase staging
- Project `higoadrzxnhzbbwhdbmh`: ACTIVE_HEALTHY, PostgreSQL 17.
- 64 public base tables; 64/64 RLS-enabled; 64 public policies.
- Applied migrations: 49; latest `20261119182606`.
- Staging source tree: 58 migration files; 9 source-only versions belum tercatat di DB: `20261120100000`, `20261120110000`, `20261120120000`, `20261121100000`, `20261121120000`, `20261121130000`, `20261121153000`, `20261121160000`, `20261121170000`. Applied versions missing from source: 0; duplicate source versions: 0.
- Trigger `trg_stock_transfer_same_tenant` belum ada pada shared staging. PR #138 migration belum diaplikasikan. Jangan apply langsung sebelum exact-head replay, review, P01–P09, backup/rollback dan persetujuan staging.
- Security Advisor: leaked-password protection WARN.
- Performance Advisor: 26 unindexed foreign keys dan 49 unused-index suggestions. Unused-index suggestions perlu workload/query-plan review; jangan hapus massal.

### Vercel
- Project `dlice-landing-page` ditemukan.
- Preview deployment terbaru dari PR #139 READY. READY hanya membuktikan deployment build berhasil; bukan penerimaan workflow bisnis atau production release.
- Tidak ada deployment production yang dilakukan oleh audit ini.

## Daftar 88 fitur NOT VERIFIED

- **Branch ranking, region/format comparison** — No verified 150-branch ranking/cohort output.
- **Critical stock, expiry, waste alerts** — Lot/expiry/waste alert workflow not proven.
- **Sales-drop / food-cost anomaly detection** — No verified anomaly rule, assignment, acknowledgement, or closure.
- **Target vs actual and executive reports** — Official targets, scheduled reports, and exports not proven.
- **Alert → assign task → resolve → audit result** — Assignment and action-outcome workflow not proven.
- **Variants, toppings, special instructions** — Complete modifier-group flow not proven.
- **Discounts, coupons, vouchers, special pricing** — Rule engine, approvals, and audit evidence missing.
- **Split bill, partial payment, final settlement** — Partial/split tender lifecycle not proven.
- **Hold/resume order** — No verified workflow found.
- **Offline sales queue and safe resynchronization** — Offline persistence, deduplication and replay recovery not proven.
- **WhatsApp, marketplace, additional channels** — Provider integrations and contract tests missing.
- **Preparation ETA and exception escalation** — SLA prediction and escalation workflow missing.
- **Station routing (hot/cold/beverage/packing)** — No verified station configuration and routing.
- **QC, temperature, shelf life and spoilage** — Food safety checks and corrective actions not proven.
- **Nested BOM, unit conversions, yield and prep loss** — Nested sub-recipes and conversion engine not proven.
- **Cost per serving and contribution margin** — Costing engine and reconciled margin outputs missing.
- **Allergens and regulated product information** — Structured allergen/product compliance flow missing.
- **FIFO/FEFO, lot/batch and expiry** — Lot traceability and expiry allocation missing.
- **Stock valuation** — Valuation method and historical valuation reports not proven.
- **Supplier price lists, contracts and price history** — No verified contract/effective price lifecycle.
- **Consolidated demand across branches** — Multi-branch buying/consolidation missing.
- **Three-way match: PO, receipt, supplier invoice** — Invoice matching and tolerance/exception handling missing.
- **AP handoff and supplier payment** — Procurement-to-AP-to-payment reconciliation missing.
- **Supplier return and supplier performance** — Return and scorecard workflows missing.
- **Daily tasks, due dates and escalation** — Task assignment/scheduling/notification workflow missing.
- **Photo evidence** — Evidence upload/storage/retention workflow missing.
- **Incidents and corrective actions** — Incident severity, assignment, escalation and closure missing.
- **Equipment maintenance** — Work orders, preventive maintenance and downtime records missing.
- **Branch audit and compliance score** — Audit scoring and executive roll-up missing.
- **Address validation and delivery quote** — Live quote provider and validation missing.
- **Courier booking / Biteship integration** — No provider credentials, contract tests or live integration evidence.
- **Dispatch and shipment tracking** — Courier lifecycle and tracking callbacks missing.
- **Proof of delivery** — POD capture and access policy missing.
- **Cancel/retry/provider exception handling** — Idempotent retry, cancellation and compensation missing.
- **Customer fee, subsidy and actual courier cost separation** — Cost model and reconciliation report missing.
- **Consent and communication preferences** — Consent lifecycle, withdrawal and audit missing.
- **Customer segments** — Segment rules and refresh jobs missing.
- **Loyalty points and tiers** — Ledger, expiry, reversal and duplicate-event protection missing.
- **Rewards and vouchers/coupons** — Issuance, eligibility, redemption and reversal missing.
- **Referral program** — Attribution and fraud controls missing.
- **Campaign management and ROI** — Campaign lifecycle and attribution metrics missing.
- **Feedback/reviews/support cases** — Ticketing, SLA and escalation missing.
- **Repeat purchase and customer lifetime analysis** — Canonical customer identity and verified BI metrics missing.
- **AR/AP subledgers and aging** — Complete AR/AP workflows and control-account tie-out missing.
- **Automated journals from POS/procurement/payroll** — Source mapping and balanced journal posting missing.
- **Budgets and branch P&L** — Budget-vs-actual and branch P&L not reconciled.
- **Consolidated financial statements** — Group consolidation missing.
- **Employee directory and lifecycle** — Employee hire/change/termination lifecycle missing.
- **Attendance and timesheets** — Clock-in/out, approvals and exception handling missing.
- **Shift scheduling and replacement** — Demand-based scheduling and shift swaps missing.
- **Leave and overtime** — Approval and policy engine missing.
- **Payroll calculation/integration** — Provider integration and payroll reconciliation missing.
- **Labor cost by branch** — Approved payroll-to-branch allocation missing.
- **Training/certification and performance reviews** — Course, certificate expiry and review workflow missing.
- **Recruitment/onboarding/offboarding** — Onboarding checklist and access revocation missing.
- **Franchise directory/application** — Application and due diligence workflow missing.
- **Site selection and feasibility** — Site scorecard, financial forecast and approval missing.
- **Agreements and contract expiry** — Document/version/renewal controls missing.
- **Royalty calculation and reconciliation** — Contract-driven royalty ledger and settlement missing.
- **Territory and franchise-specific access** — Geographic scope and tenant/franchise isolation missing.
- **Franchise compliance and performance** — Audit, corrective action and partner reporting missing.
- **Official KPI dictionary and versioning** — Formula, source, timezone, refresh SLA and owner missing.
- **Food cost %, labor cost %, waste %** — Actual vs theoretical cost data and formula definitions missing.
- **Branch benchmarking by comparable cohorts** — Format/region/hours cohort definitions missing.
- **Demand forecasting and accuracy monitoring** — Forecast pipeline, evaluation and override audit missing.
- **Data quality monitoring and anomaly detection** — Freshness/completeness checks and alert lifecycle missing.
- **Export and scheduled executive reports** — Controlled exports and schedules missing.
- **Alert → action → measured outcome** — Closed-loop workflow missing.
- **Sessions/devices and access reviews** — Session inventory, revocation and periodic review missing.
- **Recovery and offboarding** — Safe account recovery and immediate access revocation not proven.
- **Plans, subscriptions, entitlements and quotas** — Server-enforced entitlements and usage limits missing.
- **Billing, invoices and usage metering** — Subscription billing and idempotent usage ledger missing.
- **Tenant settings and suspension** — Lifecycle and grace/suspension behavior missing.
- **Support access with approval/audit** — Just-in-time scoped support access missing.
- **Export/offboarding and data deletion policy** — Audited export, retention and deletion workflow missing.
- **Multiple companies sharing one platform safely** — One D’Lice org with branch slots is not proof of multi-tenant SaaS.
- **Payment provider callback signature and status validation** — No verified live provider webhook evidence.
- **Delivery/e-commerce/WhatsApp/accounting connectors** — Provider-specific integrations not proven.
- **Integration health and alerting** — Health dashboards, lag/error alerts and recovery runbooks missing.
- **Import/export and catalog synchronization** — Validated imports, conflict resolution and scheduled sync missing.
- **Food safety, temperature, allergens, recall** — Operational compliance records and recall traceability missing.
- **Supplier quality, quarantine, corrective actions** — Inspection, quarantine and CAPA lifecycle missing.
- **Backup and restore drill / RPO / RTO** — No restore rehearsal evidence found.
- **Load/concurrency test for 150 branches** — No approved realistic workload test or latency/error SLO evidence.
- **Pilot, rollout and rollback** — No signed-off pilot operating-day reconciliation or tested rollback evidence.
- **Workflow** — Exit criteria
- **Responsive UX and accessibility** — Accepted screenshots and interactions on mobile/tablet/desktop; keyboard/focus, reduced motion, contrast, labels, validation and screen-reader checks.
- **Backup, recovery, scale and rollout** — Restore drill, measured RPO/RTO, concurrency test, branch pilot and rollback rehearsal.

## Urutan prioritas remediation

### P0 — Security, tenant isolation, migration parity
1. Selesaikan PR #138: create/transition API tenant guard, DB trigger, branch reassignment race test, exact-head checks dan full disposable migration replay.
2. Selesaikan PR #139: JSON boolean `platform_owner`, current JWT role claim, service_role-only RPC grants, exact-head tests. Lakukan validasi Owner identity hanya melalui Supabase Auth Admin resmi.
3. Tutup Auth leaked-password protection WARN pada Supabase Auth configuration.
4. Rekonsiliasi 9 source-only migrations per file; bandingkan schema/functions/grants/RLS dan lakukan disposable replay. Jangan mass-apply ke shared staging.
5. Pertahankan dua release flags false sampai runtime, UI/API, database dan operational acceptance lulus.

### P1 — Transaction integrity and operational E2E
- POS checkout: modifier, discounts, split tender, hold/resume, receipts, offline replay.
- Order lifecycle: duplicate/delayed payment, expiry, compensation, payment proof, webhook replay and reconciliation.
- Kitchen: station routing, prep SLA, QC/temperature/shelf-life.
- Procurement: PR → approval → PO → receipt/inspection → stock ledger → AP matching.

### P2 — Core FnB operating workflows
- Menu/recipe: nested BOM, conversions, yields, allergens, costing/margin, effective-date approval.
- Inventory: FIFO/FEFO lots, expiry, stock valuation, safety stock, storage/bin hierarchy.
- Branch operations: tasks, evidence, incidents/CAPA, maintenance and audit scoring.
- Finance: AR/AP, journals, budgets/P&L, consolidation and period close.

### P3 — Scale-out business domains
- Delivery/provider lifecycle and proof of delivery.
- CRM consent, customer identity, loyalty ledger, rewards, referrals and campaigns.
- HR lifecycle, attendance, schedules, leave, payroll and labor allocation.
- Franchise application, site feasibility, contract, royalty and compliance.
- BI KPI dictionary, forecasting, cohort benchmarking, data quality and executive reporting.
- SaaS plans, entitlements, billing, support access, tenant lifecycle and data offboarding.
- Integration health, webhooks, retries, dead-letter and import/export.

## DONE acceptance gate
A feature becomes DONE only when all acceptance dimensions score 100%, its UI/API/database authorization paths pass positive and negative tests, exact-head CI and disposable migration replay pass, staging E2E is executed (no skipped/blocked), source transactions reconcile to downstream ledgers and audit trails, and release flags are changed only through an explicitly authorized release decision.
