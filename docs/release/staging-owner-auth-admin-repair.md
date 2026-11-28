# Staging Platform Owner Auth repair

This is a one-time administrative repair for the existing, identity-verified Owner account. It is deliberately hard-bound to the D'Lice staging project `higoadrzxnhzbbwhdbmh`; it refuses other Supabase project URLs.

## Preconditions

1. Confirm the existing Owner account in Supabase Dashboard → Authentication → Users.
2. Confirm its UUID matches the active `admin_profiles.role = 'owner'` record.
3. Use the existing account only. Do not create a second Owner or change its password.
4. Obtain the staging Service Role Key from the staging-only secret store. Never paste it into chat, source code, a shell command argument, or a log.

## Run

Run from the repository root in a trusted terminal with environment variables already loaded from the staging secret store:

```sh
node scripts/set-staging-platform-owner.mjs --confirm-staging-owner-uuid <VERIFIED_EXISTING_OWNER_UUID>
```

Required environment variables:

- `STAGING_SUPABASE_URL=https://higoadrzxnhzbbwhdbmh.supabase.co`
- `STAGING_SUPABASE_SERVICE_ROLE_KEY=<staging-only secret>`

The script performs Auth Admin GET → PUT → GET. It preserves existing `app_metadata`, sets `platform_owner` to JSON boolean `true`, verifies the same UUID, and prints only the UUID and non-sensitive verification facts. It does not modify `user_metadata`, password, tenant membership, database rows, or production.

## Separate Edge Function allowlist step

In Supabase staging → Edge Functions → Secrets, preserve every existing `DLICE_PLATFORM_OWNER_USER_IDS` entry and add the verified existing Owner UUID if absent. Do not print the secret. The script intentionally does not change function secrets because the current connector does not expose a safe secret-write operation.

## Acceptance gate

After both steps:

1. Sign out and sign back in as the existing Owner to obtain a fresh JWT.
2. Re-read Auth Admin metadata and confirm `app_metadata.platform_owner === true`.
3. Confirm the same UUID is in the server-side allowlist without revealing its value.
4. Run positive Owner Command Center and negative non-Owner/cross-tenant tests.
5. Do not run mutation POS E2E until all four checks pass.

No feature is DONE based on the metadata update alone. Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.
