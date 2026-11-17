# Staging configuration report

**Result: BLOCKED — GitHub does not expose staging environment secret/variable
metadata to this integration (HTTP 403).** This does not mean an item is absent.
Values were not read or printed.

The canonical acceptance workflow now reads these values from GitHub Environment
`staging`, emits value-free input checks, and fails closed before authentication
when required inputs are unavailable or malformed. The workflow has not yet run
against trusted staging.

| Input | Type | Verification status |
|---|---|---|
| `STAGING_SUPABASE_URL` | Secret | BLOCKED — cannot inspect; live workflow preflight not run |
| `STAGING_SUPABASE_PUBLIC_KEY` | Secret | BLOCKED — cannot inspect; live workflow preflight not run |
| `STAGING_TENANT_A_USERNAME` | Secret | BLOCKED — cannot inspect; live workflow preflight not run |
| `STAGING_TENANT_A_PASSWORD` | Secret | BLOCKED — cannot inspect; live workflow preflight not run |
| `STAGING_TENANT_B_USERNAME` | Secret | BLOCKED — cannot inspect; live workflow preflight not run |
| `STAGING_TENANT_B_PASSWORD` | Secret | BLOCKED — cannot inspect; live workflow preflight not run |
| `STAGING_TENANT_A_ID` | Variable | BLOCKED — cannot inspect; live workflow preflight not run |
| `STAGING_TENANT_B_ID` | Variable | BLOCKED — cannot inspect; live workflow preflight not run |
| `STAGING_TENANT_A_BRANCH_ID` | Variable | BLOCKED — cannot inspect; live workflow preflight not run |
| `STAGING_TENANT_B_BRANCH_ID` | Variable | BLOCKED — cannot inspect; live workflow preflight not run |
| `STAGING_TENANT_A_USER_ID` | Variable | BLOCKED — cannot inspect; live workflow preflight not run |
| `STAGING_TENANT_B_USER_ID` | Variable | BLOCKED — cannot inspect; live workflow preflight not run |

The workflow checks the staging Supabase hostname, public-key shape, non-empty
values, UUID shape, and distinct A/B identities without outputting values.
P03 additionally verifies real Auth identities, active memberships, and exact
branch IDs/codes using the login sessions. Only that trusted runtime run can
verify that configured identifiers correspond to real staging records.

The probe expects branch codes `QA-DLICE-A` and `QA-TENANT-B`; their current
staging records have not been verified because no trusted runtime run has
occurred. No hard-coded fixture UUID is used as proof of a live record.

## Required follow-up

An administrator should inspect/add the twelve named inputs in
**GitHub → Settings → Environments → staging**, then have the protected staging
branch trigger the acceptance workflow. Do not paste values into a PR, issue,
commit, or report. Detailed steps are in
[administrator-action-required.md](./administrator-action-required.md).


## Reconciliation addendum — 18 Nov 2026

The staging records were rechecked read-only. The canonical fixture IDs in PR #75 match the current tenant and QA branch rows:

- Tenant A: `dlice-default`, branch `QA-DLICE-A`, active branch inventory rows: 2.
- Tenant B: `dlice-qa-isolation-b`, branch `QA-TENANT-B`, active branch inventory rows: 2.
- Both QA users have active tenant membership and an active assignment to their designated QA branch.

**Fixture discrepancy requiring maintainer action:** Tenant A's QA user also has an active assignment to `DLC-B001` (branch status `planned`). The P03 runner intentionally requires the complete visible branch list to contain exactly the designated QA branch. Do not weaken this assertion or filter out the extra assignment merely to obtain PASS. An authorized maintainer must remove/deactivate the stale assignment through the approved application/admin workflow, or provision a dedicated Tenant A QA identity with exactly one branch assignment.

The twelve GitHub Environment inputs remain **BLOCKED / UNVERIFIED** because this integration cannot inspect Environment variables or secrets. No values were read, changed, or logged. The workflow's value-free preflight must verify them during a trusted staging run.

The canonical workflow now supports both push to `staging` and manual dispatch, but the job-level ref guard permits execution only when `github.ref == refs/heads/staging`. No trusted P01–P09 run has been executed yet.
