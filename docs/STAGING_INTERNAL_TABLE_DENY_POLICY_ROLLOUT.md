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

## Audit evidence — 2026-10-27 (read-only)

- Staging project: `higoadrzxnhzbbwhdbmh` only.
- Read-only catalog query confirms all 17 target tables have RLS enabled, zero existing policies, and no direct table grants to `anon` or `authenticated` at the time of inspection.
- The migration is not present in staging migration history; it has not been applied.
- Security Advisor still reports 17 `rls_enabled_no_policy` findings for these tables. The explicit deny policies are intended to close that advisor gap without granting client access.
- **Hold application for now:** the repository connector did not return authoritative evidence that no browser/client code depends on these tables, and authenticated runtime regression tests for allowed Edge Function flows have not been run. This is not a claim that the migration is unsafe; it is a release gate requiring the remaining pre-apply evidence.
- Do not expose secret values. Platform-owner allowlist membership must be compared against an approved identity source using a metadata/boolean check only; if that source cannot be accessed, leave platform-owner bypass unvalidated and tenant isolation unreleased.

## Staging application result — 2026-10-27

- Applied to staging project `higoadrzxnhzbbwhdbmh` as migration `20261027112330_explicit_deny_policies_server_only_tables`.
- Post-apply catalog verification: 17/17 target tables retain RLS, 17/17 have exactly one explicit deny policy, `anon` denied direct SELECT/INSERT/UPDATE/DELETE on 17/17, `authenticated` denied the same operations on 17/17, and `service_role` retains SELECT/INSERT/UPDATE/DELETE on 17/17.
- Security Advisor no longer reports the prior 17 `rls_enabled_no_policy` findings. One unrelated warning remains: Auth leaked-password protection is disabled. Remediation: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- Staging `dlice-orders` Edge Function is now version 60 from PR #58 source, with `TENANT_ISOLATION_RELEASED=false`. Do not treat deployment or this migration as proof of runtime tenant isolation.
- Runtime negative API tests and before/after data snapshots are still outstanding because this connector has no HTTP POST/function-invoke action and no approved authenticated test identities were supplied. No temporary QA accounts were created.
- Production project was not touched.


## Migration history alignment — 2026-10-27

- The migration was applied on staging and recorded by Supabase as version `20261027112330`.
- The repository migration filename has been aligned to `supabase/migrations/20261027112330_explicit_deny_policies_server_only_tables.sql` so local version tracking matches the staging history. This change only renames the tracked file; it does not reapply DDL.
- Production remains untouched. The new file must not be pushed to production as part of this staging-only rollout without a separately approved production migration plan.
