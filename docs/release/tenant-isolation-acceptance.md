# Tenant isolation acceptance

**Live staging result: BLOCKED / NOT RUN.** The current GitHub integration
cannot read Environment secret/variable metadata (HTTP 403), and the trusted
acceptance workflow has not run on the staging branch. A local no-credentials
contract test confirmed that an unconfigured execution reports all nine probes
as BLOCKED, with zero PASS and zero SKIPPED; this is not runtime evidence.

The established P01–P09 contract is retained:

| Probe | Existing contract | Live status |
|---|---|---|
| P01 | Tenant A existing Supabase Auth identity passwordless magic-link login | BLOCKED |
| P02 | Tenant B existing Supabase Auth identity passwordless magic-link login | BLOCKED |
| P03 | Distinct Auth identities, active memberships, exact tenant membership, and exact one-branch assignment/code | BLOCKED |
| P04 | Tenant A reads real inventory rows for its own branch | BLOCKED |
| P05 | Tenant A is denied Tenant B inventory read | BLOCKED |
| P06 | Tenant B reads real inventory rows for its own branch | BLOCKED |
| P07 | Tenant B is denied Tenant A inventory read | BLOCKED |
| P08 | Tenant A cross-tenant stock-transfer write is denied and no transfer row is created | BLOCKED |
| P09 | Tenant B cross-tenant stock-transfer write is denied and no transfer row is created | BLOCKED |

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
- The workflow and fail-closed preflight changes were pushed in commit
  `073a58f11b043da6083ba610c501e3eb93302e35`; exact-head quality, procurement,
  Kitchen/KDS, CORS, and Vercel Preview checks passed. These checks do not run
  the protected staging workflow or provide live tenant-isolation evidence.
- No authenticated staging session, cross-tenant read/write result, or database
  evidence was produced.

`TENANT_ISOLATION_RELEASED=false` remains unchanged. Do not enable either
release flag until trusted runtime evidence and independent approval are
available.


## Reconciliation addendum — 18 Nov 2026

- The canonical workflow supports `workflow_dispatch` and trusted pushes to `staging`; a job-level ref guard prevents dispatch from any non-staging ref. It remains protected by the GitHub Environment named `staging`.
- P01–P09 remain **NOT RUN** on trusted staging. Static/contract CI is not runtime acceptance.
- The configured Tenant A and Tenant B tenant/branch/user records were checked read-only. Both have active membership, an active QA branch assignment, and two inventory rows on the designated QA branch.
- P03 has a known Tenant A fixture blocker: the Tenant A QA user also has an active assignment to planned branch `DLC-B001`. The exact-one-branch assertion is intentionally retained. An authorized maintainer must reconcile that assignment before P03 can pass.
- Staging `dlice-orders` was deployed as version 67 from CI-passing source commit `1ae5d40277179bd617e10a11cc839f8df89fc550`. Runtime source contains the self-scoped membership handler. No migration was applied.
- Owner authorization remains blocked: the active Owner profile's Auth `app_metadata.platform_owner` claim is absent; the server-side allowlist has not been verified.
- The six staging secrets and six fixture variables remain unverified because the connected GitHub integration cannot read Environment metadata. The workflow preflight is the required value-free verification path.

Do not mark this acceptance PASS until the fixture discrepancy and Owner/configuration blockers are resolved and a trusted staging workflow run proves all nine probes PASS with no BLOCKED or SKIPPED records.

## Cross-tenant write postcondition

P08 and P09 pass only when the authenticated write returns HTTP 403 **and**
read-only service-role queries find no row in `public.stock_transfers` matching
either generated `transfer_number` or `idempotency_key`. Evidence contains the
query status and row counts, but not the generated identifiers or secret
values. The postcondition does not write to staging.
