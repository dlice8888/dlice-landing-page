# Staging Auth control: leaked-password protection

Date: 2026-11-21
Project: `dlice-staging` (`higoadrzxnhzbbwhdbmh`)

## Current evidence

The Supabase Security Advisor previously reported leaked-password protection as
disabled. The connected Supabase project tools can inspect project/database
state but do not expose an Auth password-security configuration update action.
The project plan is not returned by the connected project inventory, so plan
eligibility must be checked by an organization owner.

Supabase documents this control as available on Pro plan and above:
https://supabase.com/docs/guides/auth/password-security

## Authorized staging configuration

An organization/project owner must:
1. Open the Supabase Dashboard and select `dlice-staging`.
2. Open Authentication → Settings → Password security.
3. Enable prevention of leaked passwords.
4. Save the Auth configuration.
5. Re-open the setting and verify it remains enabled.

Do not change the production project's Auth configuration as part of this task.
Do not upgrade a paid plan or accept billing changes without explicit approval.

## Acceptance

After the setting is enabled on staging:
- re-read Supabase Security Advisor and confirm the leaked-password warning is
  cleared or explicitly explain any remaining warning;
- use a disposable test identity to verify a known compromised password is
  rejected during password creation or password update;
- verify a compliant password succeeds;
- confirm no existing staff password or account was changed;
- retain the Auth configuration evidence and test result in the release record.

Until those checks are complete, feature 9 remains BLOCKED. A documentation
change or a dashboard instruction is not proof that the setting is enabled.
