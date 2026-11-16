# Administrator action required

These are explicit access/approval gates. They must be completed through
official administrative interfaces; do not bypass protections or expose
credentials.

## 1. GitHub staging Environment

The available API cannot enumerate staging secrets or variables (HTTP 403).
Inspect **Repository Settings → Environments → staging** and verify all twelve
names listed in [staging-configuration-report.md](./staging-configuration-report.md)
exist at this Environment scope.

- Set the six required secrets to values for the `higoadrzxnhzbbwhdbmh`
  staging Supabase project. Use the public/anon key, never a service-role key.
- Set the six variables to IDs read from actual staging tenant, branch, and
  identity records. Do not reuse the historical fixture UUIDs without
  verifying that each record still exists and maps correctly.
- Do not print secret values. The workflow reports names/status only.

## 2. Approval and trusted execution

The readable GitHub Environment metadata currently reports no protection rules
and allows administrator bypass. Configure an independent required reviewer
and restrict eligible deployment branches to protected `staging`, without
weakening repository rules. Do not self-approve. The branch-protection API
returned HTTP 403 and must be inspected by a repository administrator.

The canonical isolation workflow deliberately runs only on a push to trusted
`staging`; it has no arbitrary-branch `workflow_dispatch`. After the changes
are independently reviewed and officially merged, the staging push should run
the preflight and P01–P09. Review the workflow summary and job logs before
marking acceptance.

## 3. Supabase Owner authorization

In the staging Supabase project, verify the real Owner account and active
profile. Through Supabase Auth Admin API/dashboard only, preserve existing
`app_metadata` and set `platform_owner: true`. Update the staging Edge Function
`DLICE_PLATFORM_OWNER_USER_IDS` secret through its official settings, preserving
other entries. Verify the resulting Auth metadata, allowlist behavior, and
Owner-only administrative access using authenticated tests. Never modify
`auth.users` with SQL.

Also verify leaked-password protection, current migration history, RLS/grants,
advisor findings, backups, and a tested restore/recovery procedure. Database
migrations require their own independent review and explicit staging approval.

## 4. Vercel and production boundary

Project administrators must verify Preview/Production environment separation,
deployment protection, required reviewers, rollback target, and production
deployment identity in Vercel. Do not promote the current Preview or change
production environment variables/deployment. No production migration is
authorized.

## 5. Final acceptance and evidence

After all approvals and staging configuration, run authenticated tenant
isolation, Owner authorization, migration post-checks, the five operational
E2Es, security/regression tests, and an isolated 150-branch load test. Attach
run/job links, exact commit and deployment, environment, actor/approver,
timestamps, and non-sensitive results to the
[release-evidence-index.md](./release-evidence-index.md). Reassess
production readiness only after every critical gate is PASS.
