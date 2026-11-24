# Staging stock-transfer tenant boundary — 24 November 2026

## Scope
This is a source-only remediation for PR #138 on `audit/stock-transfer-tenant-boundary-20261124`. It does not apply a migration to shared Supabase staging, deploy an Edge Function, or change production.

## Security invariant
Stock transfers are intra-tenant only. The source and destination branches must both exist, have non-null tenant IDs, and belong to the same tenant. Platform Owner privileges do not bypass this inventory boundary.

## API path
The `erp-create-stock-transfer` handler now:
1. verifies the actor has access to both requested branches;
2. independently reads both branch tenant IDs;
3. fails closed if either branch cannot be resolved or has a null tenant;
4. rejects unequal tenant IDs before invoking `erp_create_stock_transfer`.

The transition handler applies the same tenant equality rule to approve, pick, ship, receive, reconcile and cancel. Database triggers in the forward-only migration protect insert/update paths and serialize the tenant check against branch tenant reassignment.

## Required verification
- API contract: creation and every transition reject cross-tenant scope before RPC.
- Disposable PostgreSQL trigger regression: same-tenant allowed; cross-tenant insert/update rejected; branch tenant reassignment with transfer history rejected; concurrent reassignment race rejected.
- Exact-head quality checks and full disposable migration replay.
- Current staging P01–P09 acceptance remains required before any staging application or deployment.

## Release boundary
- `TENANT_ISOLATION_RELEASED=false`
- `PUBLIC_TENANT_ROUTING_RELEASED=false`
- No shared staging migration, Edge Function deployment, data mutation, production change, auto-merge or force-push is authorized by this PR.
