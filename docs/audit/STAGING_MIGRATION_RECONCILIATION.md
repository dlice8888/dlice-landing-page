# Staging migration reconciliation

- Captured: 2026-11-13T13:43Z UTC; latest Git staging: `aed2733f62506ed87a5040a48f479753fdafe1b1`.
- Migration files in latest Git staging: 45; union of migration paths found on all live branches: 66. A total of 38 non-core branches have a migration dependency in their branch comparison or PR changes; all remain preserved unless independently eligible without migration changes.
- Supabase staging exact migration history and schema catalog were **not queried**: Supabase CLI is not installed and no staging database connection interface is available in this workspace. No credentials or secret values were read.
- No version is claimed `APPLIED_AND_VERIFIED`. For files present in Git staging, Supabase history and schema verification are `UNKNOWN`; branch-only files are `MISSING_FROM_STAGING` in Git. These are conservative statuses, not deployment claims.
- Historical `docs/STAGING_MIGRATION_DRIFT_AND_DENIAL_RUNTIME_EVIDENCE_20261027.md` reports then-current 44 local files vs 45 remote records and an applied/schema-verified version `20261027112330`; that dated record is not a live check of today’s staging state.
- Do not apply the withheld PR #64 tenant-isolation migration `20261028120000_enforce_same_tenant_stock_transfers.sql`. PR #64 remains Draft/open; its migration is absent from latest Git staging and current Supabase history/schema are unknown. No migration or database operation was performed.

| Migration version / file | Git staging | Supabase staging history | Schema verified | Status |
|---|---|---|---|---|
| `20261017183506` — `20261017183506_initial_dlice_ordering_schema.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261017183509` — `20261017183509_index_ordering_foreign_keys.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261017183535` — `20261017183535_atomic_checkout_and_private_payment_proofs.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261017183537` — `20261017183537_seed_dlice_catalog.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261017183540` — `20261017183540_admin_role_permissions.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261017183542` — `20261017183542_product_catalog_storage.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261017184921` — `20261017184921_admin_username_accounts.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261017205317` — `20261017205317_receipt_payment_notification_gates.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261017205718` — `20261017205718_payment_assets_and_settings_seed.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261018000000` — `20261018000000_initial_dlice_ordering_schema.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261018001000` — `20261018001000_index_ordering_foreign_keys.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261018002000` — `20261018002000_atomic_checkout_and_private_payment_proofs.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261018003000` — `20261018003000_seed_dlice_catalog.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261018004000` — `20261018004000_admin_role_permissions.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261018005000` — `20261018005000_product_catalog_storage.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261018006000` — `20261018006000_admin_username_accounts.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261019183939` — `20261019183939_add_free_rate_limiting.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261019184047` — `20261019184047_add_privacy_preserving_funnel_metrics.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261019185240` — `20261019185240_atomic_payment_verification.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261019185629` — `20261019185629_atomic_operational_status_changes.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020160000` — `20261020160000_lock_down_internal_table_rls.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261020160307` — `20261020160307_lock_internal_table_rls.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020171825` — `20261020171825_safe_operational_retention_and_rpc_acl.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020185740` — `20261020185740_align_product_copy_and_prices.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020193327` — `20261020193327_multi_branch_pos_erp_foundation.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020193920` — `20261020193920_index_erp_foreign_keys.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020194817` — `20261020194817_order_fulfillment_production_finance_controls.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020195004` — `20261020195004_atomic_purchase_receiving_and_production_consumption.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020201601` — `20261020201601_branch_routed_online_checkout_capacity.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020201654` — `20261020201654_finance_refund_settlement_and_period_guards.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020201715` — `20261020201715_branch_capacity_on_order_edits.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020201812` — `20261020201812_atomic_payment_settlement_matching.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020202158` — `20261020202158_immutable_final_refund_records.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020202449` — `20261020202449_settlement_match_only_paid_payments.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020202805` — `20261020202805_refund_guard_all_updates.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020202830` — `20261020202830_atomic_recipe_version_activation.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261020202841` — `20261020202841_deterministic_production_stock_lock_order.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261021120000` — `20261021120000_safe_operational_retention_and_rpc_acl.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261021150339` — `20261021150339_deny_direct_client_access_on_internal_tables.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261021151246` — `20261021151246_branch_timezone_checkout_cutoff.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261021151524` — `20261021151524_index_remaining_erp_foreign_keys.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261021182634` — `20261021182634_branch_operation_checklists.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261021190000` — `20261021190000_align_product_copy_and_prices.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261021194500` — `20261021194500_multi_branch_pos_erp_foundation.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261021195000` — `20261021195000_index_erp_foreign_keys.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261022124132` — `20261022124132_stock_transfers_and_counts.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261022130135` — `20261022130135_stock_transfer_approval_pick_reconcile.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261023003006` — `20261023003006_revoke_direct_client_access_stock_workflows.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261023160257` — `20261023160257_purchase_requisitions.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261023160440` — `20261023160440_purchase_requisition_conversion_index.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261023170000` — `20261023170000_purchase_requisitions.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261023175347` — `20261023175347_kitchen_kds_idempotency_modifiers.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261023175514` — `20261023175514_tenant_branch_platform_foundation.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261023175946` — `20261023175946_tenant_branch_integrity_constraints.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261023180000` — `20261023180000_tenant_branch_integrity_constraints.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261023180455` — `20261023180455_kds_pos_deferred_dispatch.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261023181000` — `20261023181000_kds_pos_deferred_dispatch.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261023232000` — `20261023232000_kitchen_kds_idempotency_modifiers.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261023233000` — `20261023233000_tenant_branch_platform_foundation.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261025010000` — `20261025010000_explicit_deny_policies_server_only_tables.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261025115812` — `20261025115812_fix_pos_idempotency_digest_schema.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261025120000` — `20261025120000_fix_pos_idempotency_digest_schema.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261027112330` — `20261027112330_explicit_deny_policies_server_only_tables.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261027140145` — `20261027140145_revoke_client_execute_on_trigger_only_functions.sql` | YES | UNKNOWN (not queried) | NOT VERIFIED | UNKNOWN |
| `20261028120000` — `20261028120000_enforce_same_tenant_stock_transfers.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |
| `20261108090000` — `20261108090000_atomic_tenant_audit_operations.sql` | NO | UNKNOWN (not queried) | NOT VERIFIED | MISSING_FROM_STAGING |

## Tenant-isolation release gate

- `TENANT_ISOLATION_RELEASED=false` (preserved). PR #64 remains open and Draft; its withheld migration was not applied.
- Current staging commit check `auth-negative` failed (Actions run `43434328863`). This does not constitute execution and pass evidence for all nine probes. The last observed staging runtime tenant-isolation workflow run also failed.

| Required scenario | This audit result |
|---|---|
| Tenant A login | NOT VERIFIED — no all-nine passing runtime evidence attached |
| Tenant B login | NOT VERIFIED — no all-nine passing runtime evidence attached |
| A and B have different authenticated identities | NOT VERIFIED — no all-nine passing runtime evidence attached |
| A reads its own branch | NOT VERIFIED — no all-nine passing runtime evidence attached |
| B reads its own branch | NOT VERIFIED — no all-nine passing runtime evidence attached |
| A is denied access to B data | NOT VERIFIED — no all-nine passing runtime evidence attached |
| B is denied access to A data | NOT VERIFIED — no all-nine passing runtime evidence attached |
| A is denied cross-tenant writes | NOT VERIFIED — no all-nine passing runtime evidence attached |
| B is denied cross-tenant writes | NOT VERIFIED — no all-nine passing runtime evidence attached |
