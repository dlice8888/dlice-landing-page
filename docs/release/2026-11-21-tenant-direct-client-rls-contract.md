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

This proves the database's direct-client boundary, not tenant A/B isolation through the service-role Edge Function/API, Storage, cache, scheduled jobs or background workers. Those still require two real staging tenant identities, positive own-tenant reads/writes, negative cross-tenant reads/writes, and browser/API runtime probes. The current GitHub workflow preflight lacks required tenant A/B credentials, so those runtime tests remain blocked. Do not set TENANT_ISOLATION_RELEASED=true.

## Safety

No schema/data migration, shared staging mutation, Auth user creation, secret readout, Edge Function deployment or production change is made by this PR.
