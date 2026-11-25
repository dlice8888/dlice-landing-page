# D’Lice FnB OS — Total PRD Audit & Gap Register

**Tanggal audit:** 25 November 2026 (WIB)
**PRD:** docs/FNB_OS_PRD_FEATURE_REGISTER_2026-10-23.md
**Scope:** 189 fitur / 18 domain; GitHub, Supabase staging higoadrzxnhzbbwhdbmh, Vercel Preview.
**Working branch:** feat/eight-domain-workflow-kernel-20261125
**Feature matrix:** docs/audit/FNB_OS_IMPLEMENTATION_MATRIX.json

## 1. Tabel awal dari instruksi pengguna

| Domain | Total | Partial | Belum terbukti | Blocked | Selesai | Cakupan Partial |
|---|---:|---:|---:|---:|---:|---:|
| Executive Command Center | 10 | 4 | 5 | 1 | 0 | 40% |
| POS & Checkout | 13 | 7 | 5 | 1 | 0 | 54% |
| Order Management | 10 | 8 | 2 | 0 | 0 | 80% |
| Kitchen & Production | 10 | 7 | 2 | 1 | 0 | 70% |
| Menu & Recipe | 11 | 7 | 3 | 1 | 0 | 64% |
| Inventory & Warehouse | 12 | 10 | 2 | 0 | 0 | 83% |
| Procurement & Supplier | 10 | 5 | 5 | 0 | 0 | 50% |
| Branch Operations | 10 | 4 | 5 | 1 | 0 | 40% |
| Delivery & Fulfillment | 8 | 2 | 6 | 0 | 0 | 25% |
| CRM & Loyalty | 9 | 1 | 8 | 0 | 0 | 11% |
| Finance & Accounting | 12 | 7 | 4 | 1 | 0 | 58% |
| HR & Workforce | 9 | 1 | 8 | 0 | 0 | 11% |
| Franchise & Expansion | 8 | 2 | 6 | 0 | 0 | 25% |
| BI & Analytics | 10 | 3 | 7 | 0 | 0 | 30% |
| Admin & Access Control | 10 | 6 | 4 | 0 | 0 | 60% |
| SaaS Tenant Management | 8 | 2 | 6 | 0 | 0 | 25% |
| Integrations & Automation | 9 | 5 | 4 | 0 | 0 | 56% |
| Quality, Compliance & Security | 20 | 11 | 9 | 0 | 0 | 55% |
| **TOTAL** | **189** | **92** | **91** | **6** | **0** | **48.7%** |

## 2. Rekonsiliasi selisih baseline

PR #142 yang sudah merged dan feature-level matrix pada staging berisi 95 PARTIAL / 88 NOT VERIFIED / 6 BLOCKED. Tabel terbaru yang Anda kirim berisi 92 / 91 / 6. Selisih tepat tiga status ada pada Admin & Access Control (6 vs 8 PARTIAL) dan Quality, Compliance & Security (11 vs 12 PARTIAL). Instruksi terbaru tidak menyebut tiga identitas fitur yang berubah, sehingga saya tidak menebaknya. Tabel awal Anda tetap disimpan apa adanya; feature-level matrix menggunakan baris PRD yang dapat ditelusuri dan menyimpan perbedaan ini sebagai gap rekonsiliasi.

## 3. Tabel feature-level setelah pengerjaan audit ini

27 fitur yang sebelumnya NOT VERIFIED/BLOCKED memiliki pekerjaan implementasi konkret dan sekarang dipindahkan ke PARTIAL. Satu perpindahan berasal dari BLOCKED (digital receipt), 26 dari NOT VERIFIED. PARTIAL bukan DONE dan bukan berarti workflow diterima.

| Domain | Total | Partial | Belum terbukti | Blocked | Selesai | Cakupan Partial |
|---|---:|---:|---:|---:|---:|---:|
| Executive Command Center | 10 | 5 | 4 | 1 | 0 | 50.0% |
| POS & Checkout | 13 | 12 | 1 | 0 | 0 | 92.3% |
| Order Management | 10 | 8 | 2 | 0 | 0 | 80.0% |
| Kitchen & Production | 10 | 7 | 2 | 1 | 0 | 70.0% |
| Menu, Recipe & Product Engineering | 11 | 7 | 3 | 1 | 0 | 63.6% |
| Inventory & Warehouse | 12 | 10 | 2 | 0 | 0 | 83.3% |
| Procurement & Supplier | 10 | 6 | 4 | 0 | 0 | 60.0% |
| Branch Operations | 10 | 4 | 5 | 1 | 0 | 40.0% |
| Delivery & Fulfillment | 8 | 4 | 4 | 0 | 0 | 50.0% |
| CRM, Loyalty & Marketing | 9 | 5 | 4 | 0 | 0 | 55.6% |
| Finance & Accounting | 12 | 7 | 4 | 1 | 0 | 58.3% |
| HR & Workforce | 9 | 6 | 3 | 0 | 0 | 66.7% |
| Franchise & Expansion | 8 | 6 | 2 | 0 | 0 | 75.0% |
| BI & Analytics | 10 | 5 | 5 | 0 | 0 | 50.0% |
| Admin, Identity & Access Control | 10 | 8 | 2 | 0 | 0 | 80.0% |
| SaaS Tenant Management | 8 | 5 | 3 | 0 | 0 | 62.5% |
| Integrations & Automation | 9 | 5 | 4 | 0 | 0 | 55.6% |
| Quality, Compliance & Security | 20 | 12 | 8 | 0 | 0 | 60.0% |
| **TOTAL** | **189** | **122** | **62** | **5** | **0** | **64.6%** |

## 4. Bukti lintas platform

### GitHub
- Repo dlice8888/dlice-landing-page; default branch main.
- PR #144 masih OPEN, belum merge, dan base-nya main, bukan staging. Branch kerja memiliki 162 commit di depan staging; dibanding main branch diverged (654 ahead / 28 behind) dan PR menampilkan 243 file berubah. Ini blocker integrasi kritis; jangan merge sebelum target PR dan ancestry diselaraskan.
- Exact-head quality run 45622292238 FAILED. scripts/quality-checks.mjs menemukan syntax error di renderer Executive Alert pada erp.html: missing string concatenation sebelum penutup div. Diperbaiki pada commit 8198b5a1ee1f5c4576ebafcd0445549cc9b7d566. CI exact-head sesudah fix masih harus dibuktikan PASS.
- PR #143 masih OPEN di branch terpisah. Body PR menyebut staging POS E2E BLOCKED karena app_metadata.platform_owner pada Owner belum ada dan allowlist Edge harus memuat UUID yang sama. Percobaan berhenti sebelum mutasi transaksi QA. Hasil disposable replay yang dilaporkan PR bukan bukti staging positive-path E2E.
- Tidak ada PR yang di-merge dalam audit ini.

### Supabase staging
- Katalog read-only: 68/68 public base tables RLS enabled; 0 tabel tanpa RLS.
- Migration ledger: 63 versi applied; terbaru 20261124134222_pos_checkout_fk_supporting_indexes.
- Edge Function dlice-orders ACTIVE versi 73; verify_jwt=false. Otorisasi handler wajib tetap ada dan tidak boleh dilemahkan.
- Security Advisor: leaked-password protection disabled (WARN). Remediasi: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- Performance Advisor: 83 unused-index suggestions (INFO). Evaluasi workload/query plan sebelum penghapusan; jangan mass-delete.
- Health Advisor: tidak ada temuan.
- Query terbatas pada RPC tenant menunjukkan fungsi yang diperiksa SECURITY INVOKER dengan EXECUTE hanya untuk service_role. Ini bukan audit ACL menyeluruh untuk seluruh 189 fitur.
- Tidak ada write database, migrasi, perubahan Auth, atau deployment Edge.

### Vercel
- Project dlice-landing-page ditemukan.
- Preview terbaru yang terdata READY pada commit d55c14bb09c905bae840c48fef9096a4518f569b. HEAD branch lebih baru, jadi belum ada bukti Preview yang cocok dengan seluruh perubahan HEAD.
- READY hanya bukti status build deployment; bukan bukti workflow bisnis, browser acceptance, tenant isolation atau rekonsiliasi Finance.
- Tidak ada Production deployment/promotion.

## 5. Progress Partial dan standar skor

Bobot resmi: Code/UI 20%, Database/integrity 20%, Authorization/scope 15%, Automated tests 15%, Browser/API E2E 20%, Operational reconciliation/observability 10%.

- Tenant onboarding: 30% provisional (skor terdahulu; perlu verifikasi ulang).
- Tenant/member isolation: 58% provisional pada snapshot bukti sebelumnya; harus dihitung ulang terhadap katalog 68 tabel dan bukti exact-head terbaru.
- 27 fitur baru berstatus PARTIAL tetapi skor weighted belum diberikan. Artefak source/UI/SQL draft memulai pekerjaan, namun migration, tests, runtime dan rekonsiliasi belum membuktikan dimensi lainnya.
- Fitur Partial lainnya juga perlu dipecah ke enam dimensi. Jangan memberi angka tebakan. Matrix menandai skor yang belum punya evidence breakdown sebagai UNSCORED_EVIDENCE_BREAKDOWN_REQUIRED.
- Tidak ada fitur DONE.

## 6. Prioritas gap remediation

1. POS: perbaiki dan verifikasi PR #143 pada exact head; selesaikan cashier UI, receipt/browser acceptance, offline local queue dan fault injection; rekonsiliasi sale, tender, cash drawer, stock, KDS, receipt dan audit. Buka Owner Auth hanya melalui Auth Admin resmi dan cocokkan UUID dengan Edge allowlist; jangan bypass gate.
2. CRM: tetapkan eligible net sales dari Finance close, diskon/refund/void/chargeback, settlement dan shift reconciliation; buat earning idempotent dan reversal immutable. Pilih provider komunikasi yang benar-benar disetujui sebelum signed webhook, delivery receipt, retry, unsubscribe dan ROI.
3. HR: lengkapi monthly/fixed salary, overtime, allowance, benefit, tax, deduction, net pay dan payment. Hubungkan outbox ke skema Finance aktual, buat balanced journal posting, source references dan rekonsiliasi per branch/periode. Outbox bukan jurnal posted.
4. Delivery: verifikasi provider quote/booking dan signature contract; signed webhook idempotency, tracking, retries/compensation, customer notification, COD dan ongkir/subsidi/actual cost reconciliation. Jangan mengasumsikan Biteship; provisioning private POD bucket/policy harus diverifikasi.
5. Franchise: territory/conflict rules, agreement versioning/e-signature, seluruh opening gate, independent verification, tenant/branch provisioning, renewal/closure, royalty approval/invoice/payment dan Finance reconciliation.
6. BI: source ingestion dan aggregation jobs, approved KPI/formula version, lineage population, watermark/freshness monitoring, passed reconciliation, cohort/benchmark/export scheduling, dan drill-down ke source transaction. SQL guard saat ini masih design draft.
7. SaaS: panggil metering setelah operasi authoritative commit; implement invoice/provider payment/settlement webhook, entitlement enforcement di setiap API, suspend/reactivate, support-access approval/audit, export/retention/deletion evidence.
8. Procurement: supplier invoice intake/storage evidence, returns/credit notes, AP balanced journal, payment execution, supplier settlement dan AP reconciliation. Three-way match/approval bukan pembayaran.
9. Executive: company→region→branch→shift→transaction drilldown dengan authorization tiap level, KPI source-linked dan Finance tie-out; alert assignment/task owner, source-driven alert generation, 150-branch ranking/cohort, target-vs-actual dan measured action outcome.
10. Domain lain: lot/FEFO/valuation; nested BOM/costing/allergens; food safety/QC; branch incident/maintenance/audit; Order ETA/channels; Finance AR/AP/GL/consolidation; Admin session/recovery/offboarding; integration provider signature/health; Quality load/restore/accessibility/pilot.

## 7. Gap per fitur dari register 189 PRD

### 1. Executive Command Center
- **[PARTIAL] Company overview / owner dashboard** — Basic ERP overview and funnel metrics exist; authoritative rollups need reconciliation.
- **[PARTIAL] Live sales monitor (day/week/month)** — Basic reporting UI exists; verify against source orders and business-date cutoff.
- **[NOT VERIFIED] Branch ranking, region/format comparison** — No verified 150-branch ranking/cohort output.
- **[PARTIAL] Gross/net sales, discounts, refunds, margin, AOV, item counts** — Some source tables/metrics exist; KPI dictionary and totals reconciled to transaction fixtures are missing.
- **[NOT VERIFIED] Critical stock, expiry, waste alerts** — Lot/expiry/waste alert workflow not proven.
- **[NOT VERIFIED] Sales-drop / food-cost anomaly detection** — No verified anomaly rule, assignment, acknowledgement, or closure.
- **[PARTIAL] Approval center and pending approvals** — Some PO/expense/refund approvals exist; unified queue and delegated policies not proven.
- **[NOT VERIFIED] Target vs actual and executive reports** — Official targets, scheduled reports, and exports not proven.
- **[BLOCKED] Company → region → branch → shift → transaction drill-down** — Role-aware drill-down and row-level consistency need browser and API tests.
- **[PARTIAL] Alert → assign task → resolve → audit result** — Assignment and action-outcome workflow not proven. Evidence started: src/supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/EXECUTIVE_COMMAND_CENTER_SCHEMA_DRAFT.sql — alert transition, evidence-required resolution, independent verification. Assignment task linkage and source-driven generation remain gaps.

### 2. POS & Checkout
- **[PARTIAL] POS workspace, shifts, cash reconciliation** — POS sales/shifts and cash reconciliation structures exist; complete operating-day E2E still needed.
- **[PARTIAL] Cart, product selection, quantity updates** — Checkout/cart foundations exist; full modifier and concurrency coverage not proven.
- **[PARTIAL] Dine-in, takeaway, pickup, delivery parity** — Pickup/delivery fields exist; all order types and downstream behavior need E2E.
- **[PARTIAL] Variants, toppings, special instructions** — Complete modifier-group flow not proven. Evidence started: PR #143 (open, separate branch feat/pos-checkout-lifecycle-20261124) — modifiers, split tender, held order/resume, immutable digital receipt and offline replay work started. Cashier UI/browser acceptance, partial balance collection and network fault injection remain gaps.
- **[NOT VERIFIED] Discounts, coupons, vouchers, special pricing** — Rule engine, approvals, and audit evidence missing.
- **[PARTIAL] Cash, QRIS, card, transfer and other provider methods** — Payment-proof/status foundations exist; live provider confirmation and settlement parity not proven.
- **[PARTIAL] Split bill, partial payment, final settlement** — Partial/split tender lifecycle not proven. Evidence started: PR #143 (open, separate branch feat/pos-checkout-lifecycle-20261124) — modifiers, split tender, held order/resume, immutable digital receipt and offline replay work started. Cashier UI/browser acceptance, partial balance collection and network fault injection remain gaps.
- **[PARTIAL] Hold/resume order** — No verified workflow found. Evidence started: PR #143 (open, separate branch feat/pos-checkout-lifecycle-20261124) — modifiers, split tender, held order/resume, immutable digital receipt and offline replay work started. Cashier UI/browser acceptance, partial balance collection and network fault injection remain gaps.
- **[PARTIAL] Void, refund, return with reason and approval** — Refund records/request/approval/processing exist; POS void/return policy and positive E2E are incomplete.
- **[PARTIAL] Receipt printing/digital receipt** — Receipt behavior needs device/browser/provider acceptance. Evidence started: PR #143 (open, separate branch feat/pos-checkout-lifecycle-20261124) — modifiers, split tender, held order/resume, immutable digital receipt and offline replay work started. Cashier UI/browser acceptance, partial balance collection and network fault injection remain gaps.
- **[PARTIAL] Cash in/out, drawer reconciliation, shift close** — Cash reconciliation/shift structures exist; positive and variance fixtures need end-to-end proof.
- **[PARTIAL] Offline sales queue and safe resynchronization** — Offline persistence, deduplication and replay recovery not proven. Evidence started: PR #143 (open, separate branch feat/pos-checkout-lifecycle-20261124) — modifiers, split tender, held order/resume, immutable digital receipt and offline replay work started. Cashier UI/browser acceptance, partial balance collection and network fault injection remain gaps.
- **[PARTIAL] Separate order, payment, fulfillment statuses** — Status separation foundations exist; all transitions and retry/idempotency cases need positive E2E.

### 3. Order Management
- **[PARTIAL] Online and POS orders / shared queue** — Online order flow and ERP queue foundations exist.
- **[NOT VERIFIED] WhatsApp, marketplace, additional channels** — Provider integrations and contract tests missing.
- **[PARTIAL] Hours, cutoff, menu availability, branch capacity** — Branch routing/capacity and WIB/WITA/WIT cutoff contract exist; full browser E2E still needed.
- **[PARTIAL] Branch assignment by area/capacity** — Routing foundation exists; overload/failover cases not proven.
- **[PARTIAL] Unique business order number** — DLC date/sequence formatter exists; uniqueness and concurrency acceptance needed.
- **[PARTIAL] Consistent status/timeline across channels** — Order status history exists; cross-channel parity not proven.
- **[PARTIAL] Duplicate orders, delayed payment, failed order handling** — PR #123 adds stable checkout idempotency and atomic order/reservation ledger; PR #125 adds unpaid/unproven reservation expiry and compensation; PR #127 adds atomic proof submission and payment-attempt supersession. Exact-head CI and disposable replay pass. Browser response-drop/concurrent submission, late provider webhook, live expiry worker and full order/payment/reservation reconciliation remain NOT RUN.
- **[NOT VERIFIED] Preparation ETA and exception escalation** — SLA prediction and escalation workflow missing.
- **[PARTIAL] Cancellation/refund and customer order history** — Status/refund/history foundations exist; complete lifecycle and notification proof missing.
- **[PARTIAL] Customer notifications on each state** — Notification log/retry foundations exist; actual delivery and idempotent event handling unverified.

### 4. Kitchen & Production
- **[PARTIAL] KDS and kitchen order tickets** — KDS tables and dispatch/transition RPCs exist; staging has 6 tickets and 6 items. Station routing and positive live workflow remain unproven.
- **[NOT VERIFIED] Station routing (hot/cold/beverage/packing)** — No verified station configuration and routing.
- **[PARTIAL] Queue priority and prep SLA** — kitchen_tickets.priority exists and is persisted; SLA targets, overdue escalation and station-level queue behavior are not implemented/proven.
- **[PARTIAL] Waiting → in progress → ready → handed over** — Fulfillment/status foundations exist; kitchen-specific state machine and E2E missing.
- **[PARTIAL] Recipes, portion/yield and waste tolerance** — Recipe/BOM and actual consumption structures exist; yield/tolerance calculations incomplete.
- **[PARTIAL] Prep lists and batch planning** — Production batches exist; forecast-driven prep planning not proven.
- **[PARTIAL] Actual material consumption** — Atomic production consumption RPC exists; positive recipe-to-stock reconciliation needed.
- **[NOT VERIFIED] QC, temperature, shelf life and spoilage** — Food safety checks and corrective actions not proven.
- **[PARTIAL] Made-to-order vs batch production separation** — Batch/consumption foundations exist; distinct planning/fulfillment paths need acceptance.
- **[BLOCKED] Theoretical vs actual usage / waste variance** — No verified variance report reconciled against stock ledger.

### 5. Menu, Recipe & Product Engineering
- **[PARTIAL] Central product catalog and categories** — Product catalog exists; full category/variant/modifier lifecycle needs proof.
- **[PARTIAL] Per-branch availability** — Branch capacity/availability foundations exist; real branch parity unverified.
- **[PARTIAL] Central, regional and branch-specific pricing** — branch_settings has a pricing category and branch settings read/write handlers exist; central/regional hierarchy, effective-date approvals and branch parity remain unproven.
- **[PARTIAL] Recipe/BOM and ingredient mapping** — Recipe ingredients and version activation exist.
- **[NOT VERIFIED] Nested BOM, unit conversions, yield and prep loss** — Nested sub-recipes and conversion engine not proven.
- **[PARTIAL] Recipe versions and effective dates** — Atomic activation exists; historical version immutability/effective-date tests missing.
- **[NOT VERIFIED] Cost per serving and contribution margin** — Costing engine and reconciled margin outputs missing.
- **[NOT VERIFIED] Allergens and regulated product information** — Structured allergen/product compliance flow missing.
- **[PARTIAL] Availability by schedule and stock** — Capacity/availability foundations exist; stock-aware availability not proven.
- **[PARTIAL] Recipe change request → costing → approval → rollout** — Version activation exists; full approval/simulation/branch verification missing.
- **[BLOCKED] POS/production uses the same approved recipe version** — Cross-module version parity needs E2E proof.

### 6. Inventory & Warehouse
- **[PARTIAL] Inventory item and branch stock** — Inventory items and branch inventory exist.
- **[PARTIAL] Stock movement ledger** — Stock movement table and atomic receiving/production flows exist; all movement sources need reconciliation.
- **[PARTIAL] Warehouse/storage/bin hierarchy** — warehouses table and ERP list/create handlers exist; storage zones/bins, location hierarchy and transfer integration remain unproven.
- **[PARTIAL] Purchase/use units and conversions** — Item/recipe quantity structures exist; conversion and rounding policy incomplete.
- **[NOT VERIFIED] FIFO/FEFO, lot/batch and expiry** — Lot traceability and expiry allocation missing.
- **[PARTIAL] Available/reserved/in-transit/blocked balances** — Transfer lifecycle exists; full stock-bucket accounting not proven.
- **[PARTIAL] Min/max, safety stock and reorder point** — inventory_items.min_stock exists; safety stock, reorder policy, supplier lead-time calculations and replenishment workflow remain unproven.
- **[PARTIAL] Transfer lifecycle draft → approve → pick → ship → receive → reconcile** — Transfer states and ledger hooks exist; positive quantity/idempotency/cross-branch E2E required.
- **[PARTIAL] Stock count/cycle count and variance adjustment** — Count/posting foundations exist; full positive reconciliation and approval limits required.
- **[NOT VERIFIED] Stock valuation** — Valuation method and historical valuation reports not proven.
- **[PARTIAL] Adjustments with reasons/approvals/audit** — Restricted workflow/audit foundations exist; risk thresholds and full review trail missing.
- **[PARTIAL] PO receipt → stock ledger → balance reconciliation** — Receipt-reconciliation endpoint exists; positive procurement workflow has not been run.

### 7. Procurement & Supplier
- **[PARTIAL] Supplier directory** — Supplier master exists.
- **[NOT VERIFIED] Supplier price lists, contracts and price history** — No verified contract/effective price lifecycle.
- **[PARTIAL] Purchase requisition from branch/warehouse/central kitchen** — PR #36 adds branch-scoped multi-line requisitions, draft/submit/Owner approve-or-reject/convert-to-PO, service-role-only atomic RPCs, audit trail, and ERP UI. Positive runtime E2E has not yet run; warehouse/central-kitchen consolidation remains missing.
- **[NOT VERIFIED] Consolidated demand across branches** — Multi-branch buying/consolidation missing.
- **[PARTIAL] Purchase order draft, submit, approval, ordered** — PO state transitions exist; positive-path test still needed.
- **[PARTIAL] Approval limits by value/category** — Approval actions exist; configurable thresholds/delegation not proven.
- **[PARTIAL] Goods received note and quantity/quality inspection** — Atomic receiving RPC and GRN structures exist; live positive E2E pending.
- **[PARTIAL] Three-way match: PO, receipt, supplier invoice** — Invoice matching and tolerance/exception handling missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/PROCUREMENT_SUPPLIER_SCHEMA_DRAFT.sql — invoice matching and independent approval path. Invoice intake, AP posting/payment and settlement reconciliation remain gaps.
- **[NOT VERIFIED] AP handoff and supplier payment** — Procurement-to-AP-to-payment reconciliation missing.
- **[NOT VERIFIED] Supplier return and supplier performance** — Return and scorecard workflows missing.

### 8. Branch Operations
- **[PARTIAL] Branch directory, status, timezone and assignments** — Branch master, timezone and job assignments exist; 150 branch data readiness is not established.
- **[PARTIAL] Opening and closing checklists** — Checklist runs, item status and critical-item completion gates exist.
- **[BLOCKED] Opening readiness changes branch operating status** — Real branch lifecycle integration not proven.
- **[NOT VERIFIED] Daily tasks, due dates and escalation** — Task assignment/scheduling/notification workflow missing.
- **[PARTIAL] SOP and work instructions** — Operating model/docs exist; in-app versioned SOP delivery not proven.
- **[PARTIAL] Cleanliness, equipment and safety checks** — Checklist foundations exist; calibrated evidence and full templates missing.
- **[NOT VERIFIED] Photo evidence** — Evidence upload/storage/retention workflow missing.
- **[NOT VERIFIED] Incidents and corrective actions** — Incident severity, assignment, escalation and closure missing.
- **[NOT VERIFIED] Equipment maintenance** — Work orders, preventive maintenance and downtime records missing.
- **[NOT VERIFIED] Branch audit and compliance score** — Audit scoring and executive roll-up missing.

### 9. Delivery & Fulfillment
- **[PARTIAL] Pickup/delivery selection and fulfillment queue** — Order type and fulfillment state foundations exist.
- **[NOT VERIFIED] Address validation and delivery quote** — Live quote provider and validation missing.
- **[NOT VERIFIED] Courier booking / Biteship integration** — No provider credentials, contract tests or live integration evidence.
- **[PARTIAL] Dispatch and shipment tracking** — Courier lifecycle and tracking callbacks missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/DELIVERY_FULFILLMENT_SCHEMA_DRAFT.sql — dispatch lifecycle and tenant/branch-scoped POD evidence/upload path. Provider booking, signed webhook, live tracking and courier fee reconciliation remain gaps.
- **[PARTIAL] Proof of delivery** — POD capture and access policy missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/DELIVERY_FULFILLMENT_SCHEMA_DRAFT.sql — dispatch lifecycle and tenant/branch-scoped POD evidence/upload path. Provider booking, signed webhook, live tracking and courier fee reconciliation remain gaps.
- **[NOT VERIFIED] Cancel/retry/provider exception handling** — Idempotent retry, cancellation and compensation missing.
- **[NOT VERIFIED] Customer fee, subsidy and actual courier cost separation** — Cost model and reconciliation report missing.
- **[PARTIAL] Delivery completion notification** — Notification foundation exists; provider event → customer status E2E missing.

### 10. CRM, Loyalty & Marketing
- **[PARTIAL] Unified customer profile across channels** — Customer/order identity fields and history foundations exist; deduplication not proven.
- **[PARTIAL] Consent and communication preferences** — Consent lifecycle, withdrawal and audit missing. Evidence started: src/crm-loyalty-domain.mjs; supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/CRM_LOYALTY_SCHEMA_DRAFT.sql — consent lifecycle, loyalty ledger/rewards/vouchers, campaign approval/audience queue and paid transaction identity linking. Automatic earning from reconciled net sales and outbound provider delivery remain gaps.
- **[NOT VERIFIED] Customer segments** — Segment rules and refresh jobs missing.
- **[PARTIAL] Loyalty points and tiers** — Ledger, expiry, reversal and duplicate-event protection missing. Evidence started: src/crm-loyalty-domain.mjs; supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/CRM_LOYALTY_SCHEMA_DRAFT.sql — consent lifecycle, loyalty ledger/rewards/vouchers, campaign approval/audience queue and paid transaction identity linking. Automatic earning from reconciled net sales and outbound provider delivery remain gaps.
- **[PARTIAL] Rewards and vouchers/coupons** — Issuance, eligibility, redemption and reversal missing. Evidence started: src/crm-loyalty-domain.mjs; supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/CRM_LOYALTY_SCHEMA_DRAFT.sql — consent lifecycle, loyalty ledger/rewards/vouchers, campaign approval/audience queue and paid transaction identity linking. Automatic earning from reconciled net sales and outbound provider delivery remain gaps.
- **[NOT VERIFIED] Referral program** — Attribution and fraud controls missing.
- **[PARTIAL] Campaign management and ROI** — Campaign lifecycle and attribution metrics missing. Evidence started: src/crm-loyalty-domain.mjs; supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/CRM_LOYALTY_SCHEMA_DRAFT.sql — consent lifecycle, loyalty ledger/rewards/vouchers, campaign approval/audience queue and paid transaction identity linking. Automatic earning from reconciled net sales and outbound provider delivery remain gaps.
- **[NOT VERIFIED] Feedback/reviews/support cases** — Ticketing, SLA and escalation missing.
- **[NOT VERIFIED] Repeat purchase and customer lifetime analysis** — Canonical customer identity and verified BI metrics missing.

### 11. Finance & Accounting
- **[PARTIAL] Finance overview, expenses and approvals** — Branch expense approval foundations exist.
- **[PARTIAL] Cash/bank, settlement creation and matching** — Settlement and cash reconciliation structures/RPCs exist; source-to-bank positive E2E pending.
- **[BLOCKED] Payment provider fee and settlement variance** — Full fee/variance reconciliation not proven.
- **[NOT VERIFIED] AR/AP subledgers and aging** — Complete AR/AP workflows and control-account tie-out missing.
- **[PARTIAL] Chart of accounts and general ledger** — Journal-entry table exists; full COA/posted balanced journal lifecycle not proven.
- **[NOT VERIFIED] Automated journals from POS/procurement/payroll** — Source mapping and balanced journal posting missing.
- **[PARTIAL] Bank reconciliation** — Cash/bank reconciliation foundations exist; statement import and independent matching not proven.
- **[PARTIAL] Tax and invoicing** — Tax settings exist; tax calculations, invoice numbering and compliance tests missing.
- **[NOT VERIFIED] Budgets and branch P&L** — Budget-vs-actual and branch P&L not reconciled.
- **[NOT VERIFIED] Consolidated financial statements** — Group consolidation missing.
- **[PARTIAL] Period close/reopen and backdated-posting controls** — Fiscal period guards exist; close/reopen and full GL acceptance missing.
- **[PARTIAL] Revenue vs cash received/settlement distinction** — Payment/settlement concepts exist; end-to-end reconciliation is incomplete.

### 12. HR & Workforce
- **[PARTIAL] Employee directory and lifecycle** — Employee hire/change/termination lifecycle missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/HR_WORKFORCE_SCHEMA_DRAFT.sql — employee listing, attendance, schedules, leave, timesheets, effective-dated hourly compensation and payroll approval. Overtime/tax/deductions/payment and actual Finance journal posting remain gaps.
- **[PARTIAL] Organization hierarchy and job positions** — Job positions and branch assignments exist.
- **[PARTIAL] Attendance and timesheets** — Clock-in/out, approvals and exception handling missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/HR_WORKFORCE_SCHEMA_DRAFT.sql — employee listing, attendance, schedules, leave, timesheets, effective-dated hourly compensation and payroll approval. Overtime/tax/deductions/payment and actual Finance journal posting remain gaps.
- **[PARTIAL] Shift scheduling and replacement** — Demand-based scheduling and shift swaps missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/HR_WORKFORCE_SCHEMA_DRAFT.sql — employee listing, attendance, schedules, leave, timesheets, effective-dated hourly compensation and payroll approval. Overtime/tax/deductions/payment and actual Finance journal posting remain gaps.
- **[PARTIAL] Leave and overtime** — Approval and policy engine missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/HR_WORKFORCE_SCHEMA_DRAFT.sql — employee listing, attendance, schedules, leave, timesheets, effective-dated hourly compensation and payroll approval. Overtime/tax/deductions/payment and actual Finance journal posting remain gaps.
- **[PARTIAL] Payroll calculation/integration** — Provider integration and payroll reconciliation missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/HR_WORKFORCE_SCHEMA_DRAFT.sql — employee listing, attendance, schedules, leave, timesheets, effective-dated hourly compensation and payroll approval. Overtime/tax/deductions/payment and actual Finance journal posting remain gaps.
- **[NOT VERIFIED] Labor cost by branch** — Approved payroll-to-branch allocation missing.
- **[NOT VERIFIED] Training/certification and performance reviews** — Course, certificate expiry and review workflow missing.
- **[NOT VERIFIED] Recruitment/onboarding/offboarding** — Onboarding checklist and access revocation missing.

### 13. Franchise & Expansion
- **[PARTIAL] Branch ownership model** — Branch master foundation exists; ownership policies not proven end-to-end.
- **[PARTIAL] Franchise directory/application** — Application and due diligence workflow missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/FRANCHISE_EXPANSION_SCHEMA_DRAFT.sql — application intake, due-diligence/site review, agreement design and BI-backed royalty statement generation. E-signature, territory rules, all opening gates, provisioning and payment remain gaps.
- **[PARTIAL] Site selection and feasibility** — Site scorecard, financial forecast and approval missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/FRANCHISE_EXPANSION_SCHEMA_DRAFT.sql — application intake, due-diligence/site review, agreement design and BI-backed royalty statement generation. E-signature, territory rules, all opening gates, provisioning and payment remain gaps.
- **[PARTIAL] Opening project and readiness** — Branch setup/checklist foundations exist; full project workflow missing.
- **[PARTIAL] Agreements and contract expiry** — Document/version/renewal controls missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/FRANCHISE_EXPANSION_SCHEMA_DRAFT.sql — application intake, due-diligence/site review, agreement design and BI-backed royalty statement generation. E-signature, territory rules, all opening gates, provisioning and payment remain gaps.
- **[PARTIAL] Royalty calculation and reconciliation** — Contract-driven royalty ledger and settlement missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/FRANCHISE_EXPANSION_SCHEMA_DRAFT.sql — application intake, due-diligence/site review, agreement design and BI-backed royalty statement generation. E-signature, territory rules, all opening gates, provisioning and payment remain gaps.
- **[NOT VERIFIED] Territory and franchise-specific access** — Geographic scope and tenant/franchise isolation missing.
- **[NOT VERIFIED] Franchise compliance and performance** — Audit, corrective action and partner reporting missing.

### 14. BI & Analytics
- **[PARTIAL] Basic overview, funnel metrics and reports** — Basic overview/funnel metrics exist.
- **[PARTIAL] Official KPI dictionary and versioning** — Formula, source, timezone, refresh SLA and owner missing. Evidence started: docs/implementation/sql/BI_ANALYTICS_SCHEMA_DRAFT.sql; erp.html — metric definition/version, source lineage, watermark freshness/completeness and reconciliation publication guards. Source ingestion, aggregation, KPI seeds and drill-down remain gaps.
- **[PARTIAL] Net sales/AOV/gross margin** — Source data exists; canonical totals and reconciliation tests missing.
- **[NOT VERIFIED] Food cost %, labor cost %, waste %** — Actual vs theoretical cost data and formula definitions missing.
- **[PARTIAL] Stock variance and fulfillment/cancellation rates** — Source entities exist; canonical metric outputs not proven.
- **[NOT VERIFIED] Branch benchmarking by comparable cohorts** — Format/region/hours cohort definitions missing.
- **[NOT VERIFIED] Demand forecasting and accuracy monitoring** — Forecast pipeline, evaluation and override audit missing.
- **[PARTIAL] Data quality monitoring and anomaly detection** — Freshness/completeness checks and alert lifecycle missing. Evidence started: docs/implementation/sql/BI_ANALYTICS_SCHEMA_DRAFT.sql; erp.html — metric definition/version, source lineage, watermark freshness/completeness and reconciliation publication guards. Source ingestion, aggregation, KPI seeds and drill-down remain gaps.
- **[NOT VERIFIED] Export and scheduled executive reports** — Controlled exports and schedules missing.
- **[NOT VERIFIED] Alert → action → measured outcome** — Closed-loop workflow missing.

### 15. Admin, Identity & Access Control
- **[PARTIAL] User/admin profiles, role and permission actions** — Admin profile and action-level permission foundations exist.
- **[PARTIAL] Branch assignments and scope enforcement** — Server-side branch checks exist; full matrix testing is ongoing.
- **[PARTIAL] Owner/manager/no-permission/inactive identity probes** — An existing negative/role suite reports 21 PASS / 0 FAIL. This is concrete test work, but it is not complete positive business E2E or live acceptance for all roles and inactive identities.
- **[PARTIAL] Audit logs for sensitive actions** — Audit log table and events exist; coverage of all sensitive mutations not proven.
- **[PARTIAL] Delegated approval policies and separation of duties** — Some approval gates exist; configurable policy matrix missing.
- **[NOT VERIFIED] Sessions/devices and access reviews** — Session inventory, revocation and periodic review missing.
- **[NOT VERIFIED] Recovery and offboarding** — Safe account recovery and immediate access revocation not proven.
- **[PARTIAL] API/database deny-by-default and direct-table protection** — All 45 public tables have RLS; most internal tables have no direct anon/authenticated SELECT. Public catalog access is intentionally exposed and still requires policy review.
- **[PARTIAL] Cross-tenant isolation** — P01-P09 live staging acceptance passes 9/9 on commit 666f2a4; supplemental direct RLS/RPC checks 6/6 and 230/230 missing/invalid-auth action probes pass. Cross-tenant writes return 403 with verified zero transfer/item/stock-movement side effects. Remaining gaps: complete mutation/API route coverage, Storage, cache, background jobs, invitation lifecycle, multi-branch/150-branch concurrency, browser E2E and broader operational reconciliation.
- **[PARTIAL] Permission changes themselves audited** — PR #120 exact head 471f4a330a4da0cb13afe60ddeeb520e28dc0e88 passes all six CI/migration workflows. Audited RPCs cover permission changes, staff profile creation, role and active-state changes; forced audit-failure tests prove rollback. Password reset now writes a durable audit intent before Auth Admin mutation and finalizes success/failure; pending intent survives finalization failure. Live staging mutation-path regression remains NOT RUN.

### 16. SaaS Tenant Management
- **[PARTIAL] Tenant directory, tenant onboarding** — PR #126 adds atomic invite issue/accept RPCs, replay/expiry/audit handling and 15 invitation pgTAP assertions; exact-head full disposable replay passes. Existing Tenant A/B Auth identities and branch assignments are verified read-only. Runtime invitation delivery/acceptance/expiry, default branch provisioning, entitlements, suspension/offboarding/export and browser E2E remain unproven.
- **[PARTIAL] Tenant/member isolation in database and APIs** — P01-P09 live staging acceptance passes 9/9 on commit 666f2a4; supplemental direct RLS/RPC checks 6/6 and 230/230 missing/invalid-auth action probes pass. Cross-tenant writes return 403 with verified zero transfer/item/stock-movement side effects. Remaining gaps: complete mutation/API route coverage, Storage, cache, background jobs, invitation lifecycle, multi-branch/150-branch concurrency, browser E2E and broader operational reconciliation.
- **[PARTIAL] Plans, subscriptions, entitlements and quotas** — Server-enforced entitlements and usage limits missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/SAAS_TENANT_BILLING_SCHEMA_DRAFT.sql — plan/entitlement, retry-safe usage primitive and approved offboarding/legal-hold workflow. Operational metering call-sites, billing settlement, suspension and verified export/deletion remain gaps.
- **[PARTIAL] Billing, invoices and usage metering** — Subscription billing and idempotent usage ledger missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/SAAS_TENANT_BILLING_SCHEMA_DRAFT.sql — plan/entitlement, retry-safe usage primitive and approved offboarding/legal-hold workflow. Operational metering call-sites, billing settlement, suspension and verified export/deletion remain gaps.
- **[NOT VERIFIED] Tenant settings and suspension** — Lifecycle and grace/suspension behavior missing.
- **[NOT VERIFIED] Support access with approval/audit** — Just-in-time scoped support access missing.
- **[PARTIAL] Export/offboarding and data deletion policy** — Audited export, retention and deletion workflow missing. Evidence started: supabase/functions/dlice-orders/index.ts; erp.html; docs/implementation/sql/SAAS_TENANT_BILLING_SCHEMA_DRAFT.sql — plan/entitlement, retry-safe usage primitive and approved offboarding/legal-hold workflow. Operational metering call-sites, billing settlement, suspension and verified export/deletion remain gaps.
- **[NOT VERIFIED] Multiple companies sharing one platform safely** — One D’Lice org with branch slots is not proof of multi-tenant SaaS.

### 17. Integrations & Automation
- **[PARTIAL] Edge Function API and payment proof flow** — Shared \dlice-orders\ endpoint and payment proof/status paths exist.
- **[NOT VERIFIED] Payment provider callback signature and status validation** — No verified live provider webhook evidence.
- **[NOT VERIFIED] Delivery/e-commerce/WhatsApp/accounting connectors** — Provider-specific integrations not proven.
- **[PARTIAL] Webhooks and event log** — Notification logs/retry actions exist; durable event delivery contract missing.
- **[PARTIAL] Idempotency and replay protection** — PR #123 adds online checkout idempotency and atomic order/reservation ledger; PR #127 adds idempotent proof upload and payment-attempt supersession. Exact-head contracts and disposable replays pass; browser concurrency, Storage orphan recovery and live transaction reconciliation remain NOT RUN.
- **[PARTIAL] Retry/backoff/dead-letter queue** — Notification retry foundation exists; durable retry/dead-letter behavior missing.
- **[NOT VERIFIED] Integration health and alerting** — Health dashboards, lag/error alerts and recovery runbooks missing.
- **[PARTIAL] Secret storage/rotation** — Secret-based CORS config is active; integration credential rotation/least privilege not audited end-to-end.
- **[NOT VERIFIED] Import/export and catalog synchronization** — Validated imports, conflict resolution and scheduled sync missing.

### 18. Quality, Compliance & Security
- **[PARTIAL] RLS on exposed public tables** — Live read-only SQL on 2026-11-20: 64/64 public tables have RLS enabled and 64 public policies exist. Per-table policy correctness and full role/tenant negative runtime tests remain outstanding, so this is PARTIAL rather than PASS.
- **[PARTIAL] Direct access to internal stock/procurement/audit data** — No direct anon/authenticated SELECT grants on key internal tables; endpoint-level scope tests still required.
- **[PARTIAL] Exact-origin CORS** — Staging CORS runtime run 44307838539 passed registered-origin OPTIONS (200/exact ACAO), foreign-origin OPTIONS (403/no ACAO), and no-Origin OPTIONS (200/no ACAO). POST/authenticated action coverage and full endpoint regression remain outstanding.
- **[PARTIAL] Custom auth/permission checks on shared endpoint** — \verify_jwt=false\ remains; custom action authentication is present, so every action must remain covered by regression tests.
- **[PARTIAL] Leaked-password protection** — The application-layer k-anonymity Pwned Password guard is integrated into official Owner bootstrap, staff creation and staff password reset flows; unit and source-contract tests pass in PR #120. Native Supabase Auth leaked-password protection remains disabled on the current plan and direct Auth password changes can bypass the Edge Function guard; the feature is not DONE.
- **[NOT VERIFIED] Food safety, temperature, allergens, recall** — Operational compliance records and recall traceability missing.
- **[NOT VERIFIED] Supplier quality, quarantine, corrective actions** — Inspection, quarantine and CAPA lifecycle missing.
- **[NOT VERIFIED] Backup and restore drill / RPO / RTO** — No restore rehearsal evidence found.
- **[PARTIAL] Monitoring, system health and incident runbooks** — Rate limits and logs exist; production-grade alert/runbook acceptance missing.
- **[NOT VERIFIED] Load/concurrency test for 150 branches** — No approved realistic workload test or latency/error SLO evidence.
- **[NOT VERIFIED] Pilot, rollout and rollback** — No signed-off pilot operating-day reconciliation or tested rollback evidence.
- **[NOT VERIFIED] Workflow** — Exit criteria
- **[PARTIAL] Order-to-Cash** — Create order → verify payment → route → kitchen/fulfillment → stock consumption exactly once → settlement/cash match → customer/BI update. Reconcile source and totals.
- **[PARTIAL] Procure-to-Pay** — PR → consolidation → approval → PO → GRN → stock movement/balance → invoice 3-way match → AP → supplier payment. Positive E2E and artifact are still required.
- **[PARTIAL] Forecast-to-Production** — Forecast → recipe requirements → available/expiry-valid stock → PR/transfer → batch/prep → actual consumption/waste → stock and cost reconciliation. Forecasting itself is not proven.
- **[PARTIAL] Record-to-Report** — POS/procurement/payroll/expenses → source mapping → balanced journal → settlement/stock/AP reconciliation → period close → branch P&L → group consolidation.
- **[PARTIAL] Stock transfer and count** — All states, correct source/destination quantities, one ledger event per transition, retries safe, variance approved, branch scope verified.
- **[PARTIAL] Authentication and permissions** — Positive and negative role tests per action, anonymous 401, unauthorized 403, cross-branch/tenant deny, inactive-user deny, audit event, browser path.
- **[NOT VERIFIED] Responsive UX and accessibility** — Accepted screenshots and interactions on mobile/tablet/desktop; keyboard/focus, reduced motion, contrast, labels, validation and screen-reader checks.
- **[NOT VERIFIED] Backup, recovery, scale and rollout** — Restore drill, measured RPO/RTO, concurrency test, branch pilot and rollback rehearsal.

## 8. Release guard dan acceptance

- TENANT_ISOLATION_RELEASED=false dan PUBLIC_TENANT_ROUTING_RELEASED=false harus tetap.
- Production hanya audit. Tidak ada production DB/secrets/env/deploy/data changes.
- Tidak ada force push, auto-merge, merge, atau bypass authorization/review gates.
- Service-role tidak boleh muncul di browser/log. auth.users metadata hanya melalui Auth Admin resmi, bukan SQL.
- Mengikuti urutan yang sudah disepakati, test gabungan, disposable migration replay, merge, dan staging migration application dilakukan dalam satu final batch. CI otomatis terakhir gagal dan fix membutuhkan exact-head PASS sebelum batch tersebut.
- Feature DONE hanya setelah PRD→DB entity/relation→RLS→API/RPC→UI→tests→staging runtime→E2E→operational reconciliation lengkap; semua test applicable PASS dan tidak ada BLOCKED/SKIPPED.

## 9. Hasil audit

Feature matrix diperbarui dan 27 fitur dipindahkan ke PARTIAL karena implementasi konkret telah dimulai. Belum ada fitur yang dinyatakan selesai. Blocker langsung: selisih baseline 3 fitur Admin/Quality yang belum terpetakan, PR #144 salah base/diverged, exact-head syntax/CI belum PASS, serta seluruh gap acceptance di atas.