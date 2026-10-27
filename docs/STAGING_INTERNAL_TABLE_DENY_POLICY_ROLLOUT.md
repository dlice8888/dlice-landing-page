# Staging rollout — explicit deny policies for server-only tables

## Scope
Apply only to Supabase staging project `higoadrzxnhzbbwhdbmh`. Do not apply to production project `gdjlkrmlsurcdbwnmqgg`.

## Change
Migration `20261025010000_explicit_deny_policies_server_only_tables.sql` preserves RLS on 17 server-only tables, revokes direct `anon` and `authenticated` table grants, and creates explicit deny-all policies for those client roles. Trusted server-side Edge Function requests using `service_role` are expected to remain the only supported access path for these tables.

## Pre-apply checks
- [ ] Review the exact staging policy and grant inventory against all 17 tables.
- [ ] Confirm no browser/client code directly queries these server-only tables.
- [ ] Confirm the Edge Function uses server-side authorization and validates actor, tenant, and branch scope before service-role queries.
- [ ] Verify migration is not already recorded in staging migration history.
- [ ] Confirm this change does not target production.

## Post-apply checks
- [ ] Re-run Supabase Security Advisor and confirm the 17 `rls_enabled_no_policy` findings are cleared.
- [ ] Anonymous and authenticated direct Data API reads/writes are denied for each table.
- [ ] Existing authorized Edge Function flows still work, including KDS ticket reads, offline idempotency, waste recording, shift handover, branch settings, integration outbox, and tenant membership operations.
- [ ] Re-run the bounded staging authorization/contract suite and inspect failures.
- [ ] Record migration version, policy/grant snapshots, test links, and rollback decision.

## Important limitations
Explicit deny policies and revoked client grants are defense-in-depth for server-only tables. They do not prove tenant isolation inside the service-role Edge Function because service-role database access bypasses RLS. Cross-tenant isolation remains unreleased until authenticated negative read/write tests prove denial and no side effects for every tenant-scoped action.

## Rollback
Do not rollback by granting broad client access. If an authorized Edge Function workflow breaks, stop the rollout and diagnose its server-side access path. Any rollback must be a separately reviewed staging-only migration that preserves client denial and auditability.
