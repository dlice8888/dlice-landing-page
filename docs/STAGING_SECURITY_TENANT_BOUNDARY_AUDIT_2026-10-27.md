# Staging security and tenant-boundary audit — 2026-10-27

## Scope and safety
- Scope: staging Supabase project `higoadrzxnhzbbwhdbmh`, PR #58, PR #42.
- Production project `gdjlkrmlsurcdbwnmqgg` was not queried or modified.
- No staging data writes, schema migrations, secret reads, or Edge Function deployments were performed in this audit.
- `TENANT_ISOLATION_RELEASED` remains `false`.

## PR #58 — action authorization and owner bypass
Changes on `fix/refund-tenant-scope-guard-20261027`:
- Removed direct `actor.profile.role === "owner"` / `!== "owner"` authorization shortcuts across `dlice-orders`; platform bypasses now use one `isPlatformOwner` decision.
- A platform bypass requires all three checks: authenticated Supabase user; active `admin_profiles` row with role `owner`; user ID in `DLICE_PLATFORM_OWNER_USER_IDS`; and trusted Auth `app_metadata.platform_owner === true`.
- Generic profile permissions containing `*` are stripped for non-platform-owner actors.
- Branch access for non-platform owners goes through tenant membership and active branch assignment checks.
- The existing uncertified-action deny set remains in place while tenant isolation is unreleased.
- Added contract coverage for generic-owner bypass and the trusted Auth metadata claim.

## Identity source validation — outcome
A read-only aggregate query against staging Auth/profile metadata found:
- Active business-owner profiles: 1
- Active owner profiles carrying trusted `app_metadata.platform_owner=true`: 0

This result does not expose user IDs or secrets. It means the current active owner profile is **not presently validated as a platform owner by the chosen trusted claim**. Do not add that claim or an allowlist entry without explicit approval from the designated identity owner. If this profile is intended to be a platform owner, the authorized administrator must confirm and set the server-controlled Auth app metadata through the approved process; never use `user_metadata`.

The secret-management connector does not provide a safe metadata-only inventory of Supabase Edge Function secret names/values, so the actual `DLICE_PLATFORM_OWNER_USER_IDS` configuration was not independently verified. No secret value was requested or displayed.

## PR #42 — 17 server-only tables
Read-only catalog preflight for all 17 migration targets:
- RLS enabled: 17/17
- Existing policies: 0/17
- Direct `anon` / `authenticated` SELECT/INSERT/UPDATE/DELETE privilege exceptions: 0
- Migration recorded in staging history: no
- Security Advisor still reports 17 `rls_enabled_no_policy` findings.

The migration only revokes direct client grants and adds explicit deny-all policies for `anon` and `authenticated`; it does not change service-role grants. The migration has **not** been applied. Application remains held until client-code dependency review and authenticated Edge Function regression tests are evidenced.

## CI evidence
- PR #58 Free quality checks: https://github.com/dlice8888/dlice-landing-page/actions/runs/40495125478
- PR #58 KDS/offline contract: https://github.com/dlice8888/dlice-landing-page/actions/runs/40495125301
- PR #58 CORS probes: https://github.com/dlice8888/dlice-landing-page/actions/runs/40495125198
- PR #58 procurement contracts: https://github.com/dlice8888/dlice-landing-page/actions/runs/40495125207 and https://github.com/dlice8888/dlice-landing-page/actions/runs/40495125222
- PR #42 Free quality checks: https://github.com/dlice8888/dlice-landing-page/actions/runs/40494936376
- PR #42 deny-policy contract: https://github.com/dlice8888/dlice-landing-page/actions/runs/40494936181

These are repository/contract checks, not runtime tenant-boundary E2E.

## Remaining hard release gates
1. Confirm the approved platform-owner identity source and validate allowlist membership without exposing values.
2. Deploy the reviewed PR #58 code to staging only after the identity claim and configuration are reconciled; current deployed `dlice-orders` version 59 predates the new owner and uncertified-action guards.
3. Run runtime requests for anonymous, authenticated role-without-permission, wrong-branch, and cross-tenant read/write cases. Snapshot relevant rows before/after and prove denied writes create no side effects.
4. Confirm no browser/client code directly depends on the 17 PR #42 server-only tables, then apply the migration to staging only and rerun advisor plus authorized Edge Function regression tests.
5. Keep release gate closed until all runtime evidence is attached to the PRs. Do not merge as a substitute for those checks.

## Follow-up execution — 2026-10-27

### PR #58 deployment
- Deployed the branch's `supabase/functions/dlice-orders/index.ts` to staging project `higoadrzxnhzbbwhdbmh` using the Supabase Edge Function deploy action.
- Verified deployed function status `ACTIVE`, version `60`, `verify_jwt=false` preserved from existing configuration, and deployed source includes the allowlist + trusted `app_metadata.platform_owner` checks and `TENANT_ISOLATION_RELEASED=false`.
- Latest PR #58 CI on the branch head passed: Free quality checks, KDS/offline contract, CORS probes, procurement requisition contract, and procurement receiving contract. Links are available from the Actions runs attached to commit `53552607e5b63556d10bd7f93e8909788a8f9959`.

### Browser dependency review and PR #42 application
- Reviewed `index.html`, `admin.html`, and `erp.html` in the PR #58 source tree. Browser ERP interactions use the `dlice-orders` Edge Function `call(...)` wrapper; no direct Supabase `.from(...)` calls were found in `erp.html`, and the 17 target tables are not referenced as direct browser REST table calls. This supports server-only classification for the reviewed web clients.
- Applied PR #42 migration to staging as `20261027112330_explicit_deny_policies_server_only_tables`.
- Post-apply verification: 17/17 target tables RLS-enabled; 17/17 have one explicit deny policy; `anon` and `authenticated` have no direct SELECT/INSERT/UPDATE/DELETE; `service_role` retains all four privileges.
- Security Advisor's 17 `rls_enabled_no_policy` findings cleared. Remaining unrelated warning: leaked-password protection disabled.

### Identity validation and remaining hard gate
- Read-only aggregate still shows 1 active business-owner profile and 0 active owner profiles with trusted `app_metadata.platform_owner=true`; the corresponding user-editable metadata claim count is also 0.
- Secret inventory is not exposed by the available connector, so the actual configured `DLICE_PLATFORM_OWNER_USER_IDS` allowlist cannot be verified from secret metadata here. No secret values were read or displayed.
- No temporary QA accounts were created. The connector does not expose a function-invoke/HTTP POST action, and no approved non-owner test identities or tenant-B fixture are available in this session. Therefore runtime anonymous POST, role-without-permission, wrong-branch, cross-tenant read/write, and before/after side-effect snapshots remain unverified.
- `TENANT_ISOLATION_RELEASED` remains `false`. Do not mark PR #58 or tenant isolation as accepted until those runtime tests and data snapshots are attached.
