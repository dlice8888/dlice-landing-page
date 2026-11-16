# Tenant isolation acceptance

**Live staging result: BLOCKED / NOT RUN.** The current GitHub integration
cannot read Environment secret/variable metadata (HTTP 403), and the trusted
acceptance workflow has not run on the staging branch. A local no-credentials
contract test confirmed that an unconfigured execution reports all nine probes
as BLOCKED, with zero PASS and zero SKIPPED; this is not runtime evidence.

The established P01–P09 contract is retained:

| Probe | Existing contract | Live status |
|---|---|---|
| P01 | Tenant A username/password login | BLOCKED |
| P02 | Tenant B username/password login | BLOCKED |
| P03 | Distinct Auth identities, active memberships, exact tenant membership, and exact one-branch assignment/code | BLOCKED |
| P04 | Tenant A reads real inventory rows for its own branch | BLOCKED |
| P05 | Tenant A is denied Tenant B inventory read | BLOCKED |
| P06 | Tenant B reads real inventory rows for its own branch | BLOCKED |
| P07 | Tenant B is denied Tenant A inventory read | BLOCKED |
| P08 | Tenant A cross-tenant stock-transfer write is denied | BLOCKED |
| P09 | Tenant B cross-tenant stock-transfer write is denied | BLOCKED |

Supplemental direct REST branch-row and service-only RPC denial probes remain in
the runner. The runtime evidence records timestamps, status, expected/actual
result, response metadata, and value-free configuration checks. Passwords and
JWTs remain process-local and are never logged.

The canonical workflow is
`.github/workflows/staging-tenant-isolation-acceptance.yml`. It runs only on a
trusted push to `staging` (not on pull request code or arbitrary manual
dispatch), uses the protected `staging` Environment, and fails if any required
probe is failed, blocked, skipped, or absent.

## Local verification (not live acceptance)

- Runtime syntax and contracts: **8/8 PASS**.
- Tenant permission Deno unit tests: **7/7 PASS**.
- Empty-configuration exercise: **9 BLOCKED, 0 PASS, 0 SKIPPED**.
- The new workflow/preflight/evidence changes are still local and have not yet
  run in GitHub Actions.
- No authenticated staging session, cross-tenant read/write result, or database
  evidence was produced.

`TENANT_ISOLATION_RELEASED=false` remains unchanged. Do not enable either
release flag until trusted runtime evidence and independent approval are
available.
