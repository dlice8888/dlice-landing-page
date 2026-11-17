# Staging Owner authorization

**Status: BLOCKED — not verified against live Supabase Auth or the deployed
Edge Function.**

The supplied Owner UUID is an inspection hint only; no existence, identity,
account status, or metadata claim is inferred from it. Supabase Auth Admin
access and Edge Function secret metadata were not available. No Auth user or
metadata was changed.

Repository authorization requires all of the following:

1. Authenticated user resolved by Supabase Auth.
2. Active `admin_profiles` row with role `owner`.
3. The same real user ID included in the server-side
   `DLICE_PLATFORM_OWNER_USER_IDS` Edge Function secret.
4. Trusted Supabase `app_metadata.platform_owner === true`.

The code does not authorize from a client-editable user metadata claim. The
`TENANT_ISOLATION_RELEASED` and public-routing gates remain closed.

## Administrator verification

1. In the **staging** Supabase project, locate the actual Owner in
   Authentication → Users. Confirm the account is active and its identity with
   the authorized account owner.
2. Through the Supabase Auth Admin API or an approved dashboard control (never
   SQL), preserve existing `app_metadata` and set
   `"platform_owner": true`. Do not modify `auth.users` with SQL.
3. Confirm the corresponding active `admin_profiles.role = 'owner'` using the
   application’s authorized administrative path.
4. In the staging Edge Function secret settings, preserve existing
   `DLICE_PLATFORM_OWNER_USER_IDS` entries and ensure the verified UUID is
   included. Never print or place the secret value in repository evidence.
5. Authenticate as that Owner and verify actual Auth `app_metadata`, owner
   access, and denial for ordinary tenant users. Record only the identity
   reference, test result, run/job IDs, timestamp, and approver.

**Acceptance:** all four authorization sources match the real account, and the
independent runtime authorization tests pass. Until then Owner authorization is
BLOCKED, not PASS.


## Read-only reconciliation — 18 Nov 2026

The staging database currently contains one active `admin_profiles` record with role `owner`. Its linked Auth user's `raw_app_meta_data.platform_owner` claim is **NULL / absent**, not boolean `true`. This means the repository's two-source platform-owner authorization condition is not currently proven and should fail closed.

The Auth identity and the `DLICE_PLATFORM_OWNER_USER_IDS` Edge Function secret were not independently verified through authorized Auth Admin / function-secret controls. Do not infer the allowlist contents from the database, and do not edit Auth metadata or the allowlist through SQL or an unapproved path.

Required maintainer action remains: verify the actual Owner identity, preserve existing app metadata while setting the boolean claim through Supabase Auth Admin, and reconcile the server-side allowlist through the authorized Edge Function secret settings. Then run the Owner-specific authorization tests.
