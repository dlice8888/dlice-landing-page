# Staging migration reconciliation — 2026-10-25

## Remote migration inventory verified
Supabase staging project `higoadrzxnhzbbwhdbmh` reports 42 applied migrations. The latest four, in remote application order, are:
1. `20261023175347_kitchen_kds_idempotency_modifiers`
2. `20261023175514_tenant_branch_platform_foundation`
3. `20261023175946_tenant_branch_integrity_constraints`
4. `20261023180455_kds_pos_deferred_dispatch`

## PR #40 migration filename drift — unresolved
The PR #40 feature branch currently contains these same-name migrations under different versions:
- `20261023232000_kitchen_kds_idempotency_modifiers.sql`
- `20261023233000_tenant_branch_platform_foundation.sql`
- `20261023180000_tenant_branch_integrity_constraints.sql`
- `20261023181000_kds_pos_deferred_dispatch.sql`

The version numbers do not match the remote migration history, and the first two files sort after the other two. This is a real migration-history mismatch. Schema-object existence does not prove SQL body identity. Before changing filenames, compare each SQL body against the corresponding applied migration definition and review dependencies. Do not apply these migrations again to staging. No already-applied migration was rerun during this reconciliation.

## QA authentication evidence — unresolved
- The owner login succeeded in the recorded procurement run.
- Branch A login failed token issuance with HTTP 400, `invalid_credentials`.
- Expected Branch A username for the workflow is `qa_dlice_staging_branch_a` without the email suffix; the workflow appends `@accounts.dlice.internal`.
- The actual GitHub Environment secret values are masked and cannot be read back through the available connector. Do not reuse the GitHub account password as the QA password. Set a unique QA password on the staging Auth user, then put the same QA-only password in GitHub Environment `staging` as `STAGING_TEST_BRANCH_A_PASSWORD`. Keep the username secret as `qa_dlice_staging_branch_a`.
- Login for both accounts must be retested after secret correction; it is not yet verified for both accounts.

## Workflow scheduling
The repository default branch is `main`. PR #44 was merged to correct both staging E2E workflow schedules and guards to allow scheduled execution from `main` or `staging`, while retaining the explicit staging-mutation confirmation gate for manual execution. These workflows target the staging environment; do not point them at production. A schedule correction is not evidence that an E2E run passed.

## E2E and cleanup evidence — unresolved
- Procurement run `40089857964` failed on Branch A authentication. No passing procurement reconciliation artifact is established.
- KDS/POS/stock run `40089765565` failed; its artifact was not accepted as PASS.
- Positive E2E reruns, reconciliation checks, and fixture-cleanup verification remain required after authentication is corrected. No passing result is claimed here.

## Merge readiness
PR #40 must remain Draft / not merge-ready until:
1. The four migration SQL bodies and dependency order are reconciled against the applied remote versions without rerunning them.
2. Both staging QA accounts pass login using the workflow's exact username convention.
3. Procurement and KDS/POS/stock E2E runs pass with reviewed reconciliation artifacts and verified fixture cleanup.
4. This baseline is updated with run IDs, artifact references, and the observed results.
