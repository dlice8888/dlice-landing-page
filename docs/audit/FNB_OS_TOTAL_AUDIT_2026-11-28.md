# D’Lice FnB OS — Total PRD Audit & Remediation Update

**Audit timestamp:** 2026-11-28 (Asia/Jakarta)  
**Repository:** dlice8888/dlice-landing-page  
**Candidate PR:** #153 — OPEN / DRAFT / NOT MERGED  
**Candidate branch:** feat/branch-ops-evidence-workflows-20261127  
**Candidate head at audit:** 3e8314fb232168981d16969051ba77176f09b39c  
**Supabase staging:** dlice-staging / higoadrzxnhzbbwhdbmh  
**Vercel project:** dlice-landing-page

## 1. Canonical status after the 2026-11-27 implementation-start batch

| Status | Count | Interpretation |
|---|---:|---|
| PARTIAL | 188 | Implementation has started with traceable artifacts; not accepted end-to-end |
| NOT VERIFIED | 0 | All 39 features from the user-provided baseline have implementation-start artifacts |
| BLOCKED | 1 | D01-F09 Owner drill-down awaits official Auth Admin + allowlist proof |
| DONE | 0 | No feature has passed all six acceptance dimensions |
| **TOTAL** | **189** | **18 domains** |

Coverage PARTIAL is 188/189 = 99.47%. This is implementation-start coverage, not weighted completion or production readiness.

## 2. Updated 18-domain status matrix

| Domain | Total | Partial | Not verified | Blocked |
|---|---:|---:|---:|---:|
| Executive Command Center | 10 | 9 | 0 | 1 |
| POS & Checkout | 13 | 13 | 0 | 0 |
| Order Management | 10 | 10 | 0 | 0 |
| Kitchen & Production | 10 | 10 | 0 | 0 |
| Menu, Recipe & Product Engineering | 11 | 11 | 0 | 0 |
| Inventory & Warehouse | 12 | 12 | 0 | 0 |
| Procurement & Supplier | 10 | 10 | 0 | 0 |
| Branch Operations | 10 | 10 | 0 | 0 |
| Delivery & Fulfillment | 8 | 8 | 0 | 0 |
| CRM, Loyalty & Marketing | 9 | 9 | 0 | 0 |
| Finance & Accounting | 12 | 12 | 0 | 0 |
| HR & Workforce | 9 | 9 | 0 | 0 |
| Franchise & Expansion | 8 | 8 | 0 | 0 |
| BI & Analytics | 10 | 10 | 0 | 0 |
| Admin, Identity & Access Control | 10 | 10 | 0 | 0 |
| SaaS Tenant Management | 8 | 8 | 0 | 0 |
| Integrations & Automation | 9 | 9 | 0 | 0 |
| Quality, Compliance & Security | 20 | 20 | 0 | 0 |
| **TOTAL** | **189** | **188** | **0** | **1** |

## 3. Weighted progress and evidence quality

- 50 PARTIAL features have numeric weighted scores.
- 138 PARTIAL features remain UNSCORED pending feature-level six-dimension evidence decomposition.
- The 43 newest implementation-start features are reported at 33–38%.
- The 50 scored features have an aggregate average near 40%; this is not the average of all 188 PARTIAL features and must not be presented as overall completion.
- Weights: Code/UI 20%, Database 20%, Authorization 15%, Automated tests 15%, Workflow E2E 20%, Reconciliation/observability 10%.
- DONE requires 100%, with all six dimensions PASS and no blocked/skipped/unrun acceptance.

## 4. Fresh live-system evidence

### GitHub

- Repository exists and is accessible: dlice8888/dlice-landing-page.
- PR #153 is OPEN, DRAFT, not merged; head SHA: 3e8314fb232168981d16969051ba77176f09b39c.
- PR #153 includes the updated 189-feature matrix, evidence ledger, audit report, implementation notes, workflow source modules and contract tests.
- Exact-head workflow lookup returned successful runs for Free quality checks and Free CRM disposable database replay.
- PR #152 remains OPEN/DRAFT/not merged. Its PR description reports disposable replay, 17 pgTAP files and 1,547 assertions PASS; this is candidate evidence, not staging migration evidence.

### Supabase staging

- Project dlice-staging is ACTIVE_HEALTHY; PostgreSQL 17.11.
- 68 public base tables were listed; all 68 have RLS enabled.
- Read-only aggregate: 0 public tables matching the candidate domain extension prefixes/names (crm_, hr_, delivery_, franchise_, bi_, saas_, executive_, supplier_tenant_links, procurement_supplier_invoices).
- 63 applied migrations; latest version 20261124134222.
- 49 public functions.
- Edge Function dlice-orders is ACTIVE, version 73, verify_jwt=false. Its source manually validates bearer tokens with Auth getUser, checks active admin profile, and requires both UUID allowlist membership and app_metadata.platform_owner === true for Owner elevation. This manual path still requires positive/negative runtime tests across all protected actions.
- Read-only Auth aggregate: 0 users with raw_app_meta_data.platform_owner=true; 0 users with any platform_owner claim. The allowlist secret value cannot be independently inspected through this read-only evidence. D01-F09 remains BLOCKED.
- Security Advisor: one WARN — leaked password protection disabled.
- Performance Advisor: 82 INFO findings for unused indexes. These are candidates for workload review, not automatic deletion instructions.

### Vercel

- Project dlice-landing-page is connected to the expected GitHub repository.
- Recent Preview deployments are READY, but the newest observed deployment SHA is 7322d765c6772469783ab98c7d0cd8fbae174fd8, not PR #153 head 3e8314fb232168981d16969051ba77176f09b39c.
- No Preview for the exact PR #153 head was found in the branch-filtered recent deployment results. READY previews for older commits do not prove current business workflows.

## 5. Existing POS staging reconciliation evidence and gaps

Previously audited staging snapshot:
- 6 POS sales totaling Rp600; 6 sale-item rows totaling Rp600.
- Tender allocation: 0 rows / Rp0.
- Immutable receipts: 0.
- KDS tickets: 6, but lifecycle not proven.
- Stock movements: 26, not reconciled per sale/order/recipe/item/quantity.
- Stock transfers: 0.
- Closed shifts: 7; cash expected Rp600, counted Rp600, variance Rp0, but only aggregate evidence.

Therefore POS E2E is not accepted. Required: per-sale tender split, payment status, cash drawer delta, shift close, stock movement and recipe consumption, KDS state transitions, immutable receipt snapshot and audit-event linkage. Add split tender, duplicate/idempotent checkout, held/resume, offline replay, failed payment, refund/void and network-fault scenarios.

## 6. Detailed remaining gap register

### D01 Executive Command Center — D01-F09 BLOCKED
- Owner drill-down remains blocked until the correct Owner account has app_metadata.platform_owner as a JSON boolean true and the same user UUID is present in the server-side DLICE_PLATFORM_OWNER_USER_IDS allowlist.
- Use official Supabase Auth Admin only; preserve other metadata; no SQL Auth metadata mutation.
- Then prove company → region → branch → shift → transaction drill-down with tenant/branch authorization and source reconciliation.
- Remaining work for other Executive features: canonical POS/Finance/Inventory/KDS source collectors, KPI formula/version and business-date cutoffs, branch rankings, alert assignment/resolution/audit lifecycle, schedules and 150-branch completeness.

### D02 POS & Checkout
- Link sale, sale items, tender allocations, payment provider references, cash drawer and shift close atomically.
- Add split tender, idempotency, offline sync, held/resume, payment failure compensation, refund/void and device/browser E2E.
- Persist immutable receipt snapshots and verify receipt-to-sale-to-tender hashes/references.
- Reconcile every sale against stock movement, recipe version/consumption, KDS ticket lifecycle and audit events.

### D03 Order Management
- Prove external channel ingestion with signed webhook, replay protection, idempotency and tenant/branch mapping.
- Link order edits/cancellation/refunds to POS, capacity reservation, KDS, inventory and Finance.
- Verify SLA/ETA calculation from authoritative event timestamps and complete transition history.

### D04 Kitchen & Production
- Prove station routing and ticket transitions from accepted through prepared/ready/served/cancelled.
- Link KDS ticket items to immutable POS/order item and recipe version.
- Reconcile theoretical BOM consumption against actual production consumption and stock movements.
- Enforce allergen controls, temperature/shelf-life quarantine and evidence retention.

### D05 Menu, Recipe & Product Engineering
- Convert draft BOM/recipe behavior into canonical schema/RPC and UI.
- Enforce effective-dated immutable recipe versions, UOM conversions, yield/prep loss, serving cost and allergen declarations.
- Verify POS and production consume the exact approved recipe version.
- Reconcile ingredient cost and actual stock consumption.

### D06 Inventory & Warehouse
- Prove FIFO/FEFO lot allocation, expiry and historical valuation using actual movements.
- Complete transfer lifecycle Draft → Approved → Picked → Shipped → Received → Reconciled with independent approval and branch isolation.
- Link production/POS/order consumption, waste, stock counts and valuation to immutable movement references.
- Validate concurrent reservations and idempotent movement posting.

### D07 Procurement & Supplier
- Enforce tenant-owned supplier relationship and supplier approval; no accidental cross-tenant supplier visibility.
- Complete requisition → approval → PO → GRN/inspection → invoice three-way match.
- Link returns/credit notes, AP journal, supplier payment/settlement and supplier scorecard.
- Reconcile PO, accepted quantities, invoice, AP ledger, bank settlement and Finance journal.

### D08 Branch Operations
- Current source modules define task, incident, maintenance and compliance workflows with tenant transaction, authorization, idempotency and audit adapter contracts.
- Concrete database adapters, canonical schema/RPC, private Storage ownership verification, UI routes and authenticated staging E2E remain unproven.
- Verify same-branch assignee and equipment, critical-incident escalation, evidence object ownership/retention, independent compliance approval and immutable compliance snapshots.
- Complete opening/closing checklist, handover, escalation, maintenance lifecycle, incident resolution and audit trail.

### D09 Delivery & Fulfillment
- Validate address and quote through an approved provider contract.
- Persist booking/provider reference/tracking with transactional outbox and idempotent worker.
- Verify webhook signature over raw body, timestamp, replay window and duplicate event.
- Prove private proof-of-delivery Storage ownership, MIME/size/hash and tenant/branch access.
- Add retry/backoff/dead-letter, cancellation/compensation, customer notification, COD and Finance fee/subsidy/courier-cost reconciliation.
- Do not claim Biteship is live without approved credentials and contract tests.

### D10 CRM, Loyalty & Marketing
- Canonical customer identity and deduplication across POS and online orders.
- Append-only per-purpose/per-channel consent with revocation before campaign dispatch.
- Earn points only from reconciled net sales after settlement/cash close and Finance reconciliation.
- Atomic idempotent redemption, nonnegative balance, lot expiry/FIFO and one-time reversal.
- Campaign provider contract, signed receipt, unsubscribe, retries/dead-letter, attribution/ROI, referral and support SLA.
- Customer LTV and segments must use deduplicated, reconciled transactions.

### D11 Finance & Accounting
- Canonical balanced journal entries with open fiscal period, source references and independent approval.
- Reconcile sale/tender, refunds, settlement/provider fees, bank statement and cash drawer per transaction.
- HR payroll must post to Finance only from approved immutable payroll snapshots.
- Validate intercompany eliminations, branch budgets, revenue-vs-cash and period close/reopen audit.
- Provider payouts remain unaccepted until signed callbacks and bank reconciliation pass.

### D12 HR & Workforce
- Employee lifecycle, effective-dated position/branch transfer, attendance, timesheet, scheduling, leave, overtime and offboarding.
- Compensation policies must be approved and effective-dated; statutory rates must come from verified policy sources.
- Payroll recalculation from approved snapshots, independent approval, idempotency and balanced Finance journal.
- Provider payout/beneficiary contract, signed callback and bank reconciliation remain required.
- Complete recruitment, onboarding, training certification and performance review workflow.

### D13 Franchise & Expansion
- Application, due diligence, site feasibility, agreement versioning, independent approval and signature evidence.
- Atomic tenant/branch provisioning with server-resolved tenant identity.
- Opening activation only after every required evidence gate passes with independent verifier.
- Royalty calculation only from reconciled eligible net sales, followed by invoice/payment/settlement.
- Ongoing compliance audit, corrective action and franchise performance reporting.

### D14 BI & Analytics
- Each KPI requires owner, unit, formula version, source entities, freshness SLA and lineage.
- Source ingestion needs watermarks, expected/observed counts and reconciliation review.
- Food cost links theoretical recipe usage to actual stock consumption; labor cost to approved payroll; waste to posted waste events.
- Forecast accuracy, anomaly detection, exports, schedules and action-outcome loop.
- 150-branch cohort benchmarks require active branch completeness and reconciled facts.

### D15 Admin, Identity & Access Control
- Complete action-by-action authorization inventory and positive/negative tests.
- Validate Auth metadata, allowlist, role/membership intersection, branch assignment and session revocation.
- Device/session review, permission-change audit, recovery and JIT support require independent approval and immutable audit.
- No user_metadata authorization, service-role exposure or client-controlled tenant ID.

### D16 SaaS Tenant Management
- Versioned plan/entitlements/quotas, committed usage metering and invoice lifecycle.
- Payment settlement only from verified provider callbacks; dunning, proration and reactivation guards.
- Offboarding, legal hold, export/deletion executor and retention evidence.
- Support access requires tenant-owner approval, least privilege, time bound and read-only JIT evidence.
- Tenant isolation and API-wide enforcement must pass two-tenant A/B positive/negative E2E.

### D17 Integrations & Automation
- Provider-specific approved contracts, secret references/rotation and no credential disclosure.
- Signed callbacks, durable outbox, retry/backoff/dead-letter and replay protection.
- Health monitoring, authoritative alerts, catalog sync and import conflict resolution.
- Prove each integration with provider sandbox and staging runtime, not mocks alone.

### D18 Quality, Compliance & Security
- Complete RLS, RPC ACL, Storage policy and Edge Function action authorization tests.
- Backup/restore evidence must distinguish local disposable rehearsal from managed Supabase PITR and Auth/Storage recovery.
- Verify 150-branch load, tenant A/B isolation, concurrency, latency and recovery objectives.
- Accessibility, release pilot/rollback gates, audit retention, incident response and compliance evidence.
- Review 82 unused-index INFO findings against actual query plans before any index removal; enable leaked-password protection through approved Auth configuration after impact review.

## 7. Execution order

1. Resolve Owner Auth/allowlist blocker using official Auth Admin and explicit Owner approval.
2. Finish Branch Operations concrete adapter/schema/RPC/UI/evidence workflow work.
3. Finish CRM/loyalty and HR/payroll integration to POS/Order/Refund/Settlement/Finance.
4. Complete Delivery, Procurement, Franchise, BI, SaaS, Executive and Integration workflows.
5. Reconcile POS, KDS, Inventory, Finance, immutable receipts and audit events.
6. Update feature-level evidence scores after each batch; keep unscored values null rather than guessing.
7. At the final validation stage only: exact-head CI, disposable migration replay, pgTAP/ACL/RLS/Storage, tenant A/B E2E, browser/device acceptance, provider tests, 150-branch load, merge review and approved staging migration.

## 8. Guardrails

- Staging/disposable only. Production read-only.
- Keep TENANT_ISOLATION_RELEASED=false and PUBLIC_TENANT_ROUTING_RELEASED=false.
- No auto-merge, force push, production deployment, production secret/environment/data change.
- No SQL mutation of Auth metadata.
- No service-role key in browser or logs.
- No DONE based only on PR, source file, contract test, migration file, or READY Preview.
- Migration candidate files are not evidence that staging schema has changed.


## 9. Remediation work after this audit snapshot

- Added an explicit `verifyPrivateEvidenceOwnership` adapter gate to Branch Operations incident and compliance workflows.
- Evidence references are now checked in the tenant transaction with tenant ID, branch ID, actor ID, purpose, private-storage requirement and retention requirement before incident or compliance snapshot persistence.
- Compliance snapshot persistence now receives the verified evidence references, rather than only a source revision and score.
- Added a negative contract test proving that unverified evidence is rejected before persistence, and strengthened the success contracts to assert tenant/branch-scoped evidence verification.
- Source commit: `05f4411a705037fadff76d561e12fa4ec775e33d`.
- Contract-test commit / current PR #153 head at last check: `c4c4825934aa52ca898a5ec2efcfc5e24c63c7c2`.
- Vercel deployment for the current head reached READY; combined commit status reports Vercel success. This proves build/deployment only.
- No GitHub Actions run for the latest head was returned at the time of this check. Therefore the new contract tests are added but their exact-head execution remains unverified; no progress percentage or DONE promotion is awarded.
- Branch Operations still lacks a concrete Supabase repository adapter, canonical persisted schema/RPC, application UI wiring, private Storage policy/object verification implementation, and authenticated staging workflow E2E. The new adapter gate is a fail-closed contract, not proof those integrations exist.
- The domain matrix remains 188 PARTIAL / 0 NOT VERIFIED / 1 BLOCKED / 0 DONE until additional exact evidence changes feature-level scores.


## 10. Live continuation checkpoint — 2026-11-28

- Rechecked PR #153 exact head `d9f2dccdc8c5879c6b8160318e78a1f0a05c5086`.
- GitHub Free quality checks: **PASS** (run 46088159549).
- GitHub Free CRM disposable database replay: **IN_PROGRESS** at checkpoint (run 46088159533). No PASS claim until the run completes.
- GitHub combined status currently reports Vercel success. This is deployment/build status only.
- Supabase staging remains ACTIVE_HEALTHY (PostgreSQL 17.11). Read-only schema inspection confirms `tenants` and `branches` have `tenant_id` scope, and direct client access is denied by existing RLS policies. `admin_profiles` is service-role-only.
- No staging DDL, data, Auth metadata, Storage policy, Edge Function deployment, or production change was performed in this checkpoint.
- The branch operations source still contains orchestration ports and a fail-closed evidence ownership gate, but no concrete database repository adapter, canonical Branch Ops persistence migration/RPC, application UI route, or authenticated runtime E2E has been added/verified. These remain open implementation work, not accepted features.
- CRM and HR source workflows remain candidate orchestration modules; their canonical migrations exist in the PR base/candidate history, but staging table existence and cross-domain runtime reconciliation are not proven by this checkpoint.
- Feature status and numeric progress are unchanged: 188 PARTIAL / 0 NOT VERIFIED / 1 BLOCKED / 0 DONE. No feature score is increased by this checkpoint. The 138 unscored PARTIAL features remain unscored.
- Next implementation batch: add Branch Ops canonical schema + server-only persistence adapter + private Storage metadata verifier + authenticated UI/Edge routes; then integrate CRM ledger events with reconciled POS/order/refund/settlement/Finance sources and HR approved payroll snapshots with balanced Finance journals. These changes must remain candidate-only until final validation.
- Final merge and staging migration remain explicitly deferred pending user approval after exact-head CI, disposable replay, pgTAP, RLS/ACL/Storage, tenant A/B, provider, browser/device E2E and reconciliation.


## 11. Branch Operations concrete persistence/API/UI batch — 2026-11-28

Candidate branch `feat/branch-ops-evidence-workflows-20261127`, PR #153, now includes:

1. **Persistence schema draft** — `docs/implementation/sql/BRANCH_OPERATIONS_CONCRETE_PERSISTENCE_DRAFT.sql`
   - Seven tenant/branch-keyed tables: equipment, tasks, evidence assets, incidents, work orders, compliance checks and compliance snapshots.
   - Composite FKs to `branches(tenant_id,id)`, idempotency constraints, state constraints and RLS enabled on every new table.
   - No anon/authenticated table grants. Mutation RPCs have PUBLIC/anon/authenticated execute revoked and service_role execute granted.
   - Private `branch-ops-evidence` bucket, 8 MiB file limit, JPG/PNG/PDF allowlist. No direct browser Storage policies: upload is server-only after auth and branch authorization.
   - 13 PostgreSQL functions with balanced dollar delimiters: actor/approver assertions, equipment registration, task create/status, incident create/status, maintenance create/status, evidence registration, compliance submit/review/publish.
   - Each mutation writes `admin_audit_logs` in the same database transaction. Compliance review and publication require approver authority; submitter cannot self-approve.

2. **Server adapter and Edge API**
   - `supabase/functions/_shared/branch-operations-repository.ts` calls one atomic RPC per mutation and tenant/branch-filters reads.
   - `supabase/functions/branch-operations/index.ts` verifies bearer token with Auth `getUser`, active admin profile, active tenant membership, active branch and branch assignment or tenant-admin/manager permission before using service-role access.
   - Evidence upload is server-side only, checks actual file signature and MIME, caps at 8 MiB, uses a private bucket and registers actor/tenant/branch/purpose/retention metadata.
   - Intended deployment configuration: `verify_jwt=true`; function has not been deployed.

3. **ERP UI**
   - `src/branch-operations-ui.mjs` implements task, incident/evidence, equipment, maintenance, compliance submission/review and snapshot screens.
   - `erp.html` imports and mounts this UI in Operations view.
   - `BRANCH_OPS_WORKFLOWS_RELEASED=false` remains enforced, so users cannot invoke an un-deployed Edge Function or missing schema.

4. **Tests and CI**
   - Added repository adapter tests and SQL/Auth/Storage/UI static contract tests.
   - Added CI steps for Node syntax, adapter tests, SQL contract tests and Deno type-check of the new Edge Function.
   - At latest reviewed head `a3172ede17ba709bbfd683641a1c9015ac9f6259`, GitHub connector returned no associated exact-head workflow run. Vercel status is failure due the existing Free daily deployment limit, not an application test result. Therefore no test PASS is claimed for this batch.

### Acceptance status and remaining work

- SQL remains a **candidate draft**, not a CLI-generated official migration. The official migration must be created with Supabase CLI after code review.
- The live staging schema still does not contain the new `branch_ops_*` tables/functions. No DDL or data was applied.
- New Edge Function has not been deployed; `dlice-orders` version 73 was not modified.
- ERP mount is intentionally disabled behind the false release flag.
- No authenticated staging test, tenant A/B cross-read/write denial, Storage object ownership/retention test, browser/device E2E or workflow reconciliation has run.
- D08-F04/F07/F08/F09/F10 weighted progress scores remain unchanged (33% each where previously scored). Database, runtime and E2E dimensions remain unverified. This batch adds implementation source but does not justify DONE.
- PR #153 remains Draft/unmerged. Production remains read-only. `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false` remain unchanged.


## 12. Exact-head Branch Operations quality result

- Exact head tested: `01255157a504800612982e908e11b1c9061a822f`.
- Free quality checks run `46089862837`: **PASS**.
- Branch Operations evidence workflow contracts, browser UI/repository syntax, Supabase repository tests, SQL/Auth/Storage/UI static contracts, and Deno type-check of the authenticated Edge Function all completed successfully.
- Existing global quality checks, feature matrix consistency, tenant/release contracts and migration/documentation coverage also passed in that run.
- Disposable CRM migration replay run `46089862887` was still pending at the latest check. It is a disposable replay of the existing official candidate migration set; it does not apply the new Branch Operations SQL draft and does not mutate staging.
- Matrix automated-test evidence for D08-F04/F07/F08/F09/F10 now references the exact-head run. Weighted scores remain unchanged because database migration, live authorization, E2E and reconciliation dimensions remain unverified.
- Matrix refresh itself creates a newer documentation-only head and will need its own CI run before the refreshed exact head is considered fully validated.


## 13. Evidence access and lifecycle extension

- Added scoped evidence metadata lookup in the server repository and a signed-download action in the Edge Function. It creates a **60-second signed URL** only after the requester's Auth/tenant/branch authorization and a matching, unexpired evidence metadata row.
- Incident UI now exposes links to its evidence assets without making the bucket public or exposing a service-role key.
- Added approver-only equipment registration and compliance review/publication gates; assignees can advance their own tasks/work orders while other transitions require an approver. Incident state transitions require approver authority.
- Latest candidate commit before this documentation refresh: `02a072bb99ffdba131e0aa1e3384c17e19316dbc`. Free quality-check steps 1–58, including Branch Ops adapter, SQL/Auth/Storage/UI contracts and Deno Edge Function type-check, all reported PASS; the final post-job cleanup was still running when checked.
- CRM disposable replay run `46090021604` was still pending. It does not apply Branch Operations draft SQL or modify staging.
- Branch Ops remains PARTIAL, not DONE: official CLI migration, replay of the new SQL, staging deployment, authenticated tenant A/B/Storage E2E and browser/device acceptance remain outstanding. Progress scores unchanged.


## 11. Implementation batch — Branch Operations, CRM/Loyalty and HR/Payroll (2026-11-28)

### Exact implementation validation

Implementation code head: `c9a3065bf3fec94e961538167b60cd0e58b9f19a`.

- Free quality checks: **PASS** — run [46093311446](https://github.com/dlice8888/dlice-landing-page/actions/runs/46093311446). Includes contract suites, ERP Edge Function type-check and authenticated action-probe inventory updated to 233 actions.
- Canonical migration replay on disposable Supabase: **PASS** — run [46093311274](https://github.com/dlice8888/dlice-landing-page/actions/runs/46093311274).
- Canonical CRM schema verification: **PASS** in that disposable environment.
- CRM, HR and eight-domain pgTAP workflow contracts: **PASS** in that disposable environment.
- The disposable environment was stopped/discarded. No shared staging or production database was changed.
- Subsequent PR #153 commits `5cd77aa` and `d54f93c` update only the audit matrix and evidence ledger; no application code or migration changed after the validated implementation head.

### Branch Operations — concrete source delivered, migration still held

Implemented candidate source:
- SQL schema/RPC draft: `docs/implementation/sql/BRANCH_OPERATIONS_CONCRETE_PERSISTENCE_DRAFT.sql`.
- Repository adapters: `src/branch-operations-supabase-repository.mjs` and `supabase/functions/_shared/branch-operations-repository.ts`.
- Authenticated Edge API: `supabase/functions/branch-operations/index.ts`.
- UI: `src/branch-operations-ui.mjs`, mounted from `erp.html`.
- Contracts: workflow, adapter, persistence SQL, UI, Storage and Deno Edge checks.

Implemented source paths cover task creation/escalation, incidents, equipment, maintenance work orders (including private evidence IDs), compliance check submission/review/snapshot, private evidence upload and short-lived signed download. Storage upload now compensates failed metadata registration without deleting an object if the metadata RPC may have committed. Compliance source revision is derived from approved check/evidence rows; evidence metadata and published snapshots are append-only.

**Still not accepted:** the Branch Operations SQL is a draft, not a canonical `supabase/migrations` file. It has not been replayed, applied to staging, or tested against live Storage. The UI release flag remains false. Tenant A/B, branch A/B, signed upload/download, browser/device and cross-domain maintenance-cost E2E remain open. Retention metadata is set to 365 days, but automated purge scheduling is not implemented.

### CRM/Loyalty ↔ POS, Order, Refund, Settlement and Finance

- Paid POS/online order identity is linked to tenant CRM customer records.
- POS split tender now validates sale tender total, cash portion against approved shift drawer, and each bank/QRIS portion against provider settlement items by method.
- Reconciliation rechecks both the cash and provider settlement dimensions and Finance journal state.
- Loyalty points are awarded only from reconciled net sales.
- A later processed refund creates an immutable negative loyalty adjustment, reverses unspent points from the original lot, records debt for points already spent, and retains the original earning-rule version.
- Disposable migration replay, schema verification and CRM pgTAP passed; exact-head quality checks passed.

Remaining CRM gaps: no staging Auth/tenant A/B or POS/Finance E2E, full customer deduplication/merge is incomplete, customer LTV snapshot integration remains incomplete, and no feature is DONE.

### HR/Payroll ↔ Finance journal and payment reconciliation

- HR management API now includes provider configuration and beneficiary profile request/approval, payroll payment batch prepare/approve, payment-item listing and independent reconciliation.
- Beneficiary bank details are read server-side from Edge Function Secrets; only secret reference and SHA-256 fingerprint are persisted.
- New `hr-payroll-provider-webhook` verifies HMAC-SHA256 over raw request body before invoking the idempotent provider-event RPC.
- Payment batch preparation requires reconciled payroll and Finance posting, approved provider and beneficiary profiles; batch approval and reconciliation require independent actors.
- ERP UI includes provider, beneficiary, batch and item review panels; panel visibility uses strict boolean `app_metadata.platform_owner === true`.
- Exact-head quality checks and disposable HR pgTAP/replay passed.

Remaining HR gaps: no provider-specific outbound payout dispatcher, no provider credentials or fixtures, no staging provider webhook E2E, no bank-statement reconciliation E2E, and no branch labor-cost BI acceptance. The generic webhook is not deployed; its JWT gateway setting must be disabled only for that endpoint after provider contract approval, while HMAC verification remains mandatory.

### Updated feature scoring

- Total: 189.
- PARTIAL: 188; NOT VERIFIED: 0; BLOCKED: 1; DONE: 0.
- Scored PARTIAL features: 53; unscored PARTIAL features: 135.
- Newly scored at 53%: D10-F01 (unified customer identity), D10-F04 (refund-aware loyalty) and D12-F06 (payroll/Finance integration). The 53% reflects code/UI PARTIAL (10), disposable database PASS (20), authorization PARTIAL (7.5), automated tests PASS (15), E2E UNVERIFIED (0), reconciliation/observability UNVERIFIED (0).
- D08-F04/F07/F08/F09/F10 remain at 33% because the schema is not canonical/replayed and staging/runtime dimensions remain unverified.
- Mean of the 53 scored features: 40.58%. This is not overall FnB OS completion.

### Release and staging guardrails

PR #153 remains OPEN/DRAFT. No merge, shared staging migration, Edge deployment, Storage bucket creation, Auth metadata change, production mutation or release occurred. `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false` remain unchanged. The Owner strict-boolean claim remains a separate staging blocker; no SQL Auth metadata mutation was performed.
