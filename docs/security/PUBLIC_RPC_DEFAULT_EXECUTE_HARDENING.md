# Public RPC default EXECUTE hardening

**Scope:** staging database migration only. No production changes.

## Finding

Staging's PostgreSQL default privileges for both `postgres` and `supabase_admin` granted function EXECUTE to `anon` and `authenticated` in schema `public`. A read-only catalog query also found that the three trigger-only functions `erp_guard_journal_period()`, `erp_guard_refund_amount()`, and `set_updated_at()` still had client EXECUTE grants, despite the earlier migration history entry.

## Remediation in this change

- Revoke default EXECUTE for `PUBLIC`, `anon`, and `authenticated` for future functions created by `postgres` and `supabase_admin` in schema `public`.
- Preserve the existing `service_role` default EXECUTE grant used by trusted Edge Functions.
- Revoke client EXECUTE from the three trigger-only functions again.
- Add pgTAP checks for current trigger-function privileges, both default-privilege owners, and a newly created function.
- Run `supabase test db` as part of disposable migration replay.

## Safety

This does not revoke EXECUTE from all existing application RPCs. Existing invoker RPCs remain subject to RLS; their per-function grants require a separate call-site and authorization audit before changing. No business data or Auth metadata is changed. Tenant isolation release flags remain false.
