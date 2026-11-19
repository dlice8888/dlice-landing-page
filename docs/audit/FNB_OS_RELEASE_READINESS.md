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


## Correction to the prior staging fixture status — 2026-11-18

The earlier wording that Tenant A/B credentials and all six fixture variables were currently "empty/missing" was too broad and is superseded by this correction.

- The user-provided GitHub Environment `staging` inventory already lists the four canonical Tenant A/B username/password secrets and all six Tenant A/B tenant/branch/user variables. The staging acceptance workflow at the exact run commit declares `environment: staging` and references those same names. Therefore the inventory names are present; do not instruct the user to recreate them.
- The historical run [44207773570](https://github.com/dlice8888/dlice-landing-page/actions/runs/44207773570), created 2026-11-18 00:26 UTC, logged empty values for those ten inputs at execution time. This proves that run did not receive their values; it does not establish that the current Environment inventory is empty. The connected GitHub tool cannot inspect decrypted secret values or Environment-scoped variable values, so the reason for the resolution discrepancy is not yet established.
- Read-only Supabase verification now confirms all six configured fixture UUIDs exist in their respective tables and match the intended records exactly: Tenant A `dlice-default` / branch `QA-DLICE-A` / existing user A; Tenant B `dlice-qa-isolation-b` / branch `QA-TENANT-B` / existing user B. No fixture IDs need to be recreated or replaced.
- Both users have active `branch_manager` tenant memberships, six equal permissions, and active assignments within their own tenant. User A has two active same-tenant branches (`DLC-B001` and `QA-DLICE-A`); user B has one (`QA-TENANT-B`). The P03 runtime script on staging still requires exactly one branch for each identity, which incorrectly rejects User A's valid same-tenant second assignment. This is a code/test defect, not a missing assignment.

Next diagnostic: execute a fresh `Staging Tenant Isolation Acceptance` workflow_dispatch on branch `staging` without changing/recreating configuration. If the ten inputs still resolve empty, inspect the exact GitHub Environment scope/name and access settings with repository administration access. Before treating P03 as valid, correct its one-branch-only assertion to require the configured QA branch and reject only cross-tenant visibility. Inventory action authorization must also be repaired/deployed before P04/P06 can prove own-branch reads.

## Superseding release gate snapshot — 2026-11-19

- NO-GO remains in force. TENANT_ISOLATION_RELEASED=false and PUBLIC_TENANT_ROUTING_RELEASED=false remain unchanged.
- Current open PR inventory is 17; all are Draft. PR #74 is dirty and is not an acceptable bulk merge path.
- Staging E2E reruns on 19 Nov: KDS/POS/Stock run 44505286727 attempt 2 and Procurement run 44506173400 attempt 2 both stopped before business mutations because effective runner inputs STAGING_TEST_OWNER_USERNAME, STAGING_TEST_OWNER_PASSWORD, and STAGING_TEST_BRANCH_A_USERNAME were empty. P01-P09 run 44326099475 has nine BLOCKED/not-executed probes. Do not report E2E acceptance as passed.
- PR #95 updates P03 to the live role model (sales_admin global profile and branch_manager tenant membership); exact-head quality run 44541119025 passed static/contract checks only. It does not prove P01-P09.
- PR #96 is merged to main (2bb254bfb06baa8a3847b9112552f9413420b9f0). Its P01-P09 workflow_dispatch job is guarded to execute only on ref staging. This fixes the missing default-branch entrypoint; runtime dispatch and acceptance remain pending.
- Owner authorization remains blocked: active Owner profile exists but Auth app metadata platform_owner is absent. No official Auth Admin update-user operation is exposed by the current connector. Do not mutate auth.users directly.
- Migration source parity is not clean: 47 DB applied rows vs 47 staging source files with one applied version missing from the staging directory and one unapplied branch_worker migration file. main has only two migration files. Production Supabase project is INACTIVE, so production migration history is not available for comparison.
- Staging DB configuration checks: 64/64 public tables RLS enabled; five stock SECURITY DEFINER RPCs deny anon/authenticated and permit service_role. Security Advisor WARN: leaked-password protection disabled. Performance Advisor INFO: 26 unindexed foreign keys.
- No production migration, deployment, data mutation, or Auth change was performed. Production remains untouched in this continuation.

## Fresh release-gate checkpoint — 2026-11-20

- Latest staging branch SHA: 4a13e70ce29e3fe117b6b6e7705089fa4241298a; main SHA: 2bb254bfb06baa8a3847b9112552f9413420b9f0.
- PR #96 is merged to main and makes the P01–P09 workflow dispatchable from the default branch; its job remains guarded to run only on staging.
- PR #97 is merged to staging and carries the P03 role-model correction plus E2E workflow configuration fixes.
- PR #102 and PR #103 are merged to staging. PR #103 includes the Owner Command Center summary foundation; its clean-database replay ran before the final normalized Owner migration and atomic checklist migration landed, so use the newer staging-head replay below as the authoritative database test.
- PR #104 contains production CORS source and static contract coverage. Its exact-head CORS contract and Deno type-check passed, but it remains Draft because merging to main triggers the Vercel production deployment. PR #96's earlier merge to main did trigger an automatic production deployment; details are recorded below.
- PR #74's bulk staging-to-main promotion was closed without merge; no bulk promotion is authorized.

### Current runtime blockers

- P01–P09 run [44579674471](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674471): **0 PASS, 0 FAILED, 9 BLOCKED, 0 SKIPPED; 0/9 probes executed**. The staging URL and publishable key passed preflight; Tenant A/B username/passwords and six tenant/branch/user fixture variables resolved empty in the runner. This does not prove the stored GitHub Environment values are absent; it proves the job did not receive them.
- KDS/POS/Stock positive E2E run [44579674219](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674219) stopped at preflight because Owner QA username/password resolved empty. The business-flow step was skipped and no transaction mutation ran.
- P0 HTTP bootstrap run [44579674185](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674185) stopped because Owner QA credentials were empty.
- Authenticated negative-probe run [44579674333](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674333) stopped because Tenant A credentials and the Tenant B branch fixture were empty.
- Staging CORS probes [44579674771](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674771) passed. This is not tenant-isolation acceptance.

### Database and security state

- Live migration parity is 48 applied / 52 source, with four pending source migrations and zero applied-without-source versions. The 52-migration clean replay and 67 pgTAP assertions passed in [44579674275](https://github.com/dlice8888/dlice-landing-page/actions/runs/44579674275).
- No pending migration has been applied to shared staging. No production migration or deployment was performed in this checkpoint.
- Owner Auth app_metadata.platform_owner=true and the server-side UUID allowlist remain unverified/blocked; do not use direct SQL against auth.users to bypass Auth Admin.
- Keep TENANT_ISOLATION_RELEASED=false and PUBLIC_TENANT_ROUTING_RELEASED=false.

**Decision remains NO-GO.** Do not merge PR #104 to main, apply the four pending migrations to shared staging, deploy Edge Functions, or promote to production until the Owner/Auth prerequisites, all nine runtime probes, positive E2E flows, and independent release review pass.

## Production deployment exception caused by PR #96 — 2026-11-20

PR #96 was merged to main to expose the guarded P01–P09 workflow dispatch entrypoint. The merge triggered Vercel Git integration and created production deployment **dpl_6wzdyEyDiyif7KRRWsdhDoRAUH6Q**, state READY, from main commit **2bb254bfb06baa8a3847b9112552f9413420b9f0**. Vercel confirms that the deployment aliases include **dlice.vercel.app**; therefore this was a live production deployment, not merely a Preview build.

The PR itself reported one changed file: .github/workflows/staging-tenant-isolation-acceptance.yml. However, main's post-merge tree comparison against the pre-PR restoration commit 85d889980da7d903db2348236b501b1b7281b533 shows two additions:
- .github/workflows/staging-tenant-isolation-acceptance.yml
- docs/audit/FNB_OS_IMPLEMENTATION_MATRIX.json

The 92 KB audit matrix was reintroduced because the PR branch had been created from an earlier main snapshot before the documentation restoration commit; the file was already in the PR branch's base snapshot and was therefore not shown as a PR file change. A scan of the reintroduced matrix found no JWT, Supabase secret/publishable key, bearer credential, password literal, or email pattern. No application HTML/JS, Edge Function source, Supabase schema, Auth metadata, or business data changed in this merge. Nonetheless, a production deployment occurred and must not be described as “no production deployment.”

No rollback, alias reassignment, production database change, or further production deployment has been performed in response to this finding. Keep all remaining main-target PRs Draft/HOLD. Any production rollback or corrective deployment requires an explicit release decision after assessing the live site and its prior deployment target.

## PR #104 source-provenance hold — 2026-11-20

The CORS contract and Deno type-check pass on PR #104, but its proposed Edge Function file is 239 lines. The current staging Edge Function is 2,271 lines with 121 action handlers and includes tenant-isolation release gating, Owner authorization, Command Center, and atomic checklist routes that are absent from the PR #104 file. This difference may reflect a deliberately separate production release, but the exact production export/version has not been independently verified. Keep PR #104 Draft/HOLD; do not deploy this file to Supabase or represent it as the full FnB OS Edge Function until its production provenance and intended scope are verified.
