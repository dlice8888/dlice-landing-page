# Eight-domain workflow implementation status

**Branch:** `feat/eight-domain-workflow-kernel-20261125`  
**Base:** `staging` at branch creation  
**Current scope:** source implementation, server command contracts, ERP workspaces, and design-only SQL drafts. Per the agreed sequencing, integration tests, merge, migration replay/application, and staging runtime rollout are deferred to the final coordinated batch.

## Priority order

1. CRM, Loyalty & Marketing — 8/9 previously unproven
2. HR & Workforce — 8/9
3. Delivery & Fulfillment — 6/8
4. Franchise & Expansion — 6/8
5. BI & Analytics — 7/10
6. SaaS Tenant Management — 6/8
7. Procurement & Supplier — 5/10
8. Executive Command Center — 5/10

## Current source slices

| Domain | Implemented in this branch | Still not complete / acceptance blockers |
|---|---|---|
| CRM | ERP customer/consent/ledger/reward UI; tenant-scoped Edge commands; reward activation and atomic voucher redemption; campaign draft, independent approval and consent-aware audience preparation; design RPCs for voucher consumption against a verified transaction link and void with immutable loyalty reversal; Edge commands enforce branch authorization and require the transaction link | POS/online-order identity linking and automatic earn from reconciled eligible net sales are not wired; the trusted source-link writer must be integrated into the POS/order payment lifecycle; outbound campaign provider/send/retry/unsubscribe webhook; role-scoped tenant access remains fail-closed pending isolation release; no deployed schema/runtime evidence |
| HR | Branch staff list; attendance read/write with serialized state RPC; roster creation with overlap guard; leave request, named coverage confirmation and independent approval; attendance-derived timesheet generation, employee submission and independent approval; effective-dated hourly compensation records; payroll draft calculation from approved timesheets with full-period rate coverage; independent payroll submitter and approver with audit trail | Monthly/fixed compensation, overtime/allowances/tax/benefit/deduction rules, payroll posting to Finance and journal reconciliation; compensation rate overlap governance still needs a formal constraint; schedule editing/cancellation; role-scoped non-Owner access pending tenant isolation; no deployed schema/runtime evidence |
| Delivery | Branch dispatch list and booking command; atomic booking advances a ready, paid order to dispatched; idempotent status event transitions; POD capture command with tenant/branch/dispatch-scoped object-path checks, private bucket existence/MIME/size validation, recipient-name and OTP evidence; delivered state requires recorded POD | Actual browser upload flow and storage bucket/policy provisioning; provider quotes/booking API and signed webhook ingress; customer notifications, retry/compensation/refund; COD and courier fee reconciliation to Finance; no provider is activated or assumed |
| Franchise | Application intake with six due-diligence checklist rows created atomically; evidence-backed checklist and site review; independent application approval gate; opening-gate schema and effective-dated agreement schema; royalty draft calculation sourced only from published branch net-sales BI snapshot and passed reconciliation | Territory exclusivity/conflict engine; agreement drafting/signature/e-sign; all 10 opening-gate UI and verification; tenant/branch provisioning; royalty review/approval/invoice/payment and Finance posting; no deployed schema/runtime evidence |
| BI | Metric catalogue, source watermark, reconciliation and versioned snapshot schema; snapshot publication RPC requires fresh complete lineage and passed reconciliation; UI displays published snapshots | Source ingestion/aggregation jobs and KPI catalogue seed; metric formula governance; cohort/segmentation/export; automated source-to-ledger reconciliation; no snapshot runtime evidence |
| SaaS Tenant | Plan version/entitlement, subscription, usage, invoice/payment and offboarding/legal-hold schema; server-side entitlement/quota RPC design; Owner UI for plan view, trial, cancellation and offboarding; independent offboarding approval with retention window and legal-hold block | Payment gateway/webhook settlement and invoice lifecycle; connect quota metering and entitlement checks to every protected API; tenant lifecycle/suspension and retention execution; data export and deletion evidence; no deployed schema/runtime evidence |
| Procurement | Reuses existing requisition→PO→receipt flow; tenant supplier ownership bridge with independent approval; invoice and PO/receipt three-way match schema/RPC; UI for supplier link and invoice matching | Supplier invoice intake/storage verification; confirm receipt status/columns against current staging schema; complete AP journal posting, returns/credit notes and supplier payment reconciliation; no deployed schema/runtime evidence |
| Executive | KPI target and operational alert schema; alert acknowledge/investigate/resolve/reopen commands; resolution requires evidence; independent verifier required; UI for alert queue, verification and branch KPI snapshots | Governed 150-branch KPI dashboard; company→region→branch→shift→transaction drilldown with authorization at every step; target catalogue and variance automation; alert generation from reconciled source data; no deployed schema/runtime evidence |

## Latest implementation increment (2026-11-25)\n\n- HR payroll source draft now extends the existing `hr_payroll_runs` / `hr_payroll_lines` structures instead of defining parallel replacement tables. It adds effective-dated hourly rates, links payroll lines to approved timesheets and compensation-rate records, and adds independent submit/approve workflow commands.\n- HR Edge Function commands and ERP workspace forms now cover rate entry/listing, payroll generation/listing, submission and approval. They remain Platform-Owner-only while tenant isolation is unreleased.\n- Payroll calculation is deliberately limited to hourly gross wages. It does not calculate overtime, monthly salary, tax, benefits, deductions or net pay. No payment or Finance journal posting is implemented because the actual Finance journal schema and reconciliation keys must first be confirmed.\n\n## Design SQL files (not migrations)

- `docs/implementation/sql/CRM_LOYALTY_SCHEMA_DRAFT.sql`
- `docs/implementation/sql/HR_WORKFORCE_SCHEMA_DRAFT.sql`
- `docs/implementation/sql/DELIVERY_FULFILLMENT_SCHEMA_DRAFT.sql`
- `docs/implementation/sql/FRANCHISE_EXPANSION_SCHEMA_DRAFT.sql`
- `docs/implementation/sql/BI_ANALYTICS_SCHEMA_DRAFT.sql`
- `docs/implementation/sql/SAAS_TENANT_BILLING_SCHEMA_DRAFT.sql`
- `docs/implementation/sql/PROCUREMENT_SUPPLIER_SCHEMA_DRAFT.sql`
- `docs/implementation/sql/EXECUTIVE_COMMAND_CENTER_SCHEMA_DRAFT.sql`

These files are design artifacts only. They must be reconciled against the exact staging schema, checked for dependency order, replayed on a disposable database, and reviewed before becoming timestamped migrations. None has been applied to staging or Production.

## Security boundaries retained

- `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.
- CRM and HR commands remain Platform-Owner-only/fail-closed while tenant isolation is unreleased.
- Franchise, BI, Executive, SaaS plan/offboarding and supplier-ownership administration are Platform-Owner-only.
- Delivery and Procurement operational actions check the actor's branch permission before mutation.
- New tables use service-role-only RLS and revoke direct anon/authenticated access in the design drafts.
- Never trust client tenant IDs as authority; resolve/verify tenant and branch on the server.
- Never expose service-role credentials in browser code or logs.
- No Supabase schema/data/Auth mutation, Edge Function deployment, Production change, PR creation or merge was performed in this implementation phase.

## Current branch inspection (2026-11-25)

- Branch is ahead of `staging` by 118 commits, behind by 0; 20 files differ.
- Source-level structural inspection: ERP section tags balanced (19/19), no duplicate static element IDs, no missing static element references in the ERP script, and all listed CRM/HR/Delivery/Franchise/BI/Executive/SaaS/Procurement actions are present in the Edge Function source.
- The latest GitHub combined status for head `8ab8f14c41497d4ed1ac9fe5c846e45f3c8c4057` reports Vercel `failure` with a build-rate-limit/upgrade URL. This is an infrastructure/build quota block, not a successful build. No exact-head automated tests or integrated runtime checks have been run in this phase.
- A green Preview build, CI tests, disposable migration replay, staging runtime, full E2E and transaction reconciliation remain unproven.

## Final acceptance rule

A feature is not DONE because a pure rule, SQL draft, Edge action, route, or screen exists. It must be proven end-to-end from PRD feature → database entity/relation → RLS → API/RPC → UI → tests → staging runtime → cross-domain reconciliation. Until those proofs exist, status remains PARTIAL / NOT VERIFIED / BLOCKED as appropriate.
