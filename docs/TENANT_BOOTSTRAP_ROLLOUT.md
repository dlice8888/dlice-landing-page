# Tenant bootstrap rollout

Initial platform-owner setup and tenant creation now use database RPCs that
write the profile or tenant, active tenant membership with tenant-scoped
permissions, and the audit event in one PostgreSQL transaction. An audit
failure rolls back the database writes.

The database RPC also requires server-controlled `app_metadata.platform_owner`
for initial bootstrap and tenant creation. The Edge Function retains the
separate configured user-ID allowlist check before allowing platform-owner
actions.

The initial Auth user is created before the owner-bootstrap RPC because Supabase
Auth and PostgreSQL do not share a transaction. If the RPC fails, the Edge
Function requests Auth-user cleanup after a definite database rejection and
reports when operator cleanup is required. If the RPC outcome is ambiguous,
the function does not delete the Auth user; an operator must verify both
systems before retrying. No tenant onboarding is enabled by this change:
`TENANT_ISOLATION_RELEASED` remains `false` until the independent tenant
isolation acceptance gate passes.

The migration has disposable-database pgTAP coverage for service-role-only
execution, membership permissions, successful writes, and rollback on audit
failure. Applying the migration to staging still requires independent review
and the applicable release gates.
