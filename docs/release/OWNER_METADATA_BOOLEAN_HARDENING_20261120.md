# Owner metadata boolean and service-role RPC hardening

Date: 2026-11-20
Target: staging source only
Migration: `20261124121039_harden_owner_metadata_boolean.sql`

## Why
The original #102 bootstrap RPCs extracted `platform_owner` as text. That makes JSON boolean `true` and JSON string `"true"` indistinguishable. D’Lice authorization requires the boolean value. The Edge Function already compares `app_metadata.platform_owner === true`; the database RPCs must enforce the same type boundary independently.

The #102 and #105 functions also use Supabase's deprecated `auth.role()` helper. This forward-only migration checks the JWT role claim through `auth.jwt() ->> 'role'` instead.

## Scope
- Harden `dlice_bootstrap_initial_owner`.
- Harden `dlice_create_tenant_with_owner`.
- Harden `dlice_manage_branch_checklist`.
- Preserve function signatures, SECURITY INVOKER, service-role-only EXECUTE grants, transactional audit writes and optimistic checklist versioning.
- Add a database contract proving JSON boolean `true` differs from JSON string `"true"`.

## Migration order
`20261124121039` follows #105 (`20261124121032`) and precedes #109 (`20261124121046`). Do not reorder or edit already merged migrations. Apply one migration at a time only after P0 runtime and release-protection gates pass.

## Validation
- Free quality checks include `tests/contracts/owner-metadata-boolean-contract.test.mjs`.
- Disposable Supabase migration replay runs `supabase/tests/owner_metadata_boolean.test.sql`.
- No shared staging or production migration is applied by this PR.

## Release safety
No Auth user, Owner metadata, tenant, membership, branch assignment, Edge Function or production setting is changed. The existing Owner identity must still be updated through Supabase Auth Admin; this migration does not perform that action.
