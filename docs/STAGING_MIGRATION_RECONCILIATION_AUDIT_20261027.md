# Staging migration reconciliation and runtime access audit

Date: 2026-10-27
Scope: Supabase staging project `higoadrzxnhzbbwhdbmh`, GitHub `staging` at `48e8c591fa3de9089f9cb2ca01ac2f90d8c1e3d8`.
Production project `gdjlkrmlsurcdbwnmqgg` was not accessed or changed.

## Current decision

**No historical SQL was changed and no migration was replayed against shared staging.** The disposable replay exposed an ordering defect: `20261017205317_receipt_payment_notification_gates.sql` ran before `public.orders` existed. I then renamed 12 local migration files to the exact timestamps/names already recorded in the remote ledger, preserving each SQL blob byte-for-byte. This restores the intended order and makes the ledger timestamps align. Supabase's ledger does not store the SQL payload, so these filename matches are provenance/order reconciliation, not proof that the SQL originally applied remotely is byte-identical.

## Ledger inventory

- Repository at `staging`: 44 SQL migration files.
- Staging remote ledger: 45 records.
- Local-only timestamps after reconciliation: 0.
- Remote-only timestamps after reconciliation: 1 (`20261022140302_add_missing_fk_supporting_indexes`).
- Latest migration `20261027112330_explicit_deny_policies_server_only_tables`: aligned between repository and remote ledger.

### Reconciled filename mappings (SQL bytes unchanged)

| Repository migration file after reconciliation | Matching remote ledger record | Source provenance |
|---|---|---|
| `20261017183506_initial_dlice_ordering_schema.sql` | `20261017183506_initial_dlice_ordering_schema` | Commit `791a9fcf09a24c66dbe51db70cd3d7caa2386701`. |
| `20261017183509_index_ordering_foreign_keys.sql` | `20261017183509_index_ordering_foreign_keys` | Commit `40a620319d323288102cfe9a927e9b6921a38bab`. |
| `20261017183535_atomic_checkout_and_private_payment_proofs.sql` | `20261017183535_atomic_checkout_and_private_payment_proofs` | Source commit `8864f0ad9c24ab7d26e9c15891d3c09e56bdf3fc`, followed by fix `466603eee3d16b77b4e7931f7df2fa3d2437be64`. |
| `20261017183537_seed_dlice_catalog.sql` | `20261017183537_seed_dlice_catalog` | Source commit `03f1927168b578d6ab64c5bc7572ed53843c3638`, followed by fix `24d9af7108254ac1074b7c48847058edbbb8116f`. |
| `20261017183540_admin_role_permissions.sql` | `20261017183540_admin_role_permissions` | Commit `e87152ee9f1d82b09f66d45a7b804c54f37a5c16`. |
| `20261017183542_product_catalog_storage.sql` | `20261017183542_product_catalog_storage` | Commit `bfa8aa14f2b87f9596db9f5b280e6caba5d3a758`. |
| `20261017184921_admin_username_accounts.sql` | `20261017184921_admin_username_accounts` | Commit `b1e72fb0fc1cc230090ef393b4d62c82a807d5c5`. |
| `20261020160307_lock_internal_table_rls.sql` | `20261020160307_lock_internal_table_rls` | Source commit `caa09630e42c321c22db5432bd2bcdc1eaf57c27`. |
| `20261021151524_index_remaining_erp_foreign_keys.sql` | `20261021151524_index_remaining_erp_foreign_keys` | Source commit `5b24e8beca02233791de0f58e13b08420a99a6fd`; creates 34 named indexes, all present in the live catalog. |
| `20261023175347_kitchen_kds_idempotency_modifiers.sql` | `20261023175347_kitchen_kds_idempotency_modifiers` | Source commit `f6db219e512a0a59c1d9ea39c2c2b75b17011bc1`. |
| `20261023175514_tenant_branch_platform_foundation.sql` | `20261023175514_tenant_branch_platform_foundation` | Same source commit `f6db219e512a0a59c1d9ea39c2c2b75b17011bc1`. |
| `20261023175946_tenant_branch_integrity_constraints.sql` | `20261023175946_tenant_branch_integrity_constraints` | Same source commit `f6db219e512a0a59c1d9ea39c2c2b75b17011bc1`. |
| `20261023180455_kds_pos_deferred_dispatch.sql` | `20261023180455_kds_pos_deferred_dispatch` | Same source commit `f6db219e512a0a59c1d9ea39c2c2b75b17011bc1`. |

The rename operations changed filenames only; the migration SQL content was preserved. A remote migration ledger record does not expose the SQL originally applied, so final SQL equivalence still requires a trusted deployment artifact or migration log.

### Remaining remote-only migration

- `20261022140302_add_missing_fk_supporting_indexes`

This record has no exact local migration file. The 34 indexes in `20261021151524_index_remaining_erp_foreign_keys.sql` are present, but that is not proof that the remote-only migration's complete DDL is represented. Do not delete the ledger row or invent a matching file. Determine the additional index definitions from a trusted migration artifact or compare the live catalog to all repository-declared index definitions before creating a forward-only replacement.

## Live catalog audit on staging

### Indexes

- 34/34 indexes declared by `20261021151524_index_remaining_erp_foreign_keys.sql` exist under the expected names in `pg_indexes`.
- A separate foreign-key/index coverage query still finds 26 FK constraints without an index whose leading columns cover the FK. This includes composite tenant/branch references; index existence must be evaluated against column order, not only index names. Do not create blanket duplicate indexes. Generate a reviewed follow-up index migration only after confirming query plans, constraints, and existing composite coverage.

### Constraints

The catalog confirms tenant/branch composite consistency constraints are present, including:
- `branches(tenant_id, id)` unique target.
- `warehouses(tenant_id, branch_id)` → `branches(tenant_id, id)`.
- `integration_outbox(tenant_id, branch_id)` → `branches(tenant_id, id)`.
- `inventory_waste_events(tenant_id, branch_id)` → `branches(tenant_id, id)`.
- `shift_handover_records(tenant_id, branch_id)` → `branches(tenant_id, id)`.
- `branch_inventory(branch_id, warehouse_id)` → `warehouses(branch_id, id)`.

### Functions and triggers

Catalog inspection found several `SECURITY DEFINER` stock-transfer/count RPCs. Their current execute privileges are revoked from `anon` and `authenticated` and granted to `service_role`; keep reviewing their function bodies, fixed `search_path`, and caller authorization as a separate security review. The branch-setting versioning trigger exists and calls `dlice_version_branch_setting()`. The function is not client-executable.

### Explicit deny policies

For all 17 target tables, staging catalog verification shows:
- RLS enabled: 17/17.
- `deny_direct_client_access` policy: 17/17.
- Direct table privileges for anon/authenticated SELECT/INSERT/UPDATE/DELETE: absent for all 17/17.

## REST runtime denial evidence (no test accounts created)

Executed against the staging REST API using only the public/publishable API key, with no user JWT and no service-role credential:

- 17 target tables × GET/POST/PATCH/DELETE = **68/68 denied**.
- Every response was HTTP 401 with PostgreSQL code `42501` (permission denied).
- POST/PATCH bodies contained only empty/minimal sentinel payloads; DELETE/PATCH filters used the all-zero UUID. No valid row target was supplied and all requests were rejected before mutation.

Privileged read-only count snapshots before and after the 68 REST attempts matched exactly:

| Table | Before | After |
|---|---:|---:|
| tenants | 1 | 1 |
| tenant_memberships | 1 | 1 |
| branches | 154 | 154 |
| warehouses | 154 | 154 |
| admin_audit_logs | 270 | 270 |
| orders | 7 | 7 |
| pos_sales | 6 | 6 |
| stock_movements | 24 | 24 |
| integration_outbox | 0 | 0 |
| inventory_waste_events | 0 | 0 |

This establishes direct anonymous REST CRUD denial and no observed row-count change for the sampled operational tables. It does not establish signed-in user authorization or cross-tenant isolation.

## Identity and release gate

Current staging snapshot:
- Tenant count: 1.
- Active tenant memberships: 1.
- Active admin profiles: 3.
- Active profiles with trusted `app_metadata.platform_owner=true`: 0.
- No Supabase development branch was listed under staging; the GitHub-hosted disposable replay is the chosen no-shared-database test path.

Therefore:
- Keep `TENANT_ISOLATION_RELEASED = false`.
- Do not create temporary QA identities; the requested approach is to use already-configured, existing identities only.
- Authenticated branch-boundary tests need an existing branch-scoped JWT and a real second branch.
- A true cross-tenant test cannot be meaningful until a second tenant and a legitimately authorized test identity already exist. Do not fabricate a JWT or create a tenant/account solely to make the test pass.
- The authenticated negative workflow attempted sign-in with the already-configured branch-account secrets and was blocked by HTTP 400 `invalid_credentials` before any branch/finance request. No user was created. Run: https://github.com/dlice8888/dlice-landing-page/actions/runs/40499598072
- A true cross-tenant test cannot run against this staging state because there is only one tenant. Do not create a second tenant or temporary identity just to make the suite pass.

## Disposable migration replay

This PR adds `.github/workflows/disposable-migration-replay.yml`. On a PR to `staging`, GitHub Actions will create a temporary local Supabase stack on its hosted runner, copy the repository migration files into that isolated stack, run `supabase db reset`, and print `supabase migration list`. It will not connect to staging or production.

The Vercel sandbox had no Docker executable, so the replay runs on an isolated GitHub-hosted runner with local Supabase containers. The first attempt found the ordering defect above; after renaming the 12 files, the latest replay must pass before this PR can be considered migration-order verified. No migration DDL was applied to staging and no paid Supabase branch was created.

## Next safe actions

1. Review the latest disposable migration replay; fix any remaining ordering error in a follow-up PR and rerun only on the disposable local stack.
2. Retrieve trusted SQL for the one remote-only index migration and reconcile its resulting index definitions without editing the remote ledger by guesswork.
3. Restore valid credentials for an existing authorized branch-scoped test identity; do not provision users. Rerun branch/permission tests and capture before/after snapshots.
4. Run cross-tenant negative tests only when a second tenant and legitimate existing identities are available.
5. Keep the release gate false until trusted platform-owner identity/allowlist and authenticated tenant/branch negative tests pass.


## PR CI follow-up (2026-10-27)

- The reusable REST deny-policy workflow passed on PR head `a12b6244444539c50562d1ff1a443574c224d975`: 68/68 requests returned HTTP 401 with SQLSTATE `42501`. Run: https://github.com/dlice8888/dlice-landing-page/actions/runs/40499459278
- The authenticated negative workflow was executed using the configured existing branch-account secrets only. Sign-in returned HTTP 400 `invalid_credentials`; the workflow exited BLOCKED before any branch/finance request and did not provision an account. Run: https://github.com/dlice8888/dlice-landing-page/actions/runs/40499459240
- The first disposable replay failed because `receipt_payment_notification_gates` ran before `public.orders` existed. The 12 timestamp/name corrections were applied with SQL bytes unchanged, and the KDS contract test's hard-coded file paths were updated in the same PR. Latest replay: https://github.com/dlice8888/dlice-landing-page/actions/runs/40500360730 (check final conclusion before merge).
