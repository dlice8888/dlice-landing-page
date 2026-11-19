# Public RPC EXECUTE hardening

**Scope:** staging database migration only. No production changes.

## Finding

Live staging catalog inspection found that PostgreSQL default privileges for `postgres` granted EXECUTE on new public-schema functions to `anon` and `authenticated`. All 29 existing public functions are owned by `postgres`; none are owned by `supabase_admin`. The three trigger-only functions also still had client EXECUTE grants despite the earlier migration-history entry.

## Remediation

- Revoke default EXECUTE for `PUBLIC`, `anon`, and `authenticated` for future functions created by `postgres` in schema `public`.
- Revoke direct client EXECUTE from every existing function in schema `public`.
- Grant `service_role` EXECUTE on every existing public-schema function; trusted Edge Function calls already use its server-side service-role client.
- Keep explicit revocations for the historically exposed trigger-only functions.
- Add pgTAP checks for current function privileges and the `postgres` default ACL.
- Run `supabase test db` as part of disposable migration replay.

## Scope and limits

The `supabase_admin` default ACL is not changed because the migration executor is not authorized to alter that role's defaults; no current public function is owned by that role. The migration changes grants only: it does not change function bodies, RLS policies, business data, or Auth metadata. Tenant isolation release flags remain false.
