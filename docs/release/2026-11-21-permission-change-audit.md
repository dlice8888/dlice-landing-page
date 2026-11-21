# Staging rollout: atomic staff permission audit

Date: 2026-11-21

## Scope

The `admin-set-permissions` action now calls
`public.dlice_update_admin_permissions_audited` instead of issuing a profile
update and a separate best-effort audit insert from the Edge Function.

The database function:
- requires the `service_role` database role;
- validates the actor, target profile, and permission allowlist;
- refuses to modify the platform Owner profile;
- locks the target profile row before reading and changing permissions;
- stores previous and resulting permission sets in `admin_audit_logs`;
- commits the permission update and audit record in the same transaction;
- causes the complete operation to fail and roll back if audit insertion fails.

The Edge Function returns an error if the RPC fails; it does not report a
successful permission change when audit persistence cannot be confirmed.

## Deployment gate

This is a staging-only source change. Do not apply the migration to shared
staging or production and do not deploy the Edge Function until:
1. disposable migration replay succeeds on the exact PR head;
2. pgTAP and source-contract tests pass;
3. an independent reviewer approves the migration and authorization path;
4. staging owner authorization and tenant-scope prerequisites are verified;
5. authorized staging runtime tests cover successful changes, invalid grants,
   Owner protection, unauthorized RPC invocation, and forced audit-write
   failure with rollback.

No production deployment is authorized by this document. Existing tenant
isolation and public tenant routing release flags remain false.

## Test coverage

`supabase/tests/admin_permission_audit.test.sql` covers service-role-only
execution, invalid caller rejection, before/after audit metadata, allowlist
validation, Owner protection, and transaction rollback when audit persistence
fails.

`tests/contracts/admin-permission-audit-contract.test.mjs` verifies that the
Edge Function uses the audited RPC and fails closed on RPC errors.
