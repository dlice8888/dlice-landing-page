# Branch cleanup final report

- Finalized: 2026-11-13T13:53:57Z UTC.
- Audit documents were committed and pushed to `audit/branch-cleanup-20261113`, based on current staging (initial audit commit `53a711ab679044fce9b910f5e815a1a1992d4aa1`); no application functionality was changed.

## Summary

| Measure | Result |
|---|---|
| Total remote branches before cleanup | 73 |
| Total remote branches after cleanup and audit-branch publication | 71 (70 after deletion, plus this audit branch) |
| Number deleted | 3 |
| Original branches preserved | 70 (includes `main` and `staging`) |
| Audit branch added for these deliverables | 1 (`audit/branch-cleanup-20261113`) |
| Branches awaiting migration verification | 38 |
| Preserved due to open PR head/base dependency | 8 branches (7 open PR heads plus the #21/#22 base branch) |
| Preserved for audit/release evidence | 5 branches (4 category-6 branches plus PR #64 audit branch; overlaps open-PR count) |
| Migration files found across remote branch histories | 66 (45 in current staging Git; 21 not in current staging Git) |
| Migrations currently confirmed APPLIED_AND_VERIFIED | 0 |

## Deleted branches

| Branch | SHA | PR / merge | Migration evidence | Deletion result |
|---|---|---|---|---|
| `ci/staging-cors-runtime-gate-20261023` | `ee73bd9625fbd2d5b9c2ddf725a71b7db5226e32` | #37; merged to staging (merge `6a38ff194ca13098aa2c72a2ad15e84bec6596e0`) | No migration changes in the PR/branch diff | GitHub delete succeeded; API confirmed absent at 2026-11-13T13:53:57Z. |
| `fix/staging-cors-secret-only-20261023` | `576d0781281ea826d19824990cd1668190d1ab46` | #32; merged to staging (merge `e7fd6fe5f379354648ff3db290eb96583937c788`) | No migration changes in the PR/branch diff | GitHub delete succeeded; API confirmed absent at 2026-11-13T13:53:57Z. |
| `test/staging-procurement-e2e-contract-v2` | `57ef016b7fd1a5ff436f16ece40b72ed2a1fc410` | #39; merged to staging (merge `17571890d29e2fe9f4410cb57f53de073427b9f5`) | No migration changes in the PR/branch diff | GitHub delete succeeded; API confirmed absent at 2026-11-13T13:53:57Z. |

## Preserved branches

All 70 original branches remaining after deletion are listed below with their exact SHA and preservation reason. Detailed ancestry, commit counts, changed paths, migration dependencies and PR state are in [BRANCH_RECONCILIATION.md](./BRANCH_RECONCILIATION.md).

The audit branch `audit/branch-cleanup-20261113` was created after the 73-branch baseline solely to preserve these deliverables; it is not part of the pre-cleanup inventory or deletion candidates. Its initial published commit is `53a711ab679044fce9b910f5e815a1a1992d4aa1`.

| Branch | SHA | Exact preservation reason |
|---|---|---|
| `audit/migration-reconciliation-runtime-tests-20261027` | `14079ad021bda177308938d1fa7231751ad14aa6` | Category 6 — AUDIT_OR_RELEASE_EVIDENCE — Audit/release evidence branch; preserve. |
| `audit/staging-completion-20261113` | `3b5012104ec29201c80127549c7d742b54221192` | Category 6 — AUDIT_OR_RELEASE_EVIDENCE — Audit/release evidence branch; preserve. |
| `audit/staging-migration-drift-denial-evidence-20261027` | `5519a47dd54b4fe371384a8b0ec53bcdddd3d800` | Category 6 — AUDIT_OR_RELEASE_EVIDENCE — Audit/release evidence branch; preserve. |
| `audit/tenant-isolation-inventory-20261028` | `86b19faeb354cca0e3d9a6f45e6d059376126b6c` | OPEN_PR — #64 (head); preserve head/base dependency and PR state. |
| `chore/align-applied-migration-version` | `f9418c19e2077068bf0c2925429333bd70bd5940` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `chore/default-branch-staging-e2e-entrypoints` | `0dfb8a9d39bf15a083005073f3f351bfee33bea1` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 12 commits are not ancestors of current staging; preserve unique work. |
| `chore/integrate-superpowers` | `847ed9d1527b95ac55d7fe533759e1567498d988` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 9 commits are not ancestors of current staging; preserve unique work. |
| `ci/staging-e2e-auto-schedule-20261025` | `04427123509cc635f64b3161494d7cebfb965daf` | Category 3 — CLOSED_PR_NOT_MERGED — Closed-unmerged PR work requires explicit resolution; preserve. |
| `ci/trigger-staging-pos-e2e-on-push` | `b2253c1e0d2bee40bc948b49e37417286f2f43e4` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `docs/2026-10-21-staging-audit` | `0df40311cdd4f6002fd975f5589205ae66b8a73c` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 1 commits are not ancestors of current staging; preserve unique work. |
| `docs/23-item-staging-readiness` | `45c46e1624cb5450fa7af1435e7affac589b16b6` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 1 commits are not ancestors of current staging; preserve unique work. |
| `docs/fnb-os-prd-traceability-superpowers-20261023` | `8caa888fc4f2f1c565d54694bd707513956c7f89` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 1 commits are not ancestors of current staging; preserve unique work. |
| `feat/fnb-os-branch-ops-checklists-20261022` | `0d58fe35bc94a7a13c4d94597824df8f27fdbb5f` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `feat/fnb-os-staging-implementation-20261021` | `1f4df514c9d1f7906f38a6062417519b0f8b5c3c` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `feat/free-hardening-optimizations` | `63c438c394f91a78610c937a3cd7796ff2292cd2` | Category 3 — CLOSED_PR_NOT_MERGED — Closed-unmerged PR work requires explicit resolution; preserve. |
| `feat/indonesian-operations-ui` | `a8033281d93724c86f8692be500592106ebf9e62` | Category 3 — CLOSED_PR_NOT_MERGED — Closed-unmerged PR work requires explicit resolution; preserve. |
| `feat/p0-cors-origin-hardening-20261022` | `6e9b6f79d9b1e55c14ee2534da9e9ca52e5f336a` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 2 commits are not ancestors of current staging; preserve unique work. |
| `feat/p1-stock-transfer-count-20261022` | `b84842eea23d941f2aaa593f1378820d1736eddb` | Category 2 — MERGED_BUT_MIGRATION_UNVERIFIED — Migration change detected; current staging migration history/schema not independently verified. |
| `feat/staging-elegant-responsive-motion` | `98dfe9ea9fec089ac63fde270b85f8b6399222a4` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `feat/staging-erp-workflows-api` | `acfe37ead0125a94a1e918e529c76615cf2b4adc` | OPEN_PR — #22 (head); preserve head/base dependency and PR state. |
| `feat/staging-kds-offline-tenant-20261024` | `27f50b513ed6b8348baf76f333c25460f21d2d81` | Category 2 — MERGED_BUT_MIGRATION_UNVERIFIED — Migration change detected; current staging migration history/schema not independently verified. |
| `feat/staging-multi-branch-erp-foundation` | `68e50c29f335d95f2e2339ca27925a250049e831` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `feat/staging-next-workflow-acceptance-20261023` | `6adce27672d3f9e73c376234934e8a4d30992907` | OPEN_PR — #31 (head); preserve head/base dependency and PR state. |
| `feat/staging-order-fulfillment-finance-production` | `3cb0089f3c673e522dc9f0c688bd38d6d7b9f690` | OPEN_PR — #21 (head); preserve head/base dependency and PR state. |
| `feat/staging-order-receipt-gates` | `193dbe1b04aca38d04765638f56638d3b9ca6a86` | OPEN_PR — #22 (base), #21 (base); preserve head/base dependency and PR state. |
| `feat/staging-pos-kds-stock-reconciliation-owner-e2e` | `64c8fcbfd9664d6b78431dba404e8ddc0322dcff` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `feat/staging-purchase-requisitions-20261023` | `b9468c543f70f5803287c8a379aec92899bffd45` | Category 2 — MERGED_BUT_MIGRATION_UNVERIFIED — Migration change detected; current staging migration history/schema not independently verified. |
| `feat/staging-safe-retention-rpc-audit` | `15d5a8dc59ebcde7c8d40990deacafd7c86e21fc` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `feat/staging-ux-cx-audit-motion-20261021` | `61f6678ae89ecc492ffa1525d90e2febdfee3c2e` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 1 commits are not ancestors of current staging; preserve unique work. |
| `feat/staging-ux-cx-final-reconcile-20261021` | `6b6cf54daea51c5b4d80d9382597146195ce19f3` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `feat/supabase-ordering-backend` | `6a7c6f1f07589d24d29386c8e7a4b577be386f9b` | Category 3 — CLOSED_PR_NOT_MERGED — Closed-unmerged PR work requires explicit resolution; preserve. |
| `feat/supabase-product-catalog` | `3a40e552b707f1928a780a94be8302da73db8e46` | Category 3 — CLOSED_PR_NOT_MERGED — Closed-unmerged PR work requires explicit resolution; preserve. |
| `fix-staging-tenant-auth-fallback-20261102` | `ea1f153ca4c0fe56b8d31aed100c2a1ab976cfaf` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 2 commits are not ancestors of current staging; preserve unique work. |
| `fix-staging-tenant-secret-map-20261102` | `027b498759c80267cd99c27969bcae1bb9e36b7a` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 1 commits are not ancestors of current staging; preserve unique work. |
| `fix/auto-run-staging-pos-kds-e2e` | `0dac5ed2ebefc73329c7cb2db8d3a000176e8d80` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `fix/erp-branch-scope-and-role-permissions` | `8858ede9dad017096c705370f56909efaf8b64c3` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 3 commits are not ancestors of current staging; preserve unique work. |
| `fix/kds-e2e-owner-auth-contract` | `83795e7f250435c68eb3483eb5c6baf1c0e2221c` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `fix/owner-only-pos-e2e-scope` | `1afc569bff2662ec28c05c35e41086395e23c3a3` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `fix/pos-idempotency-digest-schema` | `ee162491dbc9f71bdc3eaaca1431c51d7f8c61bc` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `fix/qa-recipe-repeatable-e2e` | `0774d6e7b89ad7bddde97e3dd59f63834721d656` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `fix/refund-tenant-scope-guard-20261027` | `d4de886c8dce7db8c229a57f48dfcb5ffc4ad6b1` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 23 commits are not ancestors of current staging; preserve unique work. |
| `fix/rls-advisor-service-role-policies` | `e8fcaf38d037ac2a6c695d0d50cebdf782b23232` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `fix/staff-password-minimum-8-20261029` | `f0927cc1d76b4e52e94b9b60144554937569d87a` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 1 commits are not ancestors of current staging; preserve unique work. |
| `fix/staging-e2e-schedule-main-20261025` | `9099c6c0a76359cb8470b1b7c88b54cf0618cb94` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 15 commits are not ancestors of current staging; preserve unique work. |
| `fix/staging-erp-index-migration-version` | `2ef85c5a276047175b1a53775b0c910fe3fb82e1` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `fix/staging-erp-migration-version` | `de3144005396c9b28c78cd319a50c32d1f0dea85` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `fix/staging-explicit-deny-policies-20261025` | `f21a6770e7c14d172bc87aff28953b750daa951e` | Category 2 — MERGED_BUT_MIGRATION_UNVERIFIED — Migration change detected; current staging migration history/schema not independently verified. |
| `fix/staging-migration-history-align-20261027` | `006187c12572c1c12c27b8c0266422cb628f8d61` | Category 2 — MERGED_BUT_MIGRATION_UNVERIFIED — Migration change detected; current staging migration history/schema not independently verified. |
| `fix/staging-migration-version-parity` | `6474a9016cc8a424ae1adfd76e3032beb0acbf76` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `fix/staging-owner-preflight-wording` | `ceaec9c31c643261368aa0146ff87bdd965e0963` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 1 commits are not ancestors of current staging; preserve unique work. |
| `fix/staging-owner-profile-e2e` | `bbfbf8f24988b2dfc58e1b0ce2afefc9b397e08c` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `fix/staging-payment-proof-signature-validation` | `df3f6ff0952793d44c5b70c68ad4fc4dd27a65de` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 5 commits are not ancestors of current staging; preserve unique work. |
| `fix/staging-procurement-receipt-item-ids-20261023` | `cc523b62190a020464b7a66558a72fc7b0c8ec47` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 8 commits are not ancestors of current staging; preserve unique work. |
| `fix/staging-product-copy-migration-version` | `4823d707775b9ec52a5abfc84a8146cba994b3ce` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `fix/staging-public-p0-independent-20261030` | `0d88926b626a651c56b30040f5400d099d259db1` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 2 commits are not ancestors of current staging; preserve unique work. |
| `fix/staging-security-timezone-20261021` | `7f79625a5000fc501c089860b4ee76b6a10b8453` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 2 commits are not ancestors of current staging; preserve unique work. |
| `fix/staging-tenant-fixtures-20261103` | `60fb9b90be68564a8975c4aee40d4a03adddb1c6` | OPEN_PR — #71 (head); preserve head/base dependency and PR state. |
| `main` | `8d74dbda81eb483a26d779b782fd4b37e12af770` | CORE_PROTECTED — never delete or rewrite; SHA and existence verified unchanged. |
| `perf/staging-erp-foreign-key-indexes` | `dfc05f60c0fb8a2dc1b7c0deaa23043e1c396da0` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `security/production-cors-fail-closed-20261027` | `9115ec20c8ed9936f9a30898435963fd6021bcdf` | OPEN_PR — #63 (head); preserve head/base dependency and PR state. |
| `security/revoke-trigger-rpc-execute-20261027` | `4329dc32d72262757eead4d26e5c3d2a2052d7eb` | OPEN_PR — #62 (head); preserve head/base dependency and PR state. |
| `staging` | `aed2733f62506ed87a5040a48f479753fdafe1b1` | CORE_PROTECTED — never delete or rewrite; SHA and existence verified unchanged. |
| `staging-acl-source-sync-20261102` | `a3d4df36fec0f270c634cbe6d49626a4cdf6b70a` | Category 2 — MERGED_BUT_MIGRATION_UNVERIFIED — Migration change detected; current staging migration history/schema not independently verified. |
| `staging-runtime-tenant-gate-20261102` | `f0f712f108a323a9c180f47dfca4ff0287d82c5d` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 3 commits are not ancestors of current staging; preserve unique work. |
| `test/contracts-match-vertical-slice` | `2c8ce9a6928ed481355d5154d356020ae8ae5106` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `test/staging-150-branch-readonly-load` | `d55efa2240910227f41fcd515ac2b5cc72752e30` | Category 6 — AUDIT_OR_RELEASE_EVIDENCE — Audit/release evidence branch; preserve. |
| `test/staging-purchase-requisition-e2e-contract` | `38b2aba01f103ffb4669f78a55842bece59a210e` | Category 3 — CLOSED_PR_NOT_MERGED — Closed-unmerged PR work requires explicit resolution; preserve. |
| `test/staging-release-contract-gates` | `585967e67a464948b1da58699ec1cb90fe6bc754` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — 2 commits are not ancestors of current staging; preserve unique work. |
| `test/strict-pos-kds-stock-report-slice` | `061e9fd8b7adb66dffc2cb49824ebe0c9b9c91ab` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |
| `test/strict-pos-kds-stock-report-slice-v2` | `416e1f2ac322cce0a7bf28d3797cb70cc0258117` | Category 5 — UNIQUE_WORK_NOT_IN_STAGING — Unique branch work/migration is not fully proven in current staging. |

## Migration verification

See [STAGING_MIGRATION_RECONCILIATION.md](./STAGING_MIGRATION_RECONCILIATION.md). All 45 Git-staging versions remain `UNKNOWN` pending current Supabase migration-history and schema evidence; 21 branch-only versions are `MISSING_FROM_STAGING` in Git. The withheld PR #64 migration was not applied. `TENANT_ISOLATION_RELEASED=false` remains unchanged. The nine required tenant scenarios are all `NOT VERIFIED`; none is claimed executed and passed.

## Repository protection

See [REPOSITORY_PROTECTION_AUDIT.md](./REPOSITORY_PROTECTION_AUDIT.md). Both ruleset POST operations failed with HTTP 403 `Resource not accessible by integration`; no ruleset exists. Branch API reports `protected=false` for main and staging. Protection remains a blocker.

## Pull requests and issues preserved

All live PRs and issues remain open; no PR state was changed. PR #64 remains Draft/unmerged and PR #63 remains open/unmerged.
- PR #21: feat: add staged order fulfillment, production and finance controls; OPEN Draft; `feat/staging-order-fulfillment-finance-production` -> `feat/staging-order-receipt-gates`.
- PR #22: feat: wire order fulfillment, production and finance workflows; OPEN Draft; `feat/staging-erp-workflows-api` -> `feat/staging-order-receipt-gates`.
- PR #31: test(staging): add next FnB OS workflow acceptance gate; OPEN Draft; `feat/staging-next-workflow-acceptance-20261023` -> `staging`.
- PR #62: Security: revoke client RPC access to trigger-only functions; OPEN; `security/revoke-trigger-rpc-execute-20261027` -> `staging`.
- PR #63: Security: fail closed on production order-function CORS; OPEN; `security/production-cors-fail-closed-20261027` -> `main`.
- PR #64: docs(security): staging tenant isolation audit and release gates; OPEN Draft; `audit/tenant-isolation-inventory-20261028` -> `staging`.
- PR #71: ci(security): externalize and validate staging tenant fixtures; OPEN Draft; `fix/staging-tenant-fixtures-20261103` -> `staging`.
- Issue #34: FnB OS implementation tracker — Superpowers P0–P4, 18 domains; OPEN.
- Issue #45: Restore reproducible staging QA fixtures and preflight Auth before E2E; OPEN.

## Post-cleanup evidence

- Paginated GitHub branch count after cleanup and audit-branch publication: 71. All seven open PR head branches still exist; the three deleted refs are absent.
- `main` remains at `8d74dbda81eb483a26d779b782fd4b37e12af770`; `staging` remains at `aed2733f62506ed87a5040a48f479753fdafe1b1`.
- Current staging still has 45 migration files. No Supabase migration or production operation was attempted.
- Open PR state after cleanup: #21, #22, #31, #62, #63, #64, #71 remain OPEN; #64 remains Draft. Open issues #34 and #45 remain OPEN.
- Ruleset list remains empty. No branch protection write succeeded.
- `node scripts/quality-checks.mjs`: PASS. `git diff --check`: PASS.
- GitHub Actions `Free quality checks` run `43438214189` completed SUCCESS for the published audit commit `53a711ab679044fce9b910f5e815a1a1992d4aa1`.
- Latest staging `auth-negative` workflow check: FAILURE (run `43434328863`); no nine-probe release claim is made.

## Failures and blockers

- GitHub ruleset API creation: HTTP 403 `Resource not accessible by integration` for both requested rulesets. Classic branch-protection GET also returned HTTP 403 with the same message.
- Supabase CLI is not installed and no staging read-only database connector is available; current exact migration history and expected schema effects cannot be verified. No secret values were accessed.
- Tenant-isolation runtime checks have not produced an all-nine passing artifact; release remains false.
- Exact deletion-command wall-clock times were not emitted by `git push`; execution date is 2026-11-13 and individual branch absence was verified at 2026-11-13T13:53:57Z.

## Final acceptance

| Criterion | Status |
|---|---|
| All remote branches inventoried from live paginated API | PASS |
| All branches reconciled against latest staging SHA | PASS (ancestry, ahead/behind, paths/stat inspected; uncertain work preserved) |
| Migration-bearing branches have current history and schema evidence | BLOCKED |
| Every deletion satisfies criteria and was individually verified | PASS (3 deletions) |
| `main` and `staging` remain intact with unchanged SHAs | PASS |
| No open PR head branch deleted | PASS |
| PR #64 remains Draft/open/unmerged | PASS |
| PR #63 remains open/unmerged | PASS |
| No production migration/deployment triggered | PASS |
| Rulesets configured and effective | FAIL/BLOCKED (write API 403; no rulesets) |
| Branch protection effectively enforced | FAIL (branch API `protected=false`; rulesets empty) |
| All audit docs complete and committed on an audit branch | PASS — pushed to `audit/branch-cleanup-20261113` |
