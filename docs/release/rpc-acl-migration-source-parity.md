# Staging RPC ACL migration source parity

**Target:** Supabase staging `higoadrzxnhzbbwhdbmh`  
**Applied history version:** `20261119182606`  
**Source path after this PR:** `supabase/migrations/20261119182606_revoke_default_public_function_execute.sql`

## Scope

This PR reconciles the migration filename with the version already recorded in staging. The SQL body is unchanged from the previously tracked source file `20261119160000_revoke_default_public_function_execute.sql`. No SQL is applied or replayed against shared staging by this PR.

## Verified staging state

Read-only post-application query:

| Check | Result |
|---|---:|
| Public functions | 29 |
| EXECUTE available to `anon` | 0 |
| EXECUTE available to `authenticated` | 0 |
| EXECUTE available to `service_role` | 29 |

All 29 current public functions are owned by `postgres`. The `postgres` default function privileges in schema `public` revoke EXECUTE from `PUBLIC`, `anon`, and `authenticated`.

## Remaining scope boundary

The existing `supabase_admin` default ACL still includes client EXECUTE for future objects created under that role. Current inspection found no public functions owned by `supabase_admin`, and the migration execution role for the application migration chain is `postgres`. Do not change internal role membership or privileges speculatively. Confirm the supported Supabase role lifecycle before any separate hardening change.

## Safety and release gates

- No production database, Edge Function, deployment, alias, or environment variable was changed.
- No staging business data was modified.
- Do not reapply this migration; version `20261119182606` is already recorded in staging.
- `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false` remain unchanged.
- This PR does not certify tenant A/B isolation or authorize production promotion.
