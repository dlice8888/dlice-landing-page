# GitHub staging configuration audit

**Audit date:** 2026-11-17  
**Environment:** `staging`  
**Repository baseline:** `aed2733f62506ed87a5040a48f479753fdafe1b1`

## Observed workflow contract

The workflow currently present on `staging` is `.github/workflows/staging-auth-tenant-negative.yml`.

| Input | Current workflow reference | Finding |
|---|---|---|
| `STAGING_SUPABASE_URL` | Hard-coded staging URL | Not sourced from a GitHub secret |
| `STAGING_SUPABASE_PUBLIC_KEY` | Hard-coded publishable key | Not sourced from a GitHub secret |
| `STAGING_TEST_BRANCH_A_USERNAME` | `secrets.*` | Legacy single-user credential |
| `STAGING_TEST_BRANCH_A_PASSWORD` | `secrets.*` | Legacy single-user credential |
| `STAGING_TEST_OWNER_USERNAME` | Not referenced | Not verified |
| `STAGING_TEST_OWNER_PASSWORD` | Not referenced | Not verified |
| `STAGING_TENANT_A_USERNAME/PASSWORD` | Not referenced | Canonical A credentials not wired |
| `STAGING_TENANT_B_USERNAME/PASSWORD` | Not referenced | Canonical B credentials not wired |
| Six `STAGING_TENANT_*` UUID variables | Not referenced | Not wired by this workflow |

## Required canonical contract (pending implementation/review)

The PRD prompt's six-secret/six-variable list is a proposed contract, not evidence of existing configuration. PR #71 describes a later canonical four-credential/eight-fixture contract. Reconcile those definitions against the actual test runner and owner test requirements before naming the reusable workflow contract.

Do not silently alias legacy Branch A credentials to Tenant A or Owner credentials. Do not provide fallback UUIDs, fixture defaults, or hard-coded tenant/user IDs.

## Verification status

- Secret existence: **UNKNOWN** — plaintext and environment secret metadata are not exposed through the available repository connector.
- Secret runtime validity: **NOT RUN** — current workflow uses a legacy single-user test; no two-tenant authentication was performed.
- Six proposed fixture variables: **UNKNOWN** — Environment variable metadata was not returned by the available connector.
- Workflow wiring: **FAIL** against the requested six-secret/six-variable contract.
- Environment protection and required reviewers: **UNKNOWN** — not verified by the available API access.
- No secrets were read, printed, created, or changed.

## Administrator checklist

- [ ] Confirm GitHub Environment `staging` exists.
- [ ] Configure canonical credentials for Owner (if used by the Owner suite), Tenant A, and Tenant B as separate secrets.
- [ ] Configure fixture UUIDs as Environment variables only after verifying live staging tenant, branch, user, membership, and assignment relationships.
- [ ] Confirm the Supabase URL is the staging project and the publishable key belongs to that project.
- [ ] Confirm environment required reviewers and deployment branch restrictions remain enabled.
- [ ] Confirm branch rulesets and required status checks remain enabled.
- [ ] Run a trusted workflow and verify authentication at runtime without emitting credentials.
- [ ] Attach sanitized evidence and run IDs.

## Security rules

Never echo secret values, tokens, sessions, cookies, or service-role keys. A secret name being referenced in YAML does not prove the secret exists or authenticates successfully. A successful preflight must fail closed on missing, malformed, mismatched, or unverified inputs.


## Separate authenticated runtime workflow

The primary nine-probe workflow on `staging` is `.github/workflows/staging-runtime-tenant-isolation.yml`.

Observed on `staging`:
- Has `workflow_dispatch` and trusted `push` to `staging`.
- Uses `STAGING_SUPABASE_URL` and `STAGING_SUPABASE_PUBLIC_KEY` secrets.
- Credential fallback expressions allow legacy Owner credentials to substitute for Tenant A and legacy Branch A credentials to substitute for Tenant B.
- Tenant IDs, branch IDs, and user IDs are hard-coded in YAML.
- Executes the nine-probe runner.

Observed on PR #71 head:
- Keeps `workflow_dispatch` and trusted staging push.
- Removes legacy credential fallback; requires four canonical Tenant A/B username/password secrets.
- Externalizes branch A/B and user A/B identifiers to Environment variables.
- Still does not externalize Tenant A/B IDs, so it does not meet the requested six-variable contract.
- The runner records nine probes independently. Missing preflight inputs create explicit BLOCKED records and a nonzero exit; this is correct fail-closed behavior, not a passing acceptance run.

## Data-backed fixture constraints

Read-only staging aggregates show 2 tenant records (1 active), 155 branches (5 active), and 3 active tenant memberships. PR #71's own runbook reports Tenant B currently has zero inventory balance rows; its positive own-branch inventory assertion cannot pass until a legitimate operational flow creates auditable stock. Do not weaken the assertion or seed inventory directly with ad-hoc SQL.

The Owner profile aggregate shows one active Owner profile, while the Auth metadata aggregate found zero non-deleted users with `raw_app_meta_data.platform_owner` as boolean true or string `true`. This is not permission to elevate an account. An authorized administrator must establish the legitimate Owner identity and verify its app metadata and server-side allowlist.

## Execution status

The connected GitHub action set exposes workflow-run lookup and rerun tools, but no workflow-dispatch action. The authenticated P01–P09 run therefore cannot be safely started from this connection. Do not infer runtime success from existing Vercel status checks or static CI.
