# Staging stock-workflow RPC EXECUTE ACL remediation

**Scope:** staging source only. This migration is not applied to Supabase staging or production by this PR.

## Verified defect

The staging catalog reports explicit EXECUTE grants to `anon` and `authenticated` on five SECURITY DEFINER stock-count/stock-transfer RPCs. `has_function_privilege` returns true for both client roles. The previous table-only revocation migration did not revoke these function grants.

## Remediation

Migration `20261118193000_revoke_public_stock_workflow_rpc_execute.sql` revokes EXECUTE from PostgreSQL `PUBLIC`, `anon`, and `authenticated`, then grants it only to `service_role`. The existing `dlice-orders` Edge Function calls these RPCs with its server-side admin client after action-specific authentication, permission, active membership, and branch-scope checks.

## Required staging verification after independent review

1. Apply this migration only through the approved staging migration process.
2. Verify `has_function_privilege('anon', ...)` and `has_function_privilege('authenticated', ...)` are false for all five functions.
3. Verify `has_function_privilege('service_role', ...)` remains true.
4. Run authenticated positive branch-scoped stock transfer/count flows through `dlice-orders`.
5. Run anonymous and authenticated direct RPC negative probes and confirm denial.
6. Re-run Supabase Security Advisor and retain sanitized evidence.

No function body, business transition, data row, Auth metadata, deployment, release flag, or production resource is changed by the migration source itself.
