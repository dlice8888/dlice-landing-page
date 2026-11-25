# Eight-domain workflow implementation baseline

**Branch:** `feat/eight-domain-workflow-kernel-20261125`  
**Base:** `staging` at branch creation  
**Scope:** Domain rules, first CRM and HR vertical slices, and design-only SQL drafts. Merge, migration execution, Supabase mutation, and Production release remain deferred by decision.

## Delivery order

1. CRM, Loyalty & Marketing
2. HR & Workforce
3. Delivery & Fulfillment
4. Franchise & Expansion
5. BI & Analytics
6. SaaS Tenant Management
7. Procurement & Supplier
8. Executive Command Center

## Source delivered in this branch

| File | Scope | Current evidence |
|---|---|---|
| `src/fnb-domain-workflows.mjs` | Lifecycle transitions, role intent, required evidence, tenant/branch mismatch and idempotency guards across all eight domains | Source committed; contract test source committed |
| `src/crm-loyalty-domain.mjs` | Customer identity normalization, consent grant/withdrawal, consent-aware audience eligibility, immutable-ledger command validation, idempotency, reversal, balance and reward-window validation | Source + CRM contract test source committed |
| `src/fnb-cross-domain-rules.mjs` | HR attendance/timesheet/payroll; delivery quote/provider-event; franchise royalty; BI KPI lineage/reconciliation; SaaS entitlement/quota; procurement 3-way match; executive alert verification | Source + cross-domain contract test source committed |
| `src/fnb-domain-acceptance-rules.mjs` | Loyalty earn/campaign, HR shift/leave/overtime, delivery transitions, franchise due diligence/opening, BI freshness/completeness, tenant lifecycle, procurement approvals/receipts, executive drilldown/targets | Source + acceptance test source committed |
| `erp.html` + `supabase/functions/dlice-orders/index.ts` (CRM) | Owner CRM workspace; customer list/create, consent event append, loyalty ledger read/post, reward draft create/list/activate and atomic voucher redemption command | Source committed; CRM non-Owner access fails closed while tenant isolation is unreleased |
| `docs/implementation/sql/CRM_LOYALTY_SCHEMA_DRAFT.sql` | Tenant-scoped customer, consent, append-only ledger, reward, voucher and transaction-link schema; service-role-only RLS; transactional ledger/reward RPCs; audit triggers | Design SQL only; not a Supabase migration and not applied |
| `erp.html` + `supabase/functions/dlice-orders/index.ts` (HR) | Branch-scoped active staff list, attendance read and attendance event write; event write routes through a serialized database RPC with state-order validation | Source committed; HR non-Owner access fails closed while tenant isolation is unreleased |
| `docs/implementation/sql/HR_WORKFORCE_SCHEMA_DRAFT.sql` | Tenant-scoped schedule, attendance, leave, timesheet and payroll entities; service-role-only RLS; audit triggers; serialized attendance RPC | Design SQL only; not a Supabase migration and not applied |
| `docs/implementation/STAGING_SCHEMA_RECONNAISSANCE_EIGHT_DOMAINS_2026-11-25.md` | Read-only inventory of existing staging entities, RLS policy patterns and tenant attribution gaps | Read-only schema/policy inspection recorded |

These source modules and UI/server additions do not by themselves prove runtime completion. All server commands still require exact authorization, database constraints, transactionality and audit. No new CRM/HR table exists in staging until the final migration batch.

## End-to-end workflow slices still to implement

| Domain | Workflow coverage added | Integration and acceptance still required |
|---|---|---|
| CRM | Customer identity, consent lifecycle, ledger earn/redeem/reversal, reward draft/activation/redemption command and Owner UI | Generate/review migration; voucher consume/void and POS redemption linkage; historical order/POS identity linking; tenant-scoped staff authorization after isolation gate; pgTAP, Edge/UI E2E, consent withdrawal, concurrency and reconciliation |
| HR | Active staff list and attendance UI/server commands; attendance sequence and idempotency guards; shift/leave/timesheet/payroll domain rules | Generate/review migration; roster overlap RPC; leave request, coverage confirmation and independent approval; timesheet evidence and approval; payroll posting to Finance; role-specific UI and E2E |
| Delivery | Quote/cost split, provider quote reference, webhook deduplication and state-transition guards | Provider contract/signature verification; order/payment linkage; booking, tracking, POD, retries, compensation/refund, notifications and finance integration |
| Franchise | Effective contract version, royalty calculation, due-diligence and opening-readiness rules | Application, territory, site feasibility, legal approval, signed agreements, tenant provisioning, royalty ledger and compliance workflows |
| BI | KPI lineage/version/reconciliation rules, freshness/completeness and source watermark acceptance | Source events, aggregation, versioned snapshots, cohorts, exports, source-to-report reconciliation and UI |
| SaaS Tenant | Tenant lifecycle, entitlement, quota and offboarding guards | Plan catalogue/version, metering, billing/invoice lifecycle, membership integration, server enforcement, RLS negative tests, retention and offboarding UI |
| Procurement | Supplier consistency, accepted receipt, three-way match, approval segregation and tolerance rules | Resolve existing supplier table's missing tenant ownership; verify PO/GRN/stock atomicity, invoice/AP posting, returns, warehouse consolidation and UI |
| Executive | Alert evidence/independent verification, KPI target and drilldown scope rules | Reconciled 150-branch KPIs, role-safe company→region→branch→shift→transaction drilldown, targets, rankings, assignment and alert UI |

## Security and release constraints

- Every command handler must authenticate the request and resolve tenant/branch scope from trusted server-side membership data, never from client-supplied identifiers alone.
- CRM and HR server actions are currently Platform-Owner-only while `TENANT_ISOLATION_RELEASED=false`; tenant-user access is not enabled by this branch.
- Enforce tenant and branch isolation in RLS and database constraints; keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.
- Write state transitions, idempotency records, ledgers, and audit events atomically where they form one business operation.
- Never expose service-role credentials in browser code, logs, or client responses.
- No migrations have been applied and no Supabase Auth metadata was changed. The latest Vercel branch Preview is READY; no manual Production deployment or Supabase Edge Function deployment was performed.
- No PR has been created or merged. Final merge, disposable replay, staging migration application, full E2E, and reconciliation remain a single coordinated final phase.

## Acceptance rule

A domain is not DONE because a pure function, test file, table, route, or screen exists. Acceptance requires traceability from PRD feature to database entity/relation, RLS, server API/RPC, UI, automated tests, staging runtime, and cross-domain business reconciliation. Until those layers are connected and proven, the affected features remain PARTIAL / NOT VERIFIED.
