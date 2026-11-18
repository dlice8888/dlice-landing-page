# FnB OS Release Readiness

**Decision:** NO-GO  
**Snapshot:** 18 November 2026  
**Target:** staging only; production excluded

## Release gates

| Gate | Current result | Evidence |
|---|---|---|
| `TENANT_ISOLATION_RELEASED=false` | PRESERVED | Edge source `supabase/functions/dlice-orders/index.ts:52` |
| `PUBLIC_TENANT_ROUTING_RELEASED=false` | PRESERVED | Edge source `supabase/functions/dlice-orders/index.ts:135-144` |
| PR #64 migration | HOLD / NOT APPLIED | Staging migration history ends at `20261027140145` |
| P01–P09 | BLOCKED / NOT RUN | Last runtime attempt 44208204366 blocked before network access |
| Owner authorization | BLOCKED | Active Owner profile exists; Auth app_metadata boolean true absent; allowlist not independently verifiable |
| Worker A/B identity and scope | BLOCKED | Distinct Auth users, separate active branch_manager memberships and equal permissions; both global profiles are sales_admin, not branch_worker |
| RLS | CONFIGURATION PASS ONLY | 64/64 public tables have RLS; policy semantics not fully adversarially verified |
| Migration parity | BLOCKED | 46 applied rows vs 45 source files |
| Operational E2E | NOT VERIFIED | Required seven business flows not proven end-to-end |
| Open PR reconciliation | IN PROGRESS | 17 current open PRs, all Draft |
| GitHub protection | P0 BLOCKED | staging reports `protected=false`; rulesets empty; protection read endpoint 403 |
| Vercel Preview | READY | Preview readiness is not authenticated staging acceptance; project SSO protection is enabled for all deployments except custom domains |
| Production | UNTOUCHED | No production deployment or database change |

## External configuration actions that cannot be performed through this connection

1. **GitHub Environment `staging` secrets/variables:** verify presence of the six tenant credential secrets and six tenant fixture variables without revealing values. Location: repository Settings → Environments → staging. Reason: connected integration cannot read environment metadata; workflow dispatch API is not exposed here. Verify by trusted staging workflow preflight.
2. **P03 fixture semantics:** review/merge PR #87. The second Worker A assignment is same-tenant and valid; do not remove it merely to satisfy the old exact-one assertion. Verify P03 sees the configured QA branch and never sees the other tenant's branch.
3. **Owner Auth metadata:** through Supabase Authentication → Users / authorized Auth Admin, preserve existing app metadata and set boolean `platform_owner: true` only if the account is genuinely authorized. Verify Auth read-back and UUID allowlist membership independently.
4. **GitHub branch protection/rulesets:** configure required reviews/status checks/no force-push/no delete and staging deployment reviewers through repository Settings. The current API reports staging unprotected and rulesets empty; this audit did not weaken protection.
5. **Missing migration source:** recover `20261022140302` from the authoritative source and checksum it against the applied version.

## Additional P0 dependency

PR #85 is a Draft code candidate for the own-branch inventory read path required by P04/P06. Its exact-head quality CI passed, but it has not been merged or deployed to staging. Do not run P01–P09 against v69 expecting P04/P06 to pass; after review and staging merge, run the trusted workflow and preserve BLOCKED results if inputs are missing.

## Release sequence

Do not merge PR #64 or apply its migration until P01–P09, supplemental direct REST/RPC checks, migration replay, operational regression, independent security review and all release gates pass. Do not merge PR #74 as a bulk promotion. Do not deploy production.

## Additional P0 identity gate

Staging's two candidate tenant users are both classified globally as `sales_admin`; the database role constraint has no ordinary worker value. Their tenant membership role is `branch_manager`, but this alone does not satisfy the explicit non-Admin fixture requirement. PR #86 adds the source-only `branch_worker` role and Owner-authorized conversion path. Do not apply its migration or change user profiles until migration review and authorized Owner verification pass. P03 remains BLOCKED.

## Runtime CORS gate

Staging CORS runtime workflow [44307838539](https://github.com/dlice8888/dlice-landing-page/actions/runs/44307838539) passed all three live probes: allowlisted origin HTTP 200 with exact ACAO, foreign origin HTTP 403 without ACAO, and absent Origin HTTP 200 without fallback ACAO. This gate is PASS; tenant P01–P09 remain BLOCKED/NOT RUN.

## Production deployment exception

**Exception recorded:** a documentation-only commit was accidentally made to `main` due to an omitted branch argument, triggering a production-target Vercel deployment. The added file was immediately deleted from `main`, which triggered a second production-target deployment. The current `dlice.vercel.app` alias points to restoration deployment `dpl_4Fvtp6RvMwukCWFndERhgNh4Zv3e`. The restored main tree SHA `427d9413b4e6fe070ba76a93baab533ccb528570` is byte-for-byte the same Git tree as the pre-incident parent commit. No application source, Auth, database or production data was changed. This is not described as “no production deployment”; it is a documented unintended documentation-only deployment followed by source-tree restoration.

## Migration source parity update

The staging source tree still has 45 migration files against 46 applied migration records. PR #88 restores the missing `20261022140302_add_missing_fk_supporting_indexes.sql` directly from the staging migration-history SQL; all nine index statements normalized-match the recorded applied SQL. This is source-only and does not reapply the migration. PR #88 exact-head quality (44309825502) and disposable replay (44309825526; all 46 migrations) have passed. The source file is not yet merged; keep parity marked PARTIAL until PR #88 is merged through the staging review path.

## PR #83 exact-head verification — 2026-11-18

- PR #83 head: `b3121406d00fa395ff5073e4b67997f05d81ad0f`; draft, open, mergeable; Vercel Preview `dpl_EANn7yD2SrmKRodsqYZppJajqZAw` READY.
- Free quality run [44303062590](https://github.com/dlice8888/dlice-landing-page/actions/runs/44303062590) SUCCESS. The workflow includes staging secret workflow, tenant-isolation runtime evidence and public-routing gate checks. The log contains passing test groups of 5/5, 4/4, 11/11, 5/5 and 1/1.
- `branchB` is declared before the fail-closed preflight in `tests/staging/tenant-isolation-existing-identity.mjs`, eliminating the previously observed temporal-dead-zone path.
- Added subprocess regression cases for empty public key, Tenant A username, Tenant A password, Tenant B branch ID, whitespace-only public key/username/password and malformed branch UUID. Each expects exit code 2, BLOCKED, no stdout/network output, no credential/token disclosure and no ReferenceError.
- The workflow now references `secrets.STAGING_SUPABASE_PUBLIC_KEY` rather than a literal public key. The actual GitHub Environment secret's availability is still not independently readable; PR #83's quality run is not a tenant-isolation runtime proof.
- **P01–P09 remain BLOCKED / NOT RUN**; no claim of tenant isolation PASS is made.

## Final continuation checkpoint — 2026-11-18 20:27 WIB

- PR #84 audit documentation branch head `16127fcd25451a31a881e9886286290f5b851ed4`; Free quality run [44314257571](https://github.com/dlice8888/dlice-landing-page/actions/runs/44314257571) SUCCESS. PR #84 remains Draft and open.
- All ten required audit artifacts exist on the isolated PR #84 branch. The JSON implementation matrix contains 18 domains and individual requirement rows; no domain is marked COMPLETE because full runtime acceptance has not been demonstrated.
- PR #83 exact-head quality PASS and Preview READY; eight missing/invalid-input regression cases pass by the quality suite. This is not P01–P09.
- PR #88 exact migration source recovery: quality PASS, disposable replay PASS, and read-only staging inspection confirms all nine expected index names exist. PR #88 remains Draft/open pending review and merge through the protected staging process.
- Current open PR list contains 18 entries. PR #64 remains Draft/HOLD; no PR was merged.
- Tenant P01–P09 remain BLOCKED/NOT RUN due unavailable verified staging credentials/fixture identity evidence and unresolved ordinary-worker role/assignment prerequisites. Owner authorization is not fully verified.
- Staging branch protection/ruleset verification remains unavailable through the connected GitHub API integration; prior audit showed staging protection false and rulesets empty. No protection was lowered.
- `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false` remain unchanged.
- No staging schema/data/Auth mutation was performed in this continuation. No production deployment is authorized; the earlier documentation-only production deployment exception and exact source-tree restoration are recorded above.


## Fresh release gate recheck — 2026-11-18

- Staging P01–P09 run [44207773570](https://github.com/dlice8888/dlice-landing-page/actions/runs/44207773570): 9 BLOCKED, 0 SKIPPED, 0 executed. Both worker credential pairs and all canonical tenant/branch/user fixture IDs were empty. No tenant-isolation result can be accepted.
- Existing-identity probe [44208204366](https://github.com/dlice8888/dlice-landing-page/actions/runs/44208204366) blocked without creating accounts. Owner-authenticated P0 HTTP bootstrap [44207773489](https://github.com/dlice8888/dlice-landing-page/actions/runs/44207773489) blocked due missing Owner QA credentials.
- Supabase read-only inventory: two active ordinary tenant members remain globally classified as `sales_admin`; the role constraint still excludes `branch_worker`. Assignment counts are one and two within their respective tenants. PR #86 migration is not applied.
- One active Owner profile exists, but no linked Auth user currently has boolean `app_metadata.platform_owner=true` in the inspected set; allowlist membership is not independently readable. Owner gate remains BLOCKED.
- PR #88 recovered the missing applied migration source and proved exact SQL parity plus disposable replay, but source parity on the staging branch remains pending PR #88 merge through the authorized review path. No staging DDL was run.
- No secrets, Auth users, memberships, assignments, profile roles, or release flags were modified. Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.
