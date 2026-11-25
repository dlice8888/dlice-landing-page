# Eight-domain workflow implementation baseline

**Branch:** feat/eight-domain-workflow-kernel-20261125  
**Base:** current staging head at branch creation  
**Scope:** application-independent domain rules and workflow contracts. Merge, migration execution, Supabase mutation, and production changes remain deferred by decision.

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
| src/fnb-domain-workflows.mjs | Lifecycle transitions, role intent, required evidence, tenant/branch mismatch and idempotency guards across all eight domains | Source committed; workflow contract tests exist |
| src/crm-loyalty-domain.mjs | Customer identity normalization, consent grant/withdrawal, consent-aware audience eligibility, immutable-ledger command validation, idempotency, reversal, balance and reward-window validation | Source + CRM contract tests committed |
| src/fnb-cross-domain-rules.mjs | HR attendance/timesheet/payroll invariants; delivery quote and provider-event deduplication; franchise effective-version royalty calculation; BI KPI lineage/version/reconciliation; SaaS entitlement/quota guards; procurement 3-way match; executive alert independent verification | Source + cross-domain contract tests committed |

These are pure domain modules. They do not access a database or authenticate callers. The guards are not a substitute for server authorization, RLS, database constraints, atomic transactions, or audit logging.

## End-to-end workflow slices still to implement

| Domain | Workflow coverage added | Integration and acceptance still required |
|---|---|---|
| CRM | Customer identity, consent lifecycle, campaign audience eligibility, points earn/redeem/reversal and reward validity rules | Existing schema reconciliation; tenant-scoped persistence; server commands; POS/order linkage; atomic immutable ledger; voucher reservation/consume; UI; consent withdrawal and duplicate-event E2E |
| HR | Attendance event, submitted timesheet approval, self-approval prevention and payroll input guards | Employee/branch assignment; schedules, leave/overtime, shift conflict policy, payroll persistence and accounting reconciliation; access revocation; UI and E2E |
| Delivery | Quote/cost split, manual-vs-provider quote reference, provider callback deduplication | Provider contract and signature verification; order/payment separation; booking, tracking, POD, retry, compensation/refund; notification and finance integration; UI and E2E |
| Franchise | Effective contract version and royalty calculation | Application/due diligence/site feasibility/territory, approval, signed agreement, opening readiness, tenant provisioning, royalty ledger and compliance workflows |
| BI | KPI lineage, timezone, owner, immutable version progression and reconciliation gate | Source event models, aggregation jobs, freshness/completeness, cohorts/forecasting, exports, source-to-report reconciliation and UI |
| SaaS Tenant | Tenant entitlement, status and quota decision rules | Existing tenant schema and Auth membership integration, plan/metering/billing lifecycle, RLS negative tests, JIT support, offboarding/retention, server-side enforcement and UI |
| Procurement | Supplier consistency, accepted receipt and tolerance-based PO/receipt/invoice match | Reconcile with existing requisition/PO/GRN migrations and RPCs; atomic receipt/stock ledger; approval separation; returns/AP; warehouse consolidation; UI and E2E |
| Executive | Alert resolution evidence, measured outcome and independent verification | 150-branch KPI source reconciliation, role-safe company→region→branch→shift→transaction drilldown, targets, rankings, approvals, assignment and alert UI |

## Security and release constraints

- Every command handler must authenticate the request and resolve tenant/branch scope from trusted server-side membership data, never from client-supplied identifiers alone.
- Enforce tenant and branch isolation in RLS and database constraints; keep TENANT_ISOLATION_RELEASED=false and PUBLIC_TENANT_ROUTING_RELEASED=false.
- Write state transitions, idempotency records, ledgers, and audit events atomically where they form one business operation.
- Never expose service-role credentials in browser code, logs, or client responses.
- No migrations have been applied, no Supabase Auth metadata was changed, no Vercel deployment was made, and no production resource was touched.
- No PR has been created or merged. Final merge, disposable replay, staging migration application, full E2E, and reconciliation remain a single coordinated final phase.

## Acceptance rule

A domain is not DONE because a pure function, test file, table, route, or screen exists. Acceptance requires traceability from PRD feature to database entity/relation, RLS, server API/RPC, UI, automated tests, staging runtime, and cross-domain business reconciliation. Until those layers are connected and proven, the affected features remain PARTIAL / NOT VERIFIED.
