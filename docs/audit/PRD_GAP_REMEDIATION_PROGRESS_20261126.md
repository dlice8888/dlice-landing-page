# PRD Gap Remediation Progress — 2026-11-26

## Audit boundary and status semantics

This is a **work-in-progress remediation ledger**, not a release certificate. The opening snapshot below is the latest 18-domain / 189-feature table explicitly supplied by the product owner in the 2026-11-26 work order. The repository's checked-in `docs/audit/FNB_OS_IMPLEMENTATION_MATRIX.json` on `staging` is timestamped 2026-11-24 and differs in two domains (Admin: 8/2 vs owner table 6/4; Quality: 12/8 vs owner table 11/9). The owner-supplied snapshot is preserved as the working baseline; the discrepancy must be reconciled feature-by-feature before this ledger is promoted to staging.

Definitions:
- **P / PARTIAL**: implementation work has started, but one or more acceptance dimensions remain unproven.
- **BT / NOT VERIFIED**: no qualifying implementation start or evidence is currently accepted.
- **B / BLOCKED**: a named external prerequisite prevents completion.
- **S / DONE**: workflow, codebase, database, authorization, integration and runtime evidence all pass. No new feature is marked DONE in this increment.
- Domain percentage shown in the table is `P / Total`, i.e. implementation-start coverage, **not** weighted completion of each PARTIAL feature.
- No feature becomes DONE merely because code was committed, tests passed, a PR exists, or Vercel says READY.

## Opening snapshot — owner supplied

| Domain | Total | P | BT | B | S | Partial coverage |
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
| **TOTAL** | **189** | **92** | **91** | **6** | **0** | **49%** |

## Closing snapshot — after this implementation increment

The eight-domain workflow PR (#145) starts work across CRM, HR/Finance, Delivery, Franchise, BI, SaaS, Procurement and Executive; PR #146 adds the payroll payout/provider boundary; PR #149 adds the 150-branch concurrency probe; PR #150 starts food safety/recall and supplier quality/CAPA. All newly started features remain PARTIAL. None is DONE.

| Domain | Total | P | BT | B | S | Partial coverage |
|---|---:|---:|---:|---:|---:|---:|
| Executive Command Center | 10 | 6 | 3 | 1 | 0 | 60% |
| POS & Checkout | 13 | 7 | 5 | 1 | 0 | 54% |
| Order Management | 10 | 8 | 2 | 0 | 0 | 80% |
| Kitchen & Production | 10 | 7 | 2 | 1 | 0 | 70% |
| Menu & Recipe | 11 | 7 | 3 | 1 | 0 | 64% |
| Inventory & Warehouse | 12 | 10 | 2 | 0 | 0 | 83% |
| Procurement & Supplier | 10 | 7 | 3 | 0 | 0 | 70% |
| Branch Operations | 10 | 4 | 5 | 1 | 0 | 40% |
| Delivery & Fulfillment | 8 | 8 | 0 | 0 | 0 | 100% |
| CRM & Loyalty | 9 | 4 | 5 | 0 | 0 | 44% |
| Finance & Accounting | 12 | 8 | 3 | 1 | 0 | 67% |
| HR & Workforce | 9 | 2 | 7 | 0 | 0 | 22% |
| Franchise & Expansion | 8 | 8 | 0 | 0 | 0 | 100% |
| BI & Analytics | 10 | 4 | 6 | 0 | 0 | 40% |
| Admin & Access Control | 10 | 6 | 4 | 0 | 0 | 60% |
| SaaS Tenant Management | 8 | 4 | 4 | 0 | 0 | 50% |
| Integrations & Automation | 9 | 7 | 2 | 0 | 0 | 78% |
| Quality, Compliance & Security | 20 | 14 | 6 | 0 | 0 | 70% |
| **TOTAL** | **189** | **121** | **62** | **6** | **0** | **64%** |

## Newly started features moved from NOT VERIFIED to PARTIAL

The following reclassifications are based on source orchestration, schema drafts and contract tests in PRs #145–#150. A source implementation counts as PARTIAL under the owner's rule, but does not imply deployed/runtime completion.

| Domain | Newly started PRD features | Evidence now present | Remaining acceptance gap | Estimated engineering progress |
|---|---|---|---|---:|
| Executive | Branch ranking; target vs actual | 1–150 branch ranking service, BI snapshot lineage and approved target requirements | Full source snapshots/targets, region rollups, browser drill-down and alert workflow | 30% |
| Procurement | Three-way match; AP handoff/supplier payment | Supplier invoice approval and balanced AP journal draft/payment+settlement orchestration | Concrete AP subledger adapters, invoice evidence intake, DB replay, provider settlement and staging reconciliation | 30% |
| Delivery | Address/quote; courier booking; dispatch/tracking; POD; retry/exception; fee vs actual cost | Quote/booking orchestration, signed webhook ingestion, private proof metadata/upload path, cost reconciliation and retry outbox schema | Provider approval/credentials, signed endpoint integration, Storage provisioning/policies, cancellation compensation and COD/bank E2E | 30% |
| CRM | Consent; loyalty points; campaign/ROI | Signed unsubscribe/consent withdrawal, reconciled-close loyalty award, provider-neutral campaign outbox/receipt/ROI orchestration | Supabase RPC adapters, provider contract/secrets, signed webhook route, source reconciliation, UI and campaign E2E | 30% |
| Finance | Automated journals from payroll | Canonical HR payroll-to-Finance draft journal and reconciliation source model | Exact disposable SQL replay, pgTAP, real payroll source, posting approval and bank evidence | 35% |
| HR | Payroll calculation/integration | Approved employee/time/pay inputs, payroll calculation, immutable run lines and Finance mapping workflow | Statutory/tax/benefit policies, provider dispatch, webhook, Finance clearing, bank statement and employee lifecycle E2E | 35% |
| Franchise | Application/due diligence; site feasibility; agreements; royalty; territory access; compliance | Ten due-diligence gates, site approval, agreement draft/approval/signature-reference/activation, royalty statement and tenant/territory checks | E-sign verification, operational provisioning, expiry/renewal, partner reporting, royalty invoice/payment and branch acceptance | 30% |
| BI | Official KPI dictionary/versioning | Published KPI formula/version and reconciled immutable snapshot ingestion | Scheduled workers, source completeness, freshness/anomaly alerting, cohort comparison, target authoring and report UI | 30% |
| SaaS Tenant | Plans/entitlements/quotas; billing/invoices/usage metering | Tenant entitlement enforcement and subscription invoice orchestration with committed-operation metering | Payment execution/receipts, quotas across every API route, grace/suspension, export/offboarding and tenant E2E | 30% |
| Integrations | Payment callback validation; external connectors | Xendit v3 webhook/payout adapter contract plus CRM/delivery provider adapter/outbox contracts | Real dev credentials, provider signature contract, callback endpoint runtime, retries and settlement reconciliation | 35% |
| Quality | Food safety/recall; supplier quality/CAPA; 150-branch concurrency | Inspection/quarantine/recall and CAPA orchestration with 8 contracts; local synthetic 150-branch RLS test with 50 concurrent clients | Concrete Supabase RPCs, SQL replay/pgTAP, two real Auth tenants on staging, Storage evidence and realistic app/API workload | 30% |

**Count arithmetic:** 29 newly started features move the owner-supplied baseline from 92 PARTIAL / 91 NOT VERIFIED to 121 PARTIAL / 62 NOT VERIFIED. BLOCKED remains 6; DONE remains 0. Partial coverage is 121/189 = 64%. This is not a weighted completion percentage. Legacy PARTIAL rows still require feature-level progress scoring; the older repository matrix marks them as unscored.

## Progress inside the two newly started PARTIAL features

Progress is an engineering-work estimate across required acceptance dimensions, not runtime completion.

| Feature | Source orchestration | Contract tests | Schema draft | Supabase adapters/RPC | Auth/API + UI | DB/RLS/ACL | Staging E2E + reconciliation | Estimated progress |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Food safety, temperature, allergens and recall | Done | Done | Draft | 0% | 0% | 0% | 0% | 30% |
| Supplier quality, quarantine and CAPA | Done | Done | Draft | 0% | 0% | 0% | 0% | 30% |

The 30% estimate reflects code orchestration, contract coverage and a reviewed schema draft. It does not mean the feature is usable in staging.

## Detailed gaps and completion work

### 1. Quality, Compliance & Security — food safety / recall
Implemented in PR #150:
- tenant/branch-scoped orchestration with required authorization and transaction adapters;
- approved-policy requirement; no hard-coded universal temperature threshold;
- temperature and allergen checks; fail-closed quarantine when out of policy;
- lot recall flow that requires server-derived affected branch/order lineage;
- idempotency and audit append requirements;
- 8 contract tests cover compliant inspection, quarantine, unapproved policy, recall traceability, supplier quarantine/CAPA, cross-tenant policy mismatch, independent reviewer, and quarantine release.

Still required:
1. Align SQL draft against actual staging table keys and tenant/branch lineage; include immutable event triggers and append-only permissions.
2. Build concrete Supabase repository/RPC adapters using tenant-scoped SQL and approved effective-dated policy selection.
3. Add authenticated Edge Function action routes and central permission mapping; negative tests for anonymous, invalid token, wrong tenant, wrong branch, inactive user and unauthorized role.
4. Build policy creation/approval, inspection capture, quarantine, recall, affected-order trace, acknowledgement and closure UI.
5. Store inspection photos/certificates in a private Storage bucket with tenant/branch path checks, signed access, retention and audit.
6. Test atomicity: if inspection/recall/audit/quarantine fails, all writes roll back; test retries and duplicate idempotency keys.
7. Run disposable migration replay + pgTAP, RLS/ACL and two-tenant/two-branch negative tests.
8. Run staging E2E: GRN or production lot → inspection → quarantine → recall impact → branch acknowledgement → disposal/return/release → stock ledger and audit reconciliation.

### 2. Quality, Compliance & Security — supplier quality / CAPA
Implemented in PR #150:
- inspection against approved supplier-specific policy;
- major/critical finding quarantine and mandatory CAPA creation;
- independent verification (creator/submitter cannot verify own action);
- release is conditional on verified CAPA and explicit repository confirmation.

Still required:
1. Verify supplier/receipt/item identity and tenant/branch linkage in the database, not only in caller context.
2. Persist findings and evidence references immutably; validate private Storage object ownership.
3. Add CAPA lifecycle and state-transition constraints (open → in progress → submitted → verified/rejected → closed).
4. Require root cause, corrective action, preventive action, due date, supplier response and evidence before submission.
5. Link quarantine quantities to GRN and stock ledger so quarantined quantities are unavailable to POS/production/transfer.
6. Add supplier scorecard metrics from verified receipt/inspection/return outcomes.
7. Add authenticated UI, notification/escalation and independent approver permissions.
8. Run GRN → inspection → quarantine → CAPA response → independent verification → stock release/return → AP hold/release reconciliation E2E.

### 3. Next domains by largest unverified count (owner opening baseline)
| Priority | Domain | Not verified | Work that must be started |
|---:|---|---:|---|
| 1 | CRM & Loyalty | 8/9 | Consent lifecycle, customer identity dedupe, points ledger/expiry/reversal, vouchers, referral fraud controls, campaign attribution, support SLA, LTV |
| 2 | HR & Workforce | 8/9 | Employee lifecycle, attendance, scheduling/swaps, leave/overtime, payroll calculation/provider clearing, labor allocation, training, onboarding/offboarding |
| 3 | Delivery & Fulfillment | 6/8 | Address validation/quote, courier dispatch/tracking, POD, cancellation/retry/compensation, fee vs actual cost, notification E2E |
| 4 | Franchise & Expansion | 6/8 | Application/due diligence, site feasibility, opening project, agreements/renewal, royalty ledger/settlement, territory access, compliance |
| 5 | BI & Analytics | 7/10 | KPI dictionary/versioning, cost/waste formulas, cohorts, forecast accuracy, data quality/anomalies, exports/schedules, alert-to-outcome |
| 6 | SaaS Tenant Management | 6/8 | Entitlements/quotas, subscription billing/metering, suspension/grace, support access, export/offboarding, multiple organizations |
| 7 | Procurement & Supplier | 5/10 | Price/contracts, demand consolidation, 3-way match, AP/payment, supplier return and scorecard |
| 8 | Executive Command Center | 5/10 | 150-branch ranking, stock/anomaly alerts, target vs actual, executive reports, role-aware drill-down and action closure |

### 4. Cross-domain acceptance gates
- Codebase: static checks, contract tests, type checks, no duplicate or conflicting migrations, exact-head CI.
- Database: disposable full migration replay, pgTAP, constraints, RLS, grants/revokes, function ACL, idempotency and append-only evidence.
- Security: tenant A/B read/write denial, branch isolation, auth-negative coverage, Storage/cache/background job boundaries.
- Workflow: positive, negative, retry, timeout, compensation and concurrent execution paths.
- Reconciliation: source-to-ledger-to-settlement-to-bank or stock/GL totals balance.
- Runtime: staging API + browser E2E, actual branch/role accounts, captured evidence and no skipped/blocked assertions.
- Release: explicit owner approval; keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false` until separate release acceptance.

## External audit observations — 2026-11-26
- Supabase staging project is ACTIVE_HEALTHY. Its migration history currently ends at POS checkout migrations `20261124134101` and `20261124134222`; no HR/payroll/Xendit/Quality schema migrations are applied. No development branch exists. No staging SQL was changed in this audit.
- Supabase security advisor currently reports leaked-password protection disabled (one warning). Performance advisor reports 83 unused-index notices; these are informational candidates, not automatic drop instructions. Health advisor returned no lints.
- Vercel project has SSO protection enabled for preview deployments. Latest deployment inspected is READY for the 150-branch QA probe branch at commit `f16c96e`; this is not a staging release or proof of application E2E. Existing payroll preview deployments are older commits and not exact-head runtime acceptance.
- PR #150 free quality checks pass on latest audit-ledger head `54ed6c9a73cce280c30c73da14e55a0b65aa129b` (run `45667743378`). Its Quality orchestration tests passed on code commit `624fd20f2649d34028daa94dfa16fa81fa3223c2`; DB replay, pgTAP, authenticated Edge Function, browser and staging E2E remain pending.
- PR #149 exact head `8994c2ef3576c1982b83d9b6bd87ee35e2aad702`: Free quality checks and PostgreSQL concurrency probe both PASS (runs `45667246991` and `45667247057`). Synthetic Tenant A 150 branches / Tenant B 1 branch: 50 concurrent clients, four workers, 10 seconds per tenant; average latency 3.273 ms / 15,278.60 TPS for A and 2.960 ms / 16,891.71 TPS for B. This is a local read/RLS drill, not a full application benchmark or p95/p99/SLO certification.
- PR #146 disposable DB run `45659462961` on the earlier head completed local stack startup and canonical migration reset, then replayed HR workforce, HR payroll/Finance and payment-adapter drafts. The final Finance-clearing draft failed at the immutable evidence trigger because one PL/pgSQL dollar delimiter was malformed. Fixed in commit `505887940e8deb7e6808f1715ed0dbefbb9ef880`; workflow concurrency was changed to avoid cancellation and a push trigger was added so the corrected exact candidate can run without merging. No corrected replay/pgTAP pass is yet evidenced.

## No-release statement
All work in this increment is draft/PR-only. No Production changes, no shared staging migration, no Xendit network request or payout, no bank transfer, no merge, and no release-flag change occurred.


## Reconciliation hold — conflicting active audit snapshots

The closing snapshot above is a **working reclassification based on the owner-supplied 92 PARTIAL / 91 NOT VERIFIED baseline**, not yet the consolidated repository-wide total. A separate open audit PR #147 reports 134 PARTIAL / 49 NOT VERIFIED / 6 BLOCKED / 0 DONE for the same 189-feature scope. These totals differ by 13 features and cannot both be the canonical current count. The 18-domain arithmetic in this document is internally consistent (121 + 62 + 6 = 189), but that arithmetic alone does not resolve the feature-level discrepancy.

Before publishing one canonical total, reconcile each of the 189 stable PRD feature IDs across the owner matrix, `docs/audit/FNB_OS_IMPLEMENTATION_MATRIX.json`, PR #147, and implementation PRs #143–#150. Deduplicate features started in stacked PRs; count a feature once even if several PRs touch it. Preserve the six named BLOCKED gates unless their external prerequisite is demonstrably cleared. Do not convert any PARTIAL to DONE based only on a PR or CI pass. Until that reconciliation is committed, report both snapshots and label the consolidated total **UNRESOLVED**, rather than silently selecting 121 or 134.

The exact-head PR #149 evidence is now verified: commit `8994c2ef3576c1982b83d9b6bd87ee35e2aad702` has successful Free quality checks (run `45667246991`) and PostgreSQL concurrency probe (run `45667247057`). This changes evidence for the 150-branch synthetic RLS-read probe only; it does not change the feature to DONE or resolve the 13-feature ledger discrepancy.
