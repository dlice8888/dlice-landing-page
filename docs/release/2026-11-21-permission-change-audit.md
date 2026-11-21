# Staging rollout: atomic staff permission audit

Date: 2026-11-21

## Scope

The staff-access mutation paths now use transaction-scoped audited RPCs instead of split profile writes and best-effort audit inserts from the Edge Function:
- `admin-set-permissions` → `dlice_update_admin_permissions_audited`.
- `admin-create-staff` → `dlice_create_admin_profile_audited` (Auth user creation remains a separate Auth Admin operation; uncertain RPC outcomes fail closed and are not auto-deleted).
- `admin-set-profile-role` → `dlice_update_admin_profile_role_audited` (including branch-worker assignment and tenant-membership checks).
- `admin-set-active` → `dlice_set_admin_profile_active_audited`.

The database functions:
- require the `service_role` database role;
- validates the actor, target profile, and permission allowlist;
- refuses to modify the platform Owner profile;
- locks the target profile row before reading and changing permissions;
- store before/after permission sets, profile role, active state, or profile creation snapshot in `admin_audit_logs`;
- commit each profile mutation and its audit record in the same transaction;
- make retries idempotent for unchanged profile creation/role/active state;
- reject branch-worker role changes without active same-tenant branch assignments;
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

`supabase/tests/admin_profile_mutation_audit.test.sql` adds 18 pgTAP assertions
for atomic staff profile creation, idempotent retry, permission allowlist,
role changes, branch assignment prerequisites, active/inactive state changes,
Owner protection, and RPC ACLs.

Remaining audit work: Auth password resets and tenant-membership/branch-assignment
mutations still need a full mutation inventory and append-only audit/transaction
review; this PR does not claim every identity or tenant permission mutation is
already covered.

`tests/contracts/admin-permission-audit-contract.test.mjs` verifies that the
Edge Function uses the audited RPC and fails closed on RPC errors.
