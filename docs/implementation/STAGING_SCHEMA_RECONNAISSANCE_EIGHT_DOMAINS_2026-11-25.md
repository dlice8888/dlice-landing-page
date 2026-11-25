# Staging schema reconnaissance for eight priority domains

**Read-only source:** Supabase staging project `higoadrzxnhzbbwhdbmh`, public schema, inspected 2026-11-25. No data rows were read or changed for this inventory. No migration was applied.

## Existing domain entities found

| Domain | Existing staging entities | Implication |
|---|---|---|
| CRM, Loyalty & Marketing | `orders` includes customer_name/customer_whatsapp; `pos_sales` includes customer_reference. No dedicated CRM/loyalty entity was found in the public table inventory. | A real CRM requires a tenant-scoped customer identity and consent model, with explicit linkage to order/POS records. Do not treat customer_reference as a customer master or create loyalty balance fields on transactions. |
| HR & Workforce | `admin_profiles`, `job_positions`, `branch_assignments`, `pos_shifts`, `shift_handover_records` | Staff identity, role and branch assignment foundations exist. No dedicated attendance-event, roster/schedule, leave, timesheet or payroll tables were found. |
| Delivery & Fulfillment | `orders`, `order_status_history`, `payment_records`, `notification_log` | Order and payment state already exist separately, including fulfillment_status. Dedicated courier quote, provider callback/event, dispatch/POD and delivery-cost ledger entities were not found. Extend order fulfillment without conflating payment_status and operational_status. |
| Franchise & Expansion | `tenants`, `branches`, `tenant_memberships`, `tenant_invites`, `branch_settings` | Tenant and branch provisioning foundations exist. Franchise applications, due diligence, territory rights, versioned agreements and royalty ledgers were not found. |
| BI & Analytics | `funnel_daily_metrics`, `admin_audit_logs`, operational transaction/stock/finance entities | Some source data and funnel aggregation exist. A versioned KPI catalogue, source watermarks, snapshot completeness/reconciliation and governed cohort definitions were not found. |
| SaaS Tenant Management | `tenants`, `tenant_memberships`, `tenant_invites`, `integration_connections`, `integration_outbox`, `backup_restore_runs` | Core tenant membership/integration foundations exist. Dedicated subscription plans, entitlement catalogue, usage metering, invoice/payment lifecycle and offboarding evidence were not found. |
| Procurement & Supplier | `suppliers`, `purchase_requisitions`, `purchase_requisition_items`, `purchase_orders`, `purchase_order_items`, `purchase_receipts`, `purchase_receipt_items` | A requisition → PO → receipt path exists. Verify approval transitions, supplier tenant ownership, immutable receipt/stock linkage, invoice matching and AP posting before extending. |
| Executive Command Center | `branches`, `tenants`, `pos_sales`, `orders`, inventory, procurement, finance and operational checklist entities | Operational sources exist for some KPIs. A governed metric catalogue and verified 150-branch company→region→branch→shift→transaction drilldown still require source/role/reconciliation proof. |

## Security and ownership observations

- `branches` has `tenant_id`; `tenant_memberships` binds `tenant_id` to `user_id`, role, permissions and active status.
- `admin_profiles` is a global profile table. It must not be treated as sufficient tenant authorization.
- `branch_assignments` stores `branch_id` and `user_id` but has no direct `tenant_id`; authorization must join through the branch and active tenant membership. `pos_shifts`, `pos_sales`, `purchase_requisitions`, `purchase_orders`, and `purchase_receipts` also rely on branch references rather than storing tenant_id directly.
- `suppliers` has no `tenant_id` column in staging. The current supplier master therefore cannot be assumed tenant-isolated; a supplier-to-tenant ownership model or approved shared-supplier model is needed before exposing Procurement supplier writes to tenant users.
- `orders` has nullable `branch_id` and no `tenant_id`; historical/unassigned orders cannot be safely assigned to a CRM tenant by guessing from customer phone or name.
- Existing tenant-aware tables include composite tenant/branch foreign keys, for example branch settings, warehouses, inventory waste and integration outbox. New branch-scoped entities should follow this referential-integrity pattern.
- The inspected public tables had RLS enabled. Read-only policy inspection showed `admin_profiles`, `orders`, and `admin_audit_logs` use service-role-only access; `branches`, `tenant_memberships`, `suppliers`, `purchase_orders`, `purchase_receipts`, and `pos_sales` deny direct `anon`/`authenticated` access. This is a deliberate server-mediated pattern, not evidence that every Edge action is correctly authorized. Policy-by-policy and cross-tenant negative tests remain required.
- Edge Function `dlice-orders` has server-side service-role access. New commands must authenticate with the caller JWT, derive tenant and branch scope from active membership, authorize the specific command, and append audit evidence. Never trust client-supplied tenant_id as authority.
- Existing global owner authorization remains dual-gated by the server UUID allowlist and boolean `app_metadata.platform_owner === true`. Do not change that path here.

## Implementation sequence based on actual schema

1. CRM: add the missing tenant-owned customer, consent-event, reward/voucher and append-only loyalty ledger model; link customer IDs to order and POS through explicit nullable foreign keys only after duplicate/identity migration rules are defined.
2. HR: extend existing employee/profile and branch-assignment model with schedules, attendance events, leave and approved timesheets; payroll must reconcile to finance journals.
3. Delivery: extend the existing fulfillment lifecycle with quote snapshots, provider event idempotency, proof of delivery and fee/subsidy/cost accounting.
4. Franchise: build application, due diligence, territory and effective-dated agreement records; royalty postings must reconcile to tenant sales/finance.
5. BI: define versioned metrics and source lineage; publish snapshots only after freshness, completeness and reconciliation checks.
6. SaaS: define plan versions, entitlements, metering and billing lifecycle over existing tenant records; enforce entitlement server-side and preserve isolation flags.
7. Procurement: reuse the existing requisition/PO/receipt entities; close the supplier ownership, approval separation, receipt-to-stock and invoice three-way-match gaps.
8. Executive: use only reconciled source metrics and enforce role-safe drilldown at every level.

## CRM source implementation added after reconnaissance

- Added `erp.html` CRM workspace and server action source for Platform Owner customer list/create, consent event append, loyalty ledger read/post, and reward draft create/list.
- Added a non-executable schema design draft at `docs/implementation/sql/CRM_LOYALTY_SCHEMA_DRAFT.sql`, including tenant-composite customer/branch references, append-only consent and loyalty records, service-role-only RLS, transactional loyalty posting and reward redemption RPCs, and same-transaction audit triggers.
- CRM Edge actions intentionally return a fail-closed response for non-Platform-Owner callers while `TENANT_ISOLATION_RELEASED=false`. This is a temporary implementation boundary, not final role coverage.
- The CRM workspace will not function against staging until the draft is reconciled, generated as a proper Supabase migration, reviewed, replayed and applied during the final batch.

## Release decision

This is reconnaissance only. No DDL, DML, RPC, Auth Admin, Edge Function deployment, Vercel deployment, or Production operation was performed. SQL migration authoring and all merge/migration/runtime validation remain deferred to the agreed final batch. The schema inventory is not a completion claim.
