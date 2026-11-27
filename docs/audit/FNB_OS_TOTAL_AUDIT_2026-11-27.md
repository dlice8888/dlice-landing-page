# D’Lice FnB OS — Total PRD Audit & Gap Register

**Tanggal audit:** 27 November 2026, 07:16 WIB  
**PRD:** 189 fitur / 18 domain  
**Repository:** `dlice8888/dlice-landing-page`  
**Candidate branch:** `feat/eight-domain-official-migrations-20261127`  
**Candidate head:** `e82ad0297877642020a13f3a5fab2366ba93a3f2`  
**Feature matrix:** `docs/audit/FNB_OS_IMPLEMENTATION_MATRIX.json`  
**Supabase staging:** `dlice-staging` / `higoadrzxnhzbbwhdbmh`

## 1. Ringkasan status terbaru

| Status | Jumlah | Makna |
|---|---:|---|
| PARTIAL | 139 | Ada implementasi konkret yang sudah dimulai; belum berarti workflow diterima |
| NOT VERIFIED | 45 | Belum ada implementasi yang cukup untuk dipindahkan ke PARTIAL |
| BLOCKED | 5 | Ada prasyarat eksternal/otorisasi yang menghalangi acceptance |
| DONE | 0 | Belum ada fitur yang lulus seluruh acceptance criteria |
| **TOTAL** | **189** | **18 domain** |

Cakupan implementasi yang sudah dimulai: **139/189 = 73,5%**. Ini bukan weighted completion dan bukan persentase penerimaan produksi.

Dari 139 fitur PARTIAL, dua fitur mempunyai skor weighted provisional terdahulu (Tenant/member isolation 38% dan Tenant directory/onboarding 30%). **137 PARTIAL lainnya belum mempunyai skor enam dimensi yang defensible**. Angka tidak akan ditebak; setiap fitur perlu breakdown Code/UI 20%, Database 20%, Authorization 15%, Automated tests 15%, Workflow E2E 20%, Reconciliation/observability 10%.

## 2. Matriks 18 domain — setelah audit

| Domain | Total | P | BT | B | S | Partial |
|---|---:|---:|---:|---:|---:|---:|
| Executive Command Center | 10 | 7 | 2 | 1 | 0 | 70% |
| POS & Checkout | 13 | 12 | 1 | 0 | 0 | 92,3% |
| Order Management | 10 | 8 | 2 | 0 | 0 | 80% |
| Kitchen & Production | 10 | 7 | 2 | 1 | 0 | 70% |
| Menu & Recipe | 11 | 7 | 3 | 1 | 0 | 63,6% |
| Inventory & Warehouse | 12 | 10 | 2 | 0 | 0 | 83,3% |
| Procurement & Supplier | 10 | 7 | 3 | 0 | 0 | 70% |
| Branch Operations | 10 | 4 | 5 | 1 | 0 | 40% |
| Delivery & Fulfillment | 8 | 8 | 0 | 0 | 0 | 100% |
| CRM & Loyalty | 9 | 6 | 3 | 0 | 0 | 66,7% |
| Finance & Accounting | 12 | 9 | 2 | 1 | 0 | 75% |
| HR & Workforce | 9 | 7 | 2 | 0 | 0 | 77,8% |
| Franchise & Expansion | 8 | 8 | 0 | 0 | 0 | 100% |
| BI & Analytics | 10 | 7 | 3 | 0 | 0 | 70% |
| Admin & Access Control | 10 | 8 | 2 | 0 | 0 | 80% |
| SaaS Tenant Management | 8 | 6 | 2 | 0 | 0 | 75% |
| Integrations & Automation | 9 | 6 | 3 | 0 | 0 | 66,7% |
| Quality, Compliance & Security | 20 | 12 | 8 | 0 | 0 | 60% |
| **TOTAL** | **189** | **139** | **45** | **5** | **0** | **73,5%** |

Keterangan: P = PARTIAL; BT = belum terbukti; B = BLOCKED; S = DONE. Cakupan Partial adalah jumlah fitur yang sudah mulai dikerjakan dibagi total domain, bukan persentase penyelesaian masing-masing fitur.

### Perubahan status pada audit 27 November

14 fitur dipindahkan dari NOT VERIFIED menjadi PARTIAL karena sudah memiliki modul, UI/Edge action, RPC atau SQL implementation artifact. Satu fitur Executive drill-down dipindahkan dari PARTIAL menjadi BLOCKED karena prasyarat Owner Auth tidak terbukti pada staging.

| Domain | Fitur yang mulai dikerjakan dan dipindahkan ke PARTIAL |
|---|---|
| Executive | Branch ranking; target vs actual dan executive reports |
| Delivery | Address validation/quote; courier booking; pemisahan customer fee, subsidy dan courier cost |
| CRM | Customer segments |
| Finance | AR/AP subledger; automated journals dari POS/procurement/payroll |
| HR | Recruitment/onboarding/offboarding |
| Franchise | Compliance dan performance |
| BI | Food cost/labor cost/waste metrics; branch benchmarking |
| SaaS | Tenant settings dan suspension |
| Integrations | Delivery/e-commerce/WhatsApp/accounting connector foundations |

Executive company→region→branch→shift→transaction drill-down sekarang BLOCKED sampai Owner Auth metadata dan allowlist cocok. Perubahan ini tidak mengubah status fitur lain tanpa bukti.

## 3. Bukti aktual GitHub, Supabase dan Vercel

### GitHub

- Candidate branch `feat/eight-domain-official-migrations-20261127` dibandingkan dengan `staging`: **525 commits ahead, 0 behind**, dengan 105 file berubah.
- Candidate berisi delapan official migration files yang dibangkitkan melalui Supabase CLI dari draft yang direview, plus pgTAP/contract test files.
- Candidate mencakup CRM/Loyalty, HR/Payroll/Finance, Delivery, Franchise, Procurement, BI, SaaS dan Executive. Migration set mengklaim 71 tabel baru lintas delapan domain.
- Candidate head `e82ad029...` belum memiliki GitHub Actions workflow run yang dapat diverifikasi pada exact head. Combined status yang terlihat hanya Vercel success.
- PR #143 tetap OPEN dan belum merge; PR #145 adalah Draft/orchestration candidate; PR #146 adalah payroll payout continuation. Tidak ada merge yang dilakukan dalam audit ini.

### Supabase staging

- Project `higoadrzxnhzbbwhdbmh` berstatus `ACTIVE_HEALTHY`.
- Database mencatat **63 applied migration versions**.
- `dlice-orders` ACTIVE versi 73; `verify_jwt=false`. Handler tetap harus memvalidasi bearer token, user, profile, tenant membership, branch scope dan Owner dual gate.
- Ada 68 public base tables; seluruh tabel yang diperiksa memiliki RLS enabled.
- Read-only schema query menemukan **0 tabel** dengan prefix `crm_`, `hr_`, `delivery_`, `franchise_`, `bi_`, `saas_`, atau `executive_`; tabel extension `supplier_tenant_links` dan `procurement_supplier_invoices` juga belum ada. Jadi migration kandidat delapan domain belum diterapkan ke staging.
- Ada satu active Owner profile, tetapi aggregate Auth query menunjukkan `raw_app_meta_data.platform_owner=true` berjumlah **0** dan jumlah user yang memiliki claim tersebut juga **0**. Secret allowlist `DLICE_PLATFORM_OWNER_USER_IDS` tidak dapat dibaca dari konektor ini. Owner authorization belum terverifikasi.

### Vercel

- Project `dlice-landing-page`.
- Preview terbaru yang terlihat READY pada candidate branch dan commit `e82ad029...`.
- READY hanya membuktikan build/deployment Preview, bukan business workflow acceptance.
- Tidak ada Production deployment, promotion atau perubahan konfigurasi Production.

## 4. POS staging — hasil rekonsiliasi aktual

| Pemeriksaan | Hasil | Status |
|---|---:|---|
| POS sales | 6 transaksi | Ada |
| Total sale | Rp600 | Ada |
| POS sale items | 6 baris / Rp600 | Cocok dengan sale |
| Tender allocation | 0 baris / Rp0 | GAP |
| Immutable receipt | 0 | GAP |
| KDS tickets | 6 | Record ada; lifecycle belum dibuktikan |
| Stock movements | 26 | Belum direkonsiliasi per sale/recipe |
| Stock transfers | 0 | Tidak ada bukti transfer |
| Closed shifts | 7 | Ada |
| Cash expected | Rp600 | Agregat |
| Cash counted | Rp600 | Agregat |
| Cash variance | Rp0 | Agregat, bukan rekonsiliasi per tender |

Enam sale masing-masing bernilai Rp100 dan item total masing-masing Rp100. Namun tender allocation dan immutable receipt tidak ada. Keberadaan KDS ticket tidak membuktikan status accepted/preparing/ready/served atau hubungan konsumsi resep. Stock movements harus dicocokkan berdasarkan reference, sale/order, recipe, inventory item dan kuantitas. Cash variance nol tidak menggantikan rekonsiliasi cash/non-cash tender per transaksi.

**POS staging E2E belum lulus.** Jangan tandai POS/Finance/Inventory/KDS/Receipt/Audit sebagai DONE dari data agregat ini.

## 5. Gap yang harus diselesaikan

### POS, Order, KDS, Inventory dan Finance

1. Selesaikan Owner Auth melalui jalur Supabase Auth Admin resmi: pertahankan metadata lain, set `app_metadata.platform_owner` sebagai JSON boolean `true` pada Owner yang benar, dan verifikasi UUID yang sama pada secret `DLICE_PLATFORM_OWNER_USER_IDS`. Jangan memakai SQL untuk mengedit Auth metadata dan jangan melemahkan dual gate.
2. Jalankan workflow POS staging E2E setelah otorisasi terverifikasi.
3. Rekonsiliasi sale total, item total, tender allocation, payment method, cash drawer delta, shift close, stock movement, recipe consumption, KDS lifecycle, receipt snapshot, dan audit events.
4. Tambahkan skenario split tender, duplicate/idempotent checkout, held/resume, offline replay, failed payment, refund/void dan network fault injection.
5. Hubungkan POS, Order, Refund, Settlement dan Finance pada canonical source references. Tidak boleh membuat loyalty earning dari payment paid saja; earning menunggu Finance close yang sudah direkonsiliasi.

### CRM & Loyalty

- Selesaikan canonical customer identity/deduplication dan linking POS sale/online order.
- Consent harus append-only, per-purpose/per-channel, dapat ditarik, dan diperiksa sebelum campaign queue.
- Loyalty earn hanya dari reconciled net sales setelah settlement/cash close, refund dan Finance journal direkonsiliasi.
- Redemption harus atomic, idempotent dan saldo tidak boleh negatif.
- Lengkapi expiry per lot, FIFO allocation, reversal dan one-reversal-per-entry.
- Lengkapi campaign provider contract, signed receipt, unsubscribe, retry/dead-letter, attribution dan ROI.
- Lengkapi customer segments, referral, feedback/support case dan repeat-purchase/LTV.

### HR & Payroll → Finance

- Lengkapi employee lifecycle, effective-dated transfer/position, attendance, timesheet, schedule, leave, overtime dan offboarding.
- Compensation hanya dari policy yang disetujui: hourly/monthly, allowances, overtime, tax, deductions dan employer contributions. Jangan mengarang statutory rate.
- Payroll run harus menghitung ulang dari approved timesheet/compensation snapshots, memakai independent approval dan idempotency.
- Posting harus memakai canonical `finance_journal_entries`, open fiscal period, balanced debit/credit, source reference, independent approval dan immutable reconciliation.
- Payroll payment tetap belum aktif sampai provider/beneficiary token contract disetujui, provider callback diverifikasi, dan bank statement reconciliation lulus.
- Lengkapi labor-cost per branch, recruitment/onboarding checklist, training/certification dan performance review.

### Delivery & Fulfillment

- Address validation dan quote harus terhubung ke provider yang benar-benar disetujui.
- Booking harus menyimpan provider reference, tracking dan status yang idempotent.
- Webhook harus memverifikasi signature raw body, timestamp, replay window dan duplicate event.
- POD membutuhkan private Storage bucket, policy, MIME/size/hash, object existence dan tenant/branch ownership.
- Tambahkan retry/backoff/dead-letter, cancel/compensation, customer notification, COD, fee/subsidy/courier-cost reconciliation ke Finance.
- Jangan mengklaim Biteship aktif tanpa credentials dan contract test yang sah.

### Procurement & Supplier

- Tenant supplier relationship dan supplier approval harus jelas; supplier global tidak boleh otomatis terlihat lintas tenant.
- Lengkapi requisition→approval→PO→GRN/inspection→invoice three-way match.
- Lengkapi AP journal, payment intent/provider, settlement, returns/credit note dan supplier scorecard.
- Rekonsiliasi invoice, PO, received quantity, AP ledger, bank settlement dan Finance journal.

### Franchise & Expansion

- Lengkapi application→due diligence→site feasibility→agreement version→independent approval→signature evidence.
- Opening harus menunggu seluruh gate dan verifier independen.
- Tenant/branch provisioning harus atomic dan tidak menerima tenant ID dari client.
- Royalty hanya dari Finance-reconciled eligible net sales, disertai invoice/payment/settlement.
- Tambahkan ongoing compliance audit, corrective action dan franchise performance reporting.

### BI & Analytics

- Metric harus mempunyai owner, unit, formula version, source entities, freshness SLA dan lineage.
- Source ingestion harus menyimpan watermark, expected/observed count dan source reconciliation.
- Food cost harus menghubungkan recipe theoretical usage dengan actual inventory consumption; labor cost dengan approved payroll; waste dengan posted waste events.
- Branch benchmarking mensyaratkan 150 active branches, cohort definitions, approved targets dan reconciled source facts.
- Tambahkan forecast accuracy, export/scheduled report, anomaly alert dan action-outcome loop.

### SaaS Tenant, Integrations dan Executive

- SaaS: plan version, entitlement/quota, post-commit metering, invoice, payment/renewal, suspension/reactivation, support access approval, export/legal hold/deletion.
- Integrations: provider-specific contracts, secret references/rotation, signed callbacks, durable outbox, retry/dead-letter, integration health/alerting dan import conflict handling.
- Executive: verified KPI targets, Finance-sourced actuals, hierarchy query adapters, authorization tiap level, branch ranking, alert→assign→resolve→audit, 150-branch completeness dan report schedule.

## 6. Urutan pengerjaan berikutnya

1. Selesaikan verifikasi Owner Auth dual gate; jangan menganggap sudah selesai sebelum staging read-only check membuktikannya.
2. Jalankan ulang POS staging E2E melalui workflow resmi yang dilindungi Environment.
3. Selesaikan sale/tender/cash/stock/KDS/receipt/audit reconciliation.
4. Hubungkan CRM/Loyalty ke POS, Order, Refund, Settlement dan Finance close.
5. Hubungkan HR/Payroll ke Finance journal dan payment reconciliation.
6. Lengkapi Delivery, Procurement, Franchise, BI, SaaS dan Executive workflows.
7. Perbarui feature matrix setelah setiap batch dengan bukti commit, schema/RLS/RPC, test, runtime dan reconciliation.
8. Tahap akhir saja: exact-head CI, disposable migration replay, pgTAP, tenant A/B positive/negative E2E, browser/device acceptance, 150-branch load test, merge review dan staging migration approval.

## 7. Guardrails

- Staging/disposable only; Production read-only.
- `TENANT_ISOLATION_RELEASED=false` dan `PUBLIC_TENANT_ROUTING_RELEASED=false`.
- No auto-merge, mass merge, force push, production deployment atau production data/secret/environment change.
- No service-role key in browser/logs.
- No Auth metadata SQL mutation.
- No DONE until all six weighted dimensions equal 100%, positive/negative workflow tests pass, no BLOCKED/SKIPPED/NOT RUN acceptance remains, and database/ledger reconciliation passes.
- Migration files in candidate branch are not evidence that staging schema changed.

