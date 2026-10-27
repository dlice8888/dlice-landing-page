# Staging migration reconciliation and runtime access audit

Date: 2026-10-27
Scope: Supabase staging project `higoadrzxnhzbbwhdbmh`, GitHub `staging` at `48e8c591fa3de9089f9cb2ca01ac2f90d8c1e3d8`.
Production project `gdjlkrmlsurcdbwnmqgg` was not accessed or changed.

## Current decision

**Do not rename or replay the historical mismatches against shared staging yet.** Supabase's migration ledger records a version and name, not a recoverable copy of the SQL applied at that version. The repository has historical source commits for the current local files, but the 13 remote-only ledger records do not have corresponding repository files to compare byte-for-byte. A matching name or a similar resulting object is not enough to assert SQL equivalence.

This PR adds guardrails/tests and records the mapping evidence; it does not mutate the database or falsely mark the ledger as reconciled.

## Ledger inventory

- Repository at `staging`: 44 SQL migration files.
- Staging remote ledger: 45 records.
- Local-only timestamps: 12.
- Remote-only timestamps: 13.
- Latest migration `20261027112330_explicit_deny_policies_server_only_tables`: aligned between repository and remote ledger.

### Candidate mappings by name

| Local file | Remote ledger record | Provenance / conclusion |
|---|---|---|
| `20261018000000_initial_dlice_ordering_schema.sql` | `20261017183506_initial_dlice_ordering_schema` | Local file originated in commit `791a9fcf09a24c66dbe51db70cd3d7caa2386701`. Name candidate only; applied remote SQL not independently retrievable. |
| `20261018001000_index_ordering_foreign_keys.sql` | `20261017183509_index_ordering_foreign_keys` | Local file originated in commit `40a620319d323288102cfe9a927e9b6921a38bab`. Name candidate only. |
| `20261018002000_atomic_checkout_and_private_payment_proofs.sql` | `20261017183535_atomic_checkout_and_private_payment_proofs` | Local source commits `8864f0ad9c24ab7d26e9c15891d3c09e56bdf3fc` and follow-up fix `466603eee3d16b77b4e7931f7df2fa3d2437be64`. Must compare the final source snapshot with a trusted deployment artifact before declaring equivalence. |
| `20261018003000_seed_dlice_catalog.sql` | `20261017183537_seed_dlice_catalog` | Local source commits `03f1927168b578d6ab64c5bc7572ed53843c3638` and follow-up fix `24d9af7108254ac1074b7c48847058edbbb8116f`. Data-seed effects require separate verification. |
| `20261018004000_admin_role_permissions.sql` | `20261017183540_admin_role_permissions` | Local source commit `e87152ee9f1d82b09f66d45a7b804c54f37a5c16`. Name candidate only. |
| `20261018005000_product_catalog_storage.sql` | `20261017183542_product_catalog_storage` | Local source commit `bfa8aa14f2b87f9596db9f5b280e6caba5d3a758`. Name candidate only. |
| `20261018006000_admin_username_accounts.sql` | `20261017184921_admin_username_accounts` | Local source commit `b1e72fb0fc1cc230090ef393b4d62c82a807d5c5`. Name candidate only. |
| `20261020160000_lock_down_internal_table_rls.sql` | `20261020160307_lock_internal_table_rls` | Local source commit `caa09630e42c321c22db5432bd2bcdc1eaf57c27`. Local source has 12-table RLS/revoke/service-role policy statements. The remote SQL payload is unavailable, so don't treat timestamp/name drift as proof of identical DDL. |
| `20261021151524_index_remaining_erp_foreign_keys.sql` | `20261022140302_add_missing_fk_supporting_indexes` | Local source commit `5b24e8beca02233791de0f58e13b08420a99a6fd` creates 34 named indexes. All 34 named indexes exist in the staging catalog. This proves those index objects exist, not that they cover every statement from the remote-only migration. |
| `20261023232000_kitchen_kds_idempotency_modifiers.sql` | `20261023175347_kitchen_kds_idempotency_modifiers` | Local file entered through commit `f6db219e512a0a59c1d9ea39c2c2b75b17011bc1`; compare exact file blob history and dependency ordering before mapping. |
| `20261023233000_tenant_branch_platform_foundation.sql` | `20261023175514_tenant_branch_platform_foundation` | Same source commit `f6db219e512a0a59c1d9ea39c2c2b75b17011bc1`; name candidate only. |
| `20261023180000_tenant_branch_integrity_constraints.sql` | `20261023175946_tenant_branch_integrity_constraints` | Same source commit `f6db219e512a0a59c1d9ea39c2c2b75b17011bc1`; name candidate only. |
| `20261023181000_kds_pos_deferred_dispatch.sql` | `20261023180455_kds_pos_deferred_dispatch` | Same source commit `f6db219e512a0a59c1d9ea39c2c2b75b17011bc1`; name candidate only. |

### Remote-only ledger entries without exact local filenames

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

The corresponding local-only timestamp files are the candidates in the mapping table above. No historical SQL file was renamed, removed, or replayed in this PR.

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
- No development branch/disposable Supabase branch is currently listed under staging.

Therefore:
- Keep `TENANT_ISOLATION_RELEASED = false`.
- Do not create temporary QA identities; the requested approach is to use already-configured, existing identities only.
- Authenticated branch-boundary tests need an existing branch-scoped JWT and a real second branch.
- A true cross-tenant test cannot be meaningful until a second tenant and a legitimately authorized test identity already exist. Do not fabricate a JWT or create a tenant/account solely to make the test pass.
- Full authenticated REST/JWT branch and cross-tenant tests have **not** been run in this pass because no usable pre-existing user access token was available to this runtime; the connector also cannot read GitHub environment secrets or dispatch the existing workflow.

## Disposable migration replay

This PR adds `.github/workflows/disposable-migration-replay.yml`. On a PR to `staging`, GitHub Actions will create a temporary local Supabase stack on its hosted runner, copy the repository migration files into that isolated stack, run `supabase db reset`, and print `supabase migration list`. It will not connect to staging or production.

The current Vercel sandbox has no Docker executable, and the Supabase staging project has no existing development branch. I did not reset staging or create a paid Supabase branch. The disposable GitHub Actions replay is configured in this PR but its CI result must be reviewed before any historical filename reconciliation is merged.

## Next safe actions

1. Review this PR and wait for the disposable migration replay job.
2. If replay fails, repair the local migration sequence in a follow-up PR and repeat the isolated replay; do not alter the remote ledger by guesswork.
3. Retrieve a trusted SQL artifact or deployment log for each remote-only migration, compare exact SQL and resulting catalog definitions, and then decide which local files can safely be renamed/recovered.
4. For authenticated runtime tests, use existing authorized staging identities/tokens already configured for testing. Capture before/after snapshots via privileged read-only queries; no account provisioning or business writes.
5. Keep the release gate false until trusted platform-owner identity/allowlist and authenticated tenant/branch negative tests pass.


## PR CI follow-up (2026-10-27)

- The reusable REST deny-policy workflow passed on PR head `a12b6244444539c50562d1ff1a443574c224d975`: 68/68 requests returned HTTP 401 with SQLSTATE `42501`. Run: https://github.com/dlice8888/dlice-landing-page/actions/runs/40499459278
- The authenticated negative workflow was executed using the configured existing branch-account secrets only. Sign-in returned HTTP 400 `invalid_credentials`; the workflow exited BLOCKED before any branch/finance request and did not provision an account. Run: https://github.com/dlice8888/dlice-landing-page/actions/runs/40499459240
- The disposable migration replay workflow was corrected after its first attempt exposed a missing-directory error. The corrected run is pending at the time this addendum was written; do not treat the migration chain as replay-verified until that run completes successfully.
