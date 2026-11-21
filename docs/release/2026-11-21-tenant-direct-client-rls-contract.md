# Tenant direct-client RLS contract — 2026-11-21

## What staging proves

A read-only inspection of Supabase staging shows 64/64 public tables have RLS enabled and 64 policies exist. Sensitive tables use one of two patterns:
- deny_direct_client_access for anon/authenticated with USING=false and WITH CHECK=false; or
- service_role_only, with no anon/authenticated policy.

The product catalog is intentionally public-read for active products and is not included in this sensitive-table list.

## What this PR adds

- 35 pgTAP assertions over 17 tenant-sensitive tables.
- Verify RLS is enabled for each table.
- Verify there is no permissive policy for PUBLIC, anon or authenticated; a direct-client deny policy is accepted only when both USING and WITH CHECK are false.
- Verify no public table is missing RLS.

## What remains unproven

This proves the database's direct-client boundary, not tenant A/B isolation through the service-role Edge Function/API, Storage, cache, scheduled jobs or background workers. Those still require two real staging tenant identities, positive own-tenant reads/writes, negative cross-tenant reads/writes, and browser/API runtime probes. The acceptance workflow is being changed to use the two existing Supabase Auth identities via one-time Admin-generated magic links, avoiding QA username/password secrets and avoiding Auth user/password mutation. It requires one protected GitHub Environment secret, `STAGING_SUPABASE_SERVICE_ROLE_KEY`, to mint one-time tokens; it must never be exposed in logs or preview builds. The workflow is manual-dispatch-only on trusted `staging`. Do not set TENANT_ISOLATION_RELEASED=true.

## Safety

No schema/data migration, shared staging mutation, Auth user creation, secret readout, Edge Function deployment or production change is made by this PR.


## Existing Supabase identities — passwordless acceptance harness

The staging Auth inventory already contains an active Owner in `dlice-default` and an active QA Branch A account in `dlice-qa-isolation-b`. The acceptance workflow now targets those existing email identities and uses the Supabase Auth Admin `generateLink` API to mint a one-time magic-link token, then exchanges the token hash for a short-lived session using the public key. This avoids creating test users, resetting passwords, or storing user passwords in GitHub. The service-role key is required only in the protected staging GitHub Environment as `STAGING_SUPABASE_SERVICE_ROLE_KEY`; the workflow revokes both temporary sessions after the probes. This path is implemented in the PR branch but cannot be live-dispatched until the PR is integrated into `staging` and the single service-role secret is configured.
