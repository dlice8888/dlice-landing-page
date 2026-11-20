# Staging GitHub OIDC session broker

## Purpose
Replace four long-lived GitHub Environment username/password secrets with GitHub's short-lived OIDC job identity. The broker issues one short-lived Supabase access token for each of two **pre-existing** Auth users. Supabase Auth and the database remain the only source of truth for identities, memberships, roles, tenants, and branch assignments.

## Trust boundary
- GitHub Actions receives an OIDC token only in the trusted `staging` Environment workflow.
- The Edge Function validates GitHub's signature/JWKS, issuer, audience, repository and immutable repository/owner IDs, exact staging ref, exact workflow ref, environment, event type, run ID, attempt, and JTI.
- The broker maps slot A/B to two pre-provisioned Supabase Auth user UUIDs held as Supabase Function secrets. It verifies the Auth user exists, the D’Lice profile is active with global profile role `sales_admin`, and the tenant-scoped membership role is `branch_manager`.
- It uses Supabase Auth Admin to create a one-time magic-link token and exchanges it immediately for an ordinary user session. No service-role token is returned.
- A database uniqueness record prevents replay for the same run/attempt/slot and records issuance. Service-role is only inside the Edge Function's managed environment.
- The runner keeps access tokens in process/job memory, masks them, and never prints or stores them as artifacts.

## Required Supabase Function secrets
Configure through the authorized Supabase staging Function Secrets interface:
- `GITHUB_REPOSITORY_ID` = immutable repository ID for dlice8888/dlice-landing-page
- `GITHUB_OWNER_ID` = immutable owner ID
- `STAGING_TENANT_A_USER_ID` = existing Auth UUID for Tenant A QA identity
- `STAGING_TENANT_B_USER_ID` = existing, different Auth UUID for Tenant B QA identity

Do not put these values in Git, workflow YAML, or GitHub Secrets. Do not create users or modify memberships from this function.

## Rollout sequence
1. Review this code and the migration independently.
2. Apply the migration to a disposable Supabase project and test replay, duplicate issuance, expired/invalid token, wrong repository/ref/workflow/environment, and A/B identity separation.
3. Configure the four Supabase Function secrets through authorized staging administration.
4. Deploy the function to staging only.
5. Dispatch the trusted workflow. Require P01-P09 to execute, no BLOCKED/SKIPPED, and cross-tenant reads/writes to be denied.
6. Only then remove the four GitHub username/password Environment secrets.
7. Keep `TENANT_ISOLATION_RELEASED=false` until separate release governance approves it.

## Important
The broker is intentionally fail-closed. If the audit migration is absent, any secret is missing, the workflow claims do not match, or Auth cannot issue the session, no session is returned. This PR does not deploy the function, apply the migration, modify Auth identities, or change release flags.
