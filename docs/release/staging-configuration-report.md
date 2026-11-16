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

The accepted branch-code contract is `QA-DLICE-A` and `QA-TENANT-B`. No
hard-coded fixture UUID is used as proof of a live record.

## Required follow-up

An administrator should inspect/add the twelve named inputs in
**GitHub → Settings → Environments → staging**, then have the protected staging
branch trigger the acceptance workflow. Do not paste values into a PR, issue,
commit, or report. Detailed steps are in
[administrator-action-required.md](./administrator-action-required.md).
