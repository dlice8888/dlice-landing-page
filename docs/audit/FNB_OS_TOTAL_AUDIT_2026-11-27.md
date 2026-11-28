# D’Lice FnB OS — Total PRD Audit & Gap Register

**Tanggal audit:** 27 November 2026, 23:18 WIB  
**PRD:** 189 fitur / 18 domain  
**Repository:** `dlice8888/dlice-landing-page`  
**Candidate branch:** `feat/branch-ops-evidence-workflows-20261127`  
**Candidate branch:** `feat/branch-ops-evidence-workflows-20261127` (head dipantau melalui PR #153)  
**Feature matrix:** `docs/audit/FNB_OS_IMPLEMENTATION_MATRIX.json`  
**Supabase staging:** `dlice-staging` / `higoadrzxnhzbbwhdbmh`

## 1. Ringkasan status terbaru

| Status | Jumlah | Makna |
|---|---:|---|
| PARTIAL | 188 | Seluruh 39 baseline belum terbukti dan 4 dari 5 blocked kini memiliki pekerjaan remediation konkret; belum berarti workflow diterima |
| NOT VERIFIED | 0 | Seluruh 39 baseline fitur sudah mulai dikerjakan |

| BLOCKED | 1 | Owner drill-down menunggu verifikasi resmi Auth Admin dan allowlist |
| DONE | 0 | Belum ada fitur yang lulus seluruh acceptance criteria |
| **TOTAL** | **189** | **18 domain** |

Cakupan implementasi yang sudah dimulai: **188/189 = 99,5%**. Ini adalah coverage status PARTIAL, bukan weighted completion dan bukan persentase penerimaan produksi. Seluruh baseline 39 NOT VERIFIED telah dipindahkan ke PARTIAL dan empat dari lima fitur BLOCKED juga sudah memiliki remediation konkret dan dipindahkan ke PARTIAL; setiap fitur baru boleh dipindahkan ke PARTIAL setelah ada artefak kerja nyata yang dapat ditelusuri.

Skor penyelesaian per fitur dihitung dari enam dimensi: Code/UI 20%, Database 20%, Authorization 15%, Automated tests 15%, Workflow E2E 20%, Reconciliation/observability 10%. Rubrik: PASS = 100% bobot dimensi, PARTIAL = 50% bobot, UNVERIFIED = 0%. **50 fitur Partial sudah memiliki skor berbobot; 43 fitur batch baru berada pada 33–38%. Sebanyak 138 fitur Partial masih UNSCORED** karena bukti enam dimensinya belum cukup. DONE memerlukan skor 100% dan seluruh gate lulus.

## 2. Matriks 18 domain — setelah audit

| Domain | Total | P | BT | B | S | Coverage Partial |
|---|---:|---:|---:|---:|---:|---:|
| Executive Command Center | 10 | 9 | 0 | 1 | 0 | 90% |
| POS & Checkout | 13 | 13 | 0 | 0 | 0 | 100% |
| Order Management | 10 | 10 | 0 | 0 | 0 | 100% |
| Kitchen & Production | 10 | 10 | 0 | 0 | 0 | 100% |
| Menu & Recipe | 11 | 11 | 0 | 0 | 0 | 100% |
| Inventory & Warehouse | 12 | 12 | 0 | 0 | 0 | 100% |
| Procurement & Supplier | 10 | 10 | 0 | 0 | 0 | 100% |
| Branch Operations | 10 | 10 | 0 | 0 | 0 | 100% |
| Delivery & Fulfillment | 8 | 8 | 0 | 0 | 0 | 100% |
| CRM & Loyalty | 9 | 9 | 0 | 0 | 0 | 100% |
| Finance & Accounting | 12 | 12 | 0 | 0 | 0 | 100% |
| HR & Workforce | 9 | 9 | 0 | 0 | 0 | 100% |
| Franchise & Expansion | 8 | 8 | 0 | 0 | 0 | 100% |
| BI & Analytics | 10 | 10 | 0 | 0 | 0 | 100% |
| Admin & Access Control | 10 | 10 | 0 | 0 | 0 | 100% |
| SaaS Tenant Management | 8 | 8 | 0 | 0 | 0 | 100% |
| Integrations & Automation | 9 | 9 | 0 | 0 | 0 | 100% |
| Quality, Compliance & Security | 20 | 20 | 0 | 0 | 0 | 100% |
| **TOTAL** | **189** | **188** | **0** | **1** | **0** | **99,5%** |

Keterangan: P = PARTIAL; BT = belum terbukti; B = BLOCKED; S = DONE. Cakupan Partial adalah jumlah fitur yang sudah mulai dikerjakan dibagi total domain, bukan persentase penyelesaian masing-masing fitur.

### Perubahan status pada batch implementasi 27 November

Seluruh **39 Feature ID** yang sebelumnya NOT VERIFIED kini memiliki artefak implementasi konkret, contract tests dan dokumentasi gap. Selain itu, empat fitur BLOCKED sudah memiliki remediation code/tests dan dipindahkan ke PARTIAL. Hanya Owner drill-down yang masih BLOCKED. Ini bukan DONE dan tidak menyatakan workflow sudah terintegrasi atau runtime accepted.

| Domain | Feature ID yang mulai dikerjakan |
|---|---|
| Executive Command Center | D01-F05, D01-F06 |
| POS & Checkout | D02-F05 |
| Order Management | D03-F02, D03-F08 |
| Kitchen & Production | D04-F02, D04-F08 |
| Menu & Recipe | D05-F05, D05-F07, D05-F08 |
| Inventory & Warehouse | D06-F05, D06-F10 |
| Procurement & Supplier | D07-F02, D07-F04, D07-F10 |
| Branch Operations | D08-F04, D08-F07, D08-F08, D08-F09, D08-F10 |
| CRM & Loyalty | D10-F06, D10-F08, D10-F09 |
| Finance & Accounting | D11-F09, D11-F10 |
| HR & Workforce | D12-F08, D12-F09 |
| BI & Analytics | D14-F07, D14-F09, D14-F10 |
| Admin & Access Control | D15-F06, D15-F07 |
| SaaS Tenant Management | D16-F06 |
| Integrations & Automation | D17-F03, D17-F07, D17-F09 |
| Quality, Compliance & Security | D18-F11, D18-F12, D18-F19 |

PR #153 masih Draft dan belum merged. Semua 39 fitur tetap memerlukan canonical database migration, RLS/Storage, concrete repository adapters, authenticated Edge Function, UI, staging E2E dan cross-domain reconciliation sebelum dapat dinilai 100%.

Satu fitur tetap BLOCKED:
- D01-F09 — Owner drill-down company→region→branch→shift→transaction. Masih menunggu verifikasi resmi Supabase Auth Admin untuk `app_metadata.platform_owner` dan kecocokan Owner UUID pada allowlist. Tidak boleh diedit melalui SQL atau dilewati dengan service-role bypass.

Empat blocker lainnya sudah dipindahkan ke PARTIAL setelah remediation code/test dimulai: D04-F10, D05-F11, D08-F03 dan D11-F03. Provider sandbox dan staging runtime tetap menjadi acceptance gap.


## 3. Bukti aktual GitHub, Supabase dan Vercel

### GitHub

- Candidate branch `feat/eight-domain-official-migrations-20261127` dibandingkan dengan `staging`: **525 commits ahead, 0 behind**, dengan 105 file berubah.
- Candidate berisi delapan official migration files yang dibangkitkan melalui Supabase CLI dari draft yang direview, plus pgTAP/contract test files.
- Candidate mencakup CRM/Loyalty, HR/Payroll/Finance, Delivery, Franchise, Procurement, BI, SaaS dan Executive. Migration set mengklaim 71 tabel baru lintas delapan domain.
- PR #152 exact head `3dda8d1...`: disposable migration replay PASS, seluruh 17 tabel CRM terverifikasi, pgTAP 17 file / 1.547 assertion PASS. Legacy overload `saas_record_usage` tetap direvoke dari semua API role, dikecualikan dari global service_role allowlist dan diuji eksplisit tidak dapat dieksekusi; plan count 12. Disposable database dihentikan dan dibuang.
- PR #143 tetap OPEN dan belum merge; PR #145 adalah Draft/orchestration candidate; PR #146 adalah payroll payout continuation. Tidak ada merge yang dilakukan dalam audit ini.

### Supabase staging

- Project `higoadrzxnhzbbwhdbmh` berstatus `ACTIVE_HEALTHY`.
- Database mencatat **63 applied migration versions**.
- `dlice-orders` ACTIVE versi 73; `verify_jwt=false`. Handler tetap harus memvalidasi bearer token, user, profile, tenant membership, branch scope dan Owner dual gate.
- Ada 68 public base tables; seluruh tabel yang diperiksa memiliki RLS enabled. Database mencatat 63 applied migration versions, terbaru `20261124134222_pos_checkout_fk_supporting_indexes`.
- Read-only schema query menemukan **0 tabel** dengan prefix `crm_`, `hr_`, `delivery_`, `franchise_`, `bi_`, `saas_`, atau `executive_`; tabel extension `supplier_tenant_links` dan `procurement_supplier_invoices` juga belum ada. Jadi migration kandidat delapan domain belum diterapkan ke staging.
- Ada satu active Owner profile, tetapi aggregate Auth query menunjukkan `raw_app_meta_data.platform_owner=true` berjumlah **0** dan jumlah user yang memiliki claim tersebut juga **0**. Secret allowlist `DLICE_PLATFORM_OWNER_USER_IDS` tidak dapat dibaca dari konektor ini. Owner authorization belum terverifikasi.

### Vercel

- Project `dlice-landing-page`.
- Free quality checks PR #153 exact head `be7ae30...`: PASS, termasuk seluruh contract suite tambahan dan remediation empat blocker. 43 fitur batch baru mendapat skor 33–38% dari rubrik berbobot.
- Disposable migration replay PR #153 exact head: sedang berjalan; PR #152 base replay sudah PASS.
- Vercel Preview untuk exact head terbaru terkena Free build rate limit (`build-rate-limit`); ini bukan hasil build aplikasi. Preview lama READY hanya membuktikan build saat itu, bukan workflow bisnis.
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

