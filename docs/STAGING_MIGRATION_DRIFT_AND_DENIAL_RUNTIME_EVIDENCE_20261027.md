# Staging migration drift and denied-access no-mutation evidence
Date: 2026-10-27
Scope: Supabase staging project `higoadrzxnhzbbwhdbmh` and GitHub branch `staging` at `48e8c591fa3de9089f9cb2ca01ac2f90d8c1e3d8`.
Production project `gdjlkrmlsurcdbwnmqgg` was not accessed or changed.

## Executive result

- The latest deny-policy migration is aligned: repository file `supabase/migrations/20261027112330_explicit_deny_policies_server_only_tables.sql` matches the remote migration version `20261027112330`.
- Historical migration ledger is **not fully reconciled**: 44 local migration files versus 45 remote migration records; 12 local-only timestamps and 13 remote-only timestamps.
- No older migration was renamed, replayed, deleted, or edited as part of this audit. Doing that without validating the exact historical SQL could reorder a fresh install or falsely claim a file matches an already-applied migration.
- Database-role negative tests below were run against staging. They prove the tested SQL roles were denied at the PostgreSQL privilege layer and that row counts for the 17 deny-policy target tables were unchanged. They are **not** a substitute for authenticated HTTP/PostgREST/Edge Function tenant-isolation tests.

## Historical drift inventory

Remote-only versions:
- `20261017183506_initial_dlice_ordering_schema`
- `20261017183509_index_ordering_foreign_keys`
- `20261017183535_atomic_checkout_and_private_payment_proofs`
- `20261017183537_seed_dlice_catalog`
- `20261017183540_admin_role_permissions`
- `20261017183542_product_catalog_storage`
- `20261017184921_admin_username_accounts`
- `20261020160307_lock_internal_table_rls`
- `20261022140302_add_missing_fk_supporting_indexes`
- `20261023175347_kitchen_kds_idempotency_modifiers`
- `20261023175514_tenant_branch_platform_foundation`
- `20261023175946_tenant_branch_integrity_constraints`
- `20261023180455_kds_pos_deferred_dispatch`

Local-only files:
- `20261018000000_initial_dlice_ordering_schema.sql`
- `20261018001000_index_ordering_foreign_keys.sql`
- `20261018002000_atomic_checkout_and_private_payment_proofs.sql`
- `20261018003000_seed_dlice_catalog.sql`
- `20261018004000_admin_role_permissions.sql`
- `20261018005000_product_catalog_storage.sql`
- `20261018006000_admin_username_accounts.sql`
- `20261020160000_lock_down_internal_table_rls.sql`
- `20261023180000_tenant_branch_integrity_constraints.sql`
- `20261023181000_kds_pos_deferred_dispatch.sql`
- `20261023232000_kitchen_kds_idempotency_modifiers.sql`
- `20261023233000_tenant_branch_platform_foundation.sql`

The local `20261021151524_index_remaining_erp_foreign_keys.sql` may be related to remote `20261022140302_add_missing_fk_supporting_indexes`, but filename similarity is not proof of identical SQL. It must be compared by SQL statements and resulting index definitions before treating it as a mapping. Likewise, `lock_down_internal_table_rls` and `lock_internal_table_rls` must be compared by historical contents before mapping.

## Safe reconciliation plan

1. Freeze edits to existing historical migration files until their exact content and provenance are verified.
2. For each timestamp/name mismatch, retrieve the historical file content at the commit that introduced it and compare normalized SQL against the local file; separately inspect dependencies and ordering.
3. Inspect current staging catalog state for every DDL object created by remote-only migrations (constraints, indexes, functions, policies, triggers) and verify definitions, not just object names.
4. Resolve the missing-FK-index migration as either an exact historical file restoration or a new forward-only migration after reviewing actual index coverage. Do not replay the old DDL merely to make the ledger look aligned.
5. Only after the mapping is proven, rename/reconcile repository filenames in a dedicated PR and run a fresh disposable database migration test. Do not reset or recreate the shared staging database as a shortcut.
6. Keep production untouched; any production rollout requires its own reviewed migration plan.

## Runtime denial test: PostgreSQL role simulation

Using the staging database connection, the following statements were executed under explicit database roles and failed with PostgreSQL SQLSTATE `42501` (`permission denied for table tenants`):

| Test | Role | Operation | Outcome |
|---|---|---|---|
| DRT-01 | `anon` | `SELECT id FROM public.tenants LIMIT 1` | Denied |
| DRT-02 | `anon` | `INSERT INTO public.tenants DEFAULT VALUES` | Denied |
| DRT-03 | `authenticated` | `UPDATE public.tenants SET id=id WHERE false` | Denied |
| DRT-04 | `authenticated` | `DELETE FROM public.tenants WHERE false` | Denied |

The denial happened at the table-privilege layer, before a row could be changed. The UPDATE/DELETE predicates intentionally matched no rows; the role still lacked the required privileges.

## Before/after data evidence

Row counts were read using a privileged read-only query immediately before and after DRT-01 through DRT-04. Counts were identical:

| Table | Before | After |
|---|---:|---:|
| backup_restore_runs | 0 | 0 |
| branch_settings | 0 | 0 |
| integration_connections | 0 | 0 |
| integration_outbox | 0 | 0 |
| inventory_waste_events | 0 | 0 |
| kitchen_ticket_items | 6 | 6 |
| kitchen_tickets | 6 | 6 |
| offline_sync_receipts | 6 | 6 |
| order_stock_consumptions | 0 | 0 |
| pos_idempotency_requests | 6 | 6 |
| product_modifiers | 0 | 0 |
| recipe_substitutions | 0 | 0 |
| shift_handover_records | 0 | 0 |
| tenant_invites | 0 | 0 |
| tenant_memberships | 1 | 1 |
| tenants | 1 | 1 |
| warehouses | 154 | 154 |

## Policy and privilege catalog check

A separate catalog query confirmed for all 17 target tables:
- RLS enabled: 17/17.
- `deny_direct_client_access` policy present: 17/17.
- `anon` direct SELECT/INSERT/UPDATE/DELETE table privileges: false for all 17/17.
- `authenticated` direct SELECT/INSERT/UPDATE/DELETE table privileges: false for all 17/17.

## Remaining gates / limits

- This proves direct database-role denials for four operations on `public.tenants`, plus unchanged row counts across the 17 target tables. It does not prove every CRUD action against every table through REST or a signed-in JWT.
- Authenticated HTTP negative tests, wrong-branch/cross-tenant read/write tests, and tenant-specific before/after snapshots remain required. The available connector has no approved direct HTTP POST/function-invoke action, so those API calls were not fabricated or claimed.
- `TENANT_ISOLATION_RELEASED` must remain `false` until trusted platform-owner identity/allowlist configuration and full runtime isolation tests are independently verified.
- No temporary QA accounts or test business records were created.
- Production was not accessed or changed.
