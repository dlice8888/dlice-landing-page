# D'Lice staging tenant-isolation audit (2026-10-28)

## Scope and evidence

Target: Supabase staging project `higoadrzxnhzbbwhdbmh`, repository branch `staging`.

Read-only evidence collected for this report:
- Supabase table inventory returned 64 tables in schema `public`.
- All 64 listed tables reported `rls_enabled=true`.
- Row counts reported by the inventory: `tenants=1`, `tenant_memberships=1`, `branches=154`.
- Staging has one active Edge Function listed by the Supabase connector: `dlice-orders`, version 60, `verify_jwt=false`.
- Security Advisor still reports `auth_leaked_password_protection` as WARN. This is not a tenant-isolation result, but remains a staging security gate.
- Existing migrations include `20261023233000_tenant_branch_platform_foundation.sql`, `20261023180000_tenant_branch_integrity_constraints.sql`, and `20261027112330_explicit_deny_policies_server_only_tables.sql`.

This report does **not** claim that all RLS policies are correct, that runtime JWT tests passed, or that production is safe.

## Ownership classification

### Canonical roots

- `public.tenants.id`: tenant root.
- `public.tenant_memberships(tenant_id,user_id)`: user-to-tenant membership and role/status. Auth identity must be `auth.users.id`; do not trust a client-supplied user ID.
- `public.branches(tenant_id,id)`: canonical branch-to-tenant ownership. The composite key `(tenant_id,id)` is protected by the existing integrity migration.
- `public.branch_assignments(user_id,branch_id,...)`: branch-level scope, subject to inspection of its exact policy and application semantics.

### Tables with direct tenant ownership columns

The live schema inventory reports `tenant_id` on:
`tenants`, `tenant_memberships`, `tenant_invites`, `branches`, `warehouses`, `branch_settings`, `shift_handover_records`, `inventory_waste_events`, `integration_connections`, `integration_outbox`, and `backup_restore_runs`.

The existing migration `20261027112330_explicit_deny_policies_server_only_tables.sql` explicitly revokes direct `anon`/`authenticated` table access and creates deny-all policies for platform/server-only tables including tenants, memberships, invites, warehouses, branch settings, shift handovers, waste events, integrations, and backup/restore records. Do not replace these with direct client access without a separately reviewed authorization design.

### Tables whose ownership must be inherited

Many operational tables lack `tenant_id` and must be scoped through a validated relationship to a parent or branch. Examples include:
- order chain: `orders -> branches`, then `order_items`, `payment_records`, `order_status_history`, `order_reservations`;
- POS chain: `pos_sales -> branches`, `pos_sale_items -> pos_sales`, `pos_shifts -> branches`;
- kitchen/production: `kitchen_tickets -> branches/orders`, ticket items through ticket/order item, production batches/consumptions through branch/batch;
- inventory/procurement: branch inventory, stock movements, purchase orders/receipts/requisitions and their item rows, stock transfers/counts and child rows;
- finance: branch expenses, cash reconciliations, journal entries, refunds, settlements and settlement items through their parent/branch relations.

For every child table, the policy must follow the authoritative parent FK; never authorize by an unvalidated client-supplied tenant ID. Where a row has both tenant and branch columns, require them to match the same `branches(tenant_id,id)` row. Existing composite integrity constraints cover several platform tables, but do not establish policy coverage for every operational table.

### Ownership decision required before tenant policy changes

The current schema has no direct `tenant_id` on `products`, `recipes`, `recipe_ingredients`, `product_modifiers`, `job_positions`, and `suppliers`. The intended ownership model for these catalog/configuration tables must be explicitly decided:
- shared/global catalog, with intentionally global read rules; or
- tenant-owned, requiring `tenant_id` plus migration/backfill and tenant-scoped policies.

Do not label these tables as cross-tenant leaks until product ownership is decided. Equally, do not treat them as tenant-isolated without evidence.

## RLS, grants, views, RPC, and Edge Function audit status

- **RLS enabled:** inventory says yes for all 64 public tables. RLS enabled alone does not prove policy correctness.
- **Explicit direct-client denials:** confirmed in the existing server-only migration for the listed platform tables. These tables are intended to be accessed through trusted server operations.
- **Grants and full policy expressions:** not completely verified by the available read-only schema inventory in this run.
- **Views/materialized views:** not inventoried in this run.
- **RPC/function security mode and execute grants:** not completely inventoried in this run. The existing migration revokes execution on selected trigger-only functions; every exposed RPC still needs review for `SECURITY DEFINER`, fixed `search_path`, execute grants, and tenant authorization.
- **Edge Functions:** staging inventory reports `dlice-orders` v60 with `verify_jwt=false`. Therefore every action must authenticate and authorize the bearer token itself; inspect the entire handler and prove that it never treats the presence of a user ID or branch ID as authorization. This audit did not execute its endpoints.
- **Auth:** Security Advisor still reports leaked-password protection disabled.

## Required follow-up migration design

Do not apply a broad generated policy migration until policy expressions, grants, RPCs, and all foreign-key chains are inspected. The next reviewed migration should:
1. add/repair canonical membership and branch authorization helpers only after verifying role and assignment semantics;
2. use `auth.uid()` and active membership for tenant scope;
3. enforce branch assignments for branch-limited roles;
4. enforce parent-chain scope on child tables;
5. use both `USING` and `WITH CHECK` for updates, and `WITH CHECK` for inserts;
6. retain deny-all client access for server-only tables;
7. set fixed `search_path` and minimal execute grants for any `SECURITY DEFINER` helper;
8. add integrity constraints where composite tenant/branch FKs are missing, after checking/backfilling data;
9. be replayable and tested against a clean staging branch before applying to shared staging.

## Required two-tenant acceptance tests

Fixture prerequisites: two real Auth users, two valid tenants, at least one active branch per tenant, active memberships, and explicit branch assignments. Never use service-role credentials as the tested identity.

For each test, record HTTP status, response body shape, pre/post row counts or hashes, and relevant audit event ID:
1. User A reads a known Tenant B branch/resource: zero rows or explicit denial; no sensitive fields returned.
2. User A attempts to update a known Tenant B row: denied/no visible mutation; before/after snapshot unchanged.
3. User B requests Tenant A branch by ID through REST and each relevant Edge Function: denied/no data leak.
4. User B reads and performs an allowed operation on their own branch: succeeds according to role.
5. User A attempts cross-tenant insert or tenant/branch reassignment: rejected by policy/constraint; no orphan or foreign-tenant row created.
6. A denied write leaves inventory, sale, payment, refund, and audit-relevant business state unchanged; record security audit event where policy requires it.

Repeat through PostgREST with each user's own JWT and through each Edge Function endpoint. Do not use the SQL editor/service role as proof of client RLS behavior.

## Current release gate

`TENANT_ISOLATION_RELEASED=false`.

Reason: only one tenant and one membership are currently evidenced; no second-user JWT has been used; policy/grant/view/RPC inventory and live REST/Edge Function negative tests remain incomplete. No production mutation was performed by this audit.
