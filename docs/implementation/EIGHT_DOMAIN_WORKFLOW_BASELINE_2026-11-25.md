# Eight-domain workflow implementation baseline

**Branch:** `feat/eight-domain-workflow-kernel-20261125`  
**Base:** current `staging` head at branch creation  
**Scope:** workflow contracts only; no merge, migration execution, Supabase mutation, or production change.

## Delivery order

1. CRM, Loyalty & Marketing
2. HR & Workforce
3. Delivery & Fulfillment
4. Franchise & Expansion
5. BI & Analytics
6. SaaS Tenant Management
7. Procurement & Supplier
8. Executive Command Center

## Required end-to-end workflow slices

| Domain | Aggregate and lifecycle | Cross-domain dependencies | Completion evidence still required |
|---|---|---|---|
| CRM | Customer identity, consent, segments, immutable points ledger, tier, rewards, voucher, referral, campaign, feedback and retention | POS/order identity, promotions, notification/outbox, BI | Tenant-scoped persistence, consent withdrawal, duplicate-event protection, reward redemption/reversal, campaign attribution and customer history |
| HR | Employee lifecycle, onboarding/offboarding, assignment, scheduling, attendance, timesheet, leave/overtime, payroll and training | Branch Operations, access control, Finance, BI | Approval policies, server timestamps, schedule conflict detection, payroll reconciliation and access revocation |
| Delivery | Address, quote, booking, dispatch, tracking, proof of delivery, cancellation, retry and refund/compensation | Order Management, POS payment state, notifications, Finance | Provider contract or explicit manual fallback, webhook signature/deduplication, cost reconciliation and failure compensation |
| Franchise | Application, due diligence, site scorecard, financial forecast, territory, contract, opening readiness, royalty and compliance | SaaS tenant lifecycle, Finance, Branch Operations, BI | Versioned agreement, territory constraints, tenant-scoped access, royalty reconciliation and compliance corrective actions |
| BI | KPI dictionary/version, source lineage, timezone, data quality, cohorts, forecasting, anomalies, exports and action outcome | All operational domains | Reconciled source-to-report totals, freshness/completeness monitoring, forecast scoring and auditable alert closure |
| SaaS Tenant | Provisioning, membership, isolation, plans, entitlements, quotas, metering, billing, suspension, support access and offboarding | Auth, all tenant-scoped records, Finance | Server-enforced entitlements, cross-tenant denial, JIT support approval, usage ledger and retention-safe deletion |
| Procurement | Supplier, effective price, requisition, consolidation, PO, approval, GRN/QC, 3-way match, AP and returns | Inventory, Finance, Branch Operations, Franchise | Atomic/idempotent receipt, stock ledger parity, tolerance handling and supplier settlement |
| Executive | KPI rollups, branch cohorts/ranking, targets, alerts, approvals, drill-down, assignment, resolution and measured verification | BI and all operational modules | 150-branch source reconciliation, role/tenant-safe drill-down and closed-loop action evidence |

## Shared command contract

`src/fnb-domain-workflows.mjs` provides pure transition definitions and guard checks for valid source state, actor role, required evidence, tenant/branch scope and duplicate idempotency keys. These checks are **not** an authorization boundary: the server must independently authenticate the caller, resolve tenant/branch scope from trusted claims and database records, enforce RLS, and write audit records atomically.

## Explicit non-goals in this first commit

- No database migration was created or applied.
- No Supabase schema, Auth metadata, RLS, Edge Function, Vercel deployment, or production resource was changed.
- No existing PR was merged and no PR was created.
- No UI claims these workflows are live yet.

## Next implementation gates

For each domain, add persistence model and migration source in the final migration batch, server-side command handlers, RLS and negative cross-tenant tests, integrated workspace UI, event/outbox handling, and contract tests. Then run the complete cross-domain E2E and financial/stock reconciliation batch before any merge or migration execution.
