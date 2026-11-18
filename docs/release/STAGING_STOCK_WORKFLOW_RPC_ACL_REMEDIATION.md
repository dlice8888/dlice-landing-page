# Staging stock-workflow RPC EXECUTE ACL remediation

**Scope:** staging only. The ACL migration was applied to Supabase staging as migration version `20261118165519` (migration name `20261118193000_revoke_public_stock_workflow_rpc_execute`) and verified. It has not been applied to production.

## Verified defect

The staging catalog reports explicit EXECUTE grants to `anon` and `authenticated` on five SECURITY DEFINER stock-count/stock-transfer RPCs. `has_function_privilege` returns true for both client roles. The previous table-only revocation migration did not revoke these function grants.

## Remediation

Migration `20261118165519_20261118193000_revoke_public_stock_workflow_rpc_execute.sql` revokes EXECUTE from PostgreSQL `PUBLIC`, `anon`, and `authenticated`, then grants it only to `service_role`. The existing `dlice-orders` Edge Function calls these RPCs with its server-side admin client after action-specific authentication, permission, active membership, and branch-scope checks.

## Staging verification completed

1. **Completed:** staging migration recorded as version `20261118165519`.
2. **PASS:** `anon` EXECUTE is false for all five functions.
3. **PASS:** `authenticated` EXECUTE is false for all five functions.
4. **PASS:** `service_role` EXECUTE remains true for all five functions.
5. **PASS:** Supabase Security Advisor no longer reports the five stock RPCs as publicly or authenticated-executable.
6. **Pending:** authenticated positive branch-scoped stock count/transfer flows through `dlice-orders`.
7. **Pending:** anonymous and authenticated direct RPC negative HTTP probes confirm denial.

No function body, business transition, business data row, Auth metadata, deployment, release flag, or production resource was changed. The migration changes staging function privileges only.
