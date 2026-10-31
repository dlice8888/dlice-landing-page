# D'Lice staging tenant-isolation audit (2026-10-28)

## Evidence captured
- Target staging project: `higoadrzxnhzbbwhdbmh`; repository branch: `staging`.
- Supabase schema inventory: 64 public tables; all 64 reported `rls_enabled=true`.
- Inventory row counts: `tenants=1`, `tenant_memberships=1`, `branches=154`.
- Staging Edge Function: `dlice-orders` v60, `verify_jwt=false`.
- Security Advisor still warns `auth_leaked_password_protection` is disabled.
- Existing migrations: `20261023233000_tenant_branch_platform_foundation.sql`, `20261023180000_tenant_branch_integrity_constraints.sql`, `20261027112330_explicit_deny_policies_server_only_tables.sql`.

This is an inventory, not proof of cross-tenant isolation. No production mutation or two-user JWT test was performed.

## Canonical ownership model
- `public.tenants.id`: tenant root.
- `public.tenant_memberships(tenant_id,user_id)`: active membership and role; `user_id` must match `auth.users.id`.
- `public.branches(tenant_id,id)`: canonical branch-to-tenant ownership. The existing integrity migration creates the composite key/FK protections for selected platform tables.
- `public.branch_assignments(user_id,branch_id,...)`: branch-level scope; confirm exact role semantics before policy changes.

Tables with direct `tenant_id` in the live inventory: `tenants`, `tenant_memberships`, `tenant_invites`, `branches`, `warehouses`, `branch_settings`, `shift_handover_records`, `inventory_waste_events`, `integration_connections`, `integration_outbox`, `backup_restore_runs`.

Many operational tables do not have `tenant_id` and must inherit scope from their parent FK or branch: `orders` and children (`order_items`, `payment_records`, `order_status_history`, `order_reservations`); `pos_sales` and items; `pos_shifts`; kitchen tickets/items; production batches/consumptions; branch inventory, stock movements, purchase orders/receipts/requisitions and child rows; expenses, cash reconciliations, refunds, settlements and journal entries. Do not authorize from an unvalidated client-supplied tenant/branch ID. Where both tenant and branch columns exist, they must match the same `branches(tenant_id,id)` row.

Ownership remains a product decision for tables without `tenant_id`, including `products`, `recipes`, `recipe_ingredients`, `product_modifiers`, `job_positions`, and `suppliers`: explicitly declare each as shared/global or tenant-owned before applying a tenant policy. Do not silently treat global catalogs as leaks or as tenant-isolated.

## RLS / grants / views / RPC / Edge Function findings
- All 64 tables report RLS enabled, but that alone does not prove policies are correct.
- Migration `20261027112330_explicit_deny_policies_server_only_tables.sql` revokes direct `anon`/`authenticated` access and adds deny-all policies to server-only tables including tenants, memberships, invites, warehouses, branch settings, handovers, waste, integrations, backup/restore, and selected operational tables. Preserve these denials unless a reviewed server-side access design replaces them.
- Live catalog queries subsequently succeeded. Snapshot: 64 RLS-enabled public tables; 64 policies across 64 tables; 52 policies mention anon/authenticated and 51 are deny policies (false USING/WITH CHECK). These counts are not proof that every row/action is correctly scoped; policies must be reviewed per table and command. `information_schema.role_table_grants` currently shows direct anon/authenticated table grants only on `public.products` (SELECT), consistent with the public active-product catalog policy. No public views were returned from `information_schema.views` in public/app_private.
- Inspected deployed staging source of `dlice-orders` v60. It has `verify_jwt=false`, but its admin helper calls `authClient.auth.getUser(token)`. It sets `TENANT_ISOLATION_RELEASED=false` and returns HTTP 423 for listed uncertified tenant-sensitive actions for non-platform-owner actors. This is a fail-closed gate, not proof of isolation. The handler contains membership/branch-assignment checks that still require runtime negative tests. Platform-owner bypass requires both configured UUID allowlist membership and `app_metadata.platform_owner=true`. No endpoint was executed.
- Security Advisor still warns leaked-password protection is disabled.

- RPC snapshot: 29 public functions; 5 are `SECURITY DEFINER`. Catalog checks report zero EXECUTE privilege for `anon` and `authenticated` across these functions, and all 29 have an explicit `search_path` setting. The five SECURITY DEFINER functions are `erp_create_stock_count`, `erp_create_stock_transfer`, `erp_post_stock_count`, `erp_transition_stock_transfer`, and `erp_update_stock_count_item`. Their bodies accept actor UUID arguments and depend on the trusted caller path; do not grant direct client EXECUTE without moving identity/tenant authorization inside each function. Review source/destination branch tenant equality in stock transfer logic before considering the release gate.

## Confirmed gap and proposed replayable migration
- The live `public.stock_transfers` schema stores `source_branch_id` and `destination_branch_id`, but the existing `erp_create_stock_transfer` SECURITY DEFINER function validates that each branch exists and is active without verifying that both branches belong to the same `tenant_id`. The Edge Function checks actor access to both branches, but that is not a database invariant and can be bypassed by a future trusted caller or privileged RPC path.
- A live read-only query found no existing stock-transfer rows whose source and destination branches belong to different tenants.
- Added migration `supabase/migrations/20261028120000_enforce_same_tenant_stock_transfers.sql` to this PR. It installs a replayable `BEFORE INSERT OR UPDATE OF source_branch_id, destination_branch_id` trigger that rejects missing branches and cross-tenant transfers, fixes `search_path`, and revokes direct client EXECUTE on the trigger function. This does not change current staging data and has not yet been applied to shared staging. It still needs CI/replay validation and a negative test that attempts a cross-tenant transfer through the trusted RPC path.

## Required reviewed migration design
Do not generate broad policies until policy expressions, grants, RPCs, views, and FK chains have been inspected. The reviewed migration should:
1. Use `auth.uid()` and active membership as identity/tenant source.
2. Enforce branch assignments for branch-limited roles and tenant membership for tenant-wide roles.
3. Enforce parent-chain scope on child tables.
4. Use `USING` and `WITH CHECK` for updates, and `WITH CHECK` for inserts.
5. Preserve deny-all direct client access to server-only tables.
6. Use fixed `search_path` and minimum execute grants for any `SECURITY DEFINER` helper.
7. Add missing composite tenant/branch integrity constraints only after checking and backfilling existing data.
8. Replay on a clean staging branch and run tests before applying to shared staging.

## Two-tenant acceptance matrix
Prerequisites: two real Auth users, two valid tenants, one active branch per tenant, active memberships and branch assignments. Test with each user's own JWT, never service-role credentials.

1. A reads known B branch/resource: zero rows or explicit denial; no sensitive fields returned.
2. A updates known B row: denied; before/after snapshot identical.
3. B requests A branch by ID through PostgREST and relevant Edge Functions: denied/no data leak.
4. B reads and performs an allowed action on B's branch: succeeds according to role.
5. A inserts into B or reassigns a row to B: rejected; no foreign-tenant row created.
6. Denied writes leave stock, sale, payment, refund and other business state unchanged; record an audit event when policy requires it.

Record HTTP status, response shape, pre/post hashes or row counts, and audit event ID. Repeat through REST and Edge Functions; SQL editor/service-role results are not proof of client RLS behavior.

## Release gate
`TENANT_ISOLATION_RELEASED=false`.

Only one tenant and one membership are currently evidenced; no second-user JWT has been tested. Policy/grant/function/view catalog snapshots are now captured, but a human-reviewed per-policy/per-action matrix and live REST/Edge Function tests remain incomplete. No production mutation was performed. The catalog snapshot shows most operational tables are intentionally server-only, so the immediate review target is every `dlice-orders` action that uses the service-role client: prove that actor identity, tenant membership, branch assignment, and source/destination tenant equality are checked before each read/write. Do not add permissive client RLS policies to bypass this architecture.
