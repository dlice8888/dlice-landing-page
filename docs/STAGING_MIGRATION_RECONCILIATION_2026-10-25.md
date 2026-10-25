# Staging migration reconciliation — 2026-10-25

## Remote migration inventory verified
Supabase staging project `higoadrzxnhzbbwhdbmh` reports these applied versions:
- `20261023175347_kitchen_kds_idempotency_modifiers`
- `20261023175514_tenant_branch_platform_foundation`
- `20261023175946_tenant_branch_integrity_constraints`
- `20261023180455_kds_pos_deferred_dispatch`

## Repository mismatch
The PR #40 feature branch currently contains equivalent named migration files under different versions:
- `20261023232000_kitchen_kds_idempotency_modifiers.sql`
- `20261023233000_tenant_branch_platform_foundation.sql`
- `20261023180000_tenant_branch_integrity_constraints.sql`
- `20261023181000_kds_pos_deferred_dispatch.sql`

These timestamps do not match the remote migration inventory and do not preserve the applied order. Do not apply these files again to staging until the repository history is reconciled. The live schema confirms the KDS/idempotency/offline/tenant tables exist, but that alone does not prove SQL body identity.

## QA authentication evidence
- Both owner and Branch A Auth users exist and have confirmed emails/password hashes.
- Procurement E2E rerun failed at Branch A Auth token issuance: HTTP 400 instead of 200.
- The workflow masks environment values, so the actual username/password secret values cannot be compared from logs. No password was changed and no secret value was exposed.

## Workflow scheduling
- GitHub repository default branch is `main`.
- The procurement schedule PR currently targets `staging` and its job condition is restricted to `refs/heads/staging`; it therefore cannot reliably schedule from the repository default branch.
- KDS/POS/stock workflow on the PR feature branch also requires schedule/dispatch alignment with `main`.

## Acceptance state
No positive procurement or KDS/POS/stock E2E PASS is established by this checkpoint. Keep PR #40 Draft until migration history, QA auth, and positive E2E evidence are reconciled.
