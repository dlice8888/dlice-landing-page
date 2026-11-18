# D’Lice PR reconciliation master inventory

**Snapshot:** 2026-11-17 UTC
**Repository:** `dlice8888/dlice-landing-page`
**Scope:** The 14 open PRs named in the reconciliation request.
**Safety:** No PR was merged or closed; no branch was deleted; no workflow was dispatched; no staging or production deployment or migration was performed.

## Evidence boundary

GitHub PR metadata, current head SHAs, changed-file statistics, review decisions,
and check summaries were queried on 2026-11-17. The source checkout is
`fix/tenant-scoped-permissions-qa` at `8f31f6d201e7bcda0041dfcda8e6123a42b6ba14`,
six commits behind its remote branch and already contains five modified files.
Those pre-existing edits were not overwritten. The checkout SHA currently equals
the reported head SHA for PR #79, while the current PR #75 head is
`79f785711f70af51926bca07f7f4cfddbb0f6179`; therefore local test results are not
evidence for the current remote head of every PR.

Branch protection and staging-environment secret/variable metadata requests
returned HTTP 403. No secret values were queried. The API did not expose a
reliable required-reviewer/ruleset inventory. No Supabase CLI, Deno, or local
PostgreSQL client is installed in this checkout, so database replay and Deno
unit tests could not be run.

For Phase 2, the current GitHub PR base/head SHAs were rechecked. `main` is
`8d74dbda81eb483a26d779b782fd4b37e12af770`; `staging` is
`aed2733f62506ed87a5040a48f479753fdafe1b1`. All implementation commits below
exist only in isolated local worktrees; none was pushed and the GitHub PR heads
remain unchanged.

`mergeable=false` was not treated as proof of a file conflict. A local
`git merge-tree --write-tree` comparison of the exact API base/head SHAs found
the five paths below in PRs #79, #74, #73, and #62. PR #64 is a discrepancy:
GitHub reports `dirty`, but that exact local tree comparison produced no
conflicting paths. Recheck it against a fresh fetch before any rebase.

## PR inventory

| PR | Scope | Base → head (SHA) | Commits; files; diff | Draft / GitHub merge state | Checks on reported head | Review evidence | Dependencies / remaining work | Final status |
|---|---|---|---|---|---|---|---|---|
| [#79](https://github.com/dlice8888/dlice-landing-page/pull/79) | Enterprise FnB OS integration | `main` → `feat/enterprise-fnb-os-integration` (`8f31f6d…`) | 334; 135; +13,087/−24 | Ready; `dirty` | 8/8 pass | No approval; 1 conversation comment | 45 migrations and 135 files; five conflicts resolved only in local candidate; broad overlap with #73/#74 and #21/#22/#62/#75–#78; domain owner/acceptance boundaries documented, but file/commit mapping and split not done | `SPLIT_REQUIRED` |
| [#74](https://github.com/dlice8888/dlice-landing-page/pull/74) | Staging → main promotion | `main` → `staging` (`aed2733…`) | 308; 119; +11,665/−24 | Ready; `dirty` | 3 pass, 1 fail [`auth-negative`](https://github.com/dlice8888/dlice-landing-page/actions/runs/43434328863) | No approval; 1 conversation comment | Five merge conflicts; staging promotion is not a production-ready release plan; reconcile migrations, staging-only changes, and failed acceptance before creating scoped promotion PRs | `NOT_SAFE_TO_MERGE` |
| [#73](https://github.com/dlice8888/dlice-landing-page/pull/73) | Branch-cleanup/audit branch | `main` → `audit/branch-cleanup-20261113` (`48f43c1…`) | 310; 126; +12,132/−24 | Ready; `dirty` | 3/3 pass | No approval; 1 conversation comment | Five merge conflicts; changed-file set substantially overlaps #74/#79; no branch deletion or cleanup action is evidenced by the PR summary alone | `SPLIT_REQUIRED` |
| [#75](https://github.com/dlice8888/dlice-landing-page/pull/75) | Tenant-scoped permissions and staging isolation probes | `staging` → `fix/tenant-scoped-permissions-qa` (`79f7857…`) | 32; 24; +1,756/−267 | Ready; `clean` | 8/8 pass | 3 `COMMENTED` reviews; no approval decision; 5 conversation comments | Local checkout is six commits behind and dirty; existing local inactive-membership change is not on the reported remote head; stage/A-B runtime acceptance and independent approval still needed | `READY_AFTER_FIXES` |
| [#76](https://github.com/dlice8888/dlice-landing-page/pull/76) | Executive Command Center summary | `staging` → `feat/erp-command-center-foundation` (`1158cb5…`) | 13; 9; +556/−18 | Draft; `clean` | 9/9 pass | 3 `COMMENTED` reviews; no approval decision; 3 conversation comments | Review SQL/RPC authorization and independent review; keep draft until accepted | `DRAFT_HOLD` |
| [#77](https://github.com/dlice8888/dlice-landing-page/pull/77) | Atomic branch checklist audit | `staging` → `fix/branch-checklist-audit-atomicity-20261114` (`f8c6632…`) | 6; 8; +826/−57 | Draft; `clean` | 9/9 pass | 3 `COMMENTED` reviews; no approval decision; 2 conversation comments | Migration replay claim is in PR text; this environment could not reproduce it. Keep draft pending independent review and replay evidence | `DRAFT_HOLD` |
| [#78](https://github.com/dlice8888/dlice-landing-page/pull/78) | Atomic tenant bootstrap | `staging` → `fix/atomic-tenant-bootstrap-staging-20261114` (`8fa13f3…`) | 5; 7; +427/−11 | Draft; `clean` | 9/9 pass | 3 `COMMENTED` reviews; no approval decision; 2 conversation comments | No Owner/Auth Admin or secret-manager verification; test RPC rollback and ambiguous outcomes in disposable DB; preserve tenant release gate | `DRAFT_HOLD` |
| [#71](https://github.com/dlice8888/dlice-landing-page/pull/71) | Staging tenant fixture preflight | `staging` → `fix/staging-tenant-fixtures-20261103` (`60fb9b9…`) | 36; 8; +691/−257 | Draft; `unstable` | 10 pass, 1 fail [`auth-negative`](https://github.com/dlice8888/dlice-landing-page/actions/runs/42423209284) | No approval; 1 conversation comment | Trusted tenant identities/configuration are unverified and environment metadata returns 403; resolve failed run and verify fixture ownership without inventing identities | `DRAFT_HOLD` |
| [#64](https://github.com/dlice8888/dlice-landing-page/pull/64) | Tenant isolation inventory and same-tenant stock-transfer migration | `staging` → `audit/tenant-isolation-inventory-20261028` (`86b19fa…`) | 49; 12; +950/−2 | Draft; `dirty` | 3 pass, 1 fail [`runtime-gates`](https://github.com/dlice8888/dlice-landing-page/actions/runs/42094053543) | 1 `COMMENTED` review; no approval decision; 36 conversation comments | Five-way acceptance is not evidenced; no migration replay or two-user runtime test; GitHub/local mergeability discrepancy requires refresh | `DRAFT_HOLD` |
| [#62](https://github.com/dlice8888/dlice-landing-page/pull/62) | Revoke client execution on trigger-only RPCs | `staging` → `security/revoke-trigger-rpc-execute-20261027` (`4329dc3…`) | 15; 11; +979/0 | Ready; `dirty` | 2/2 pass | 1 `COMMENTED` review; no approval decision; 1 conversation comment | Five merge conflicts; PR description says migration was applied to staging, but this was not independently verified; reconcile environment migration history before rerun | `READY_AFTER_REBASE` |
| [#63](https://github.com/dlice8888/dlice-landing-page/pull/63) | Production order-function CORS fail-closed change | `main` → `security/production-cors-fail-closed-20261027` (`9115ec2…`) | 1; 1; +238/0 | Ready; `clean` | 2/2 pass | 1 `COMMENTED` review; no approval decision; 1 conversation comment | CORS is not authorization; require independent review and verify required checks, which are not visible via current permissions | `READY_FOR_INDEPENDENT_REVIEW` |
| [#31](https://github.com/dlice8888/dlice-landing-page/pull/31) | Staging workflow acceptance gate | `staging` → `feat/staging-next-workflow-acceptance-20261023` (`6adce27…`) | 2; 2; +202/0 | Draft; `clean` | 5/5 pass | No approval; 1 conversation comment | Reported historical acceptance is not evidence for the current production-ready workflow state; run after the business-flow PRs on trusted staging | `DRAFT_HOLD` |
| [#22](https://github.com/dlice8888/dlice-landing-page/pull/22) | ERP workflow API and UI integration | `feat/staging-order-receipt-gates` → `feat/staging-erp-workflows-api` (`acfe37e…`) | 41; 17; +1,098/−45 | Draft; `clean` | 4/4 pass | No approval; 1 conversation comment | Shares 11 migration paths with #79; shares two identical migration blobs with #21; reconcile implementation/scope and stack after schema dependency decision | `DRAFT_HOLD` |
| [#21](https://github.com/dlice8888/dlice-landing-page/pull/21) | Order, fulfillment, production, and finance schema/control foundation | `feat/staging-order-receipt-gates` → `feat/staging-order-fulfillment-finance-production` (`3cb0089…`) | 3; 3; +264/0 | Draft; `clean` | 4/4 pass | No approval; 1 conversation comment | Its two migration paths are byte-identical across #22 and #79; settle one migration owner, then verify dependent API/UI behavior | `DRAFT_HOLD` |

`READY_*` indicates only the next review step, not merge authorization. All 14
PRs had an empty GitHub `reviewDecision` at snapshot time; any `COMMENTED` review
is not an approval.

## Conflict resolution log

| PRs | Paths | Finding | Resolution / test |
|---|---|---|---|
| #79, #74, #73 | `.github/workflows/procurement-requisition-contract.yml`; `.github/workflows/staging-kds-pos-stock-positive-e2e.yml`; `.github/workflows/staging-procurement-positive-e2e.yml`; `tests/staging/kds-pos-stock-positive.mjs`; `tests/staging/procurement-receiving-positive.mjs` | Reproduced five add/add conflicts in isolated worktrees. Selected the stricter `main` versions, preserving confirmation/trusted refs, branch-manager identity, negative/checklist assertions, strict paid-status checks, and fixture cleanup. | Local candidates: #79 `dcae9bd…` + regression commit `617309b9bd87fcb66498a01c0413116b72857a43`; #74 `01bfa15…` + `6bdb392431cdc33778b22d6f5ba518dd21dcdef2`; #73 `d2dea5c…` + `dbe63d7bf9946ef519fedbdfd5c59565017fcdc6`. `git merge-tree` against refreshed `main` is conflict-free. #79 KDS/receiving tests 18/18 and requisition contract PASS; syntax and `git diff --check` PASS on all three. No push or remote CI run. |
| #62 | Same five paths; PR base SHA `a021497…`, current `staging` SHA `aed2733…` | Reproduced conflicts and selected current staging-side versions. The target-side procurement E2E file contained an invalid newline string. | Local candidate `3784b1e…` + syntax fix `1f04c8e72954fc373713a8366ad8a0b161882780`. `git merge-tree` against current `staging` is conflict-free; both E2E files pass `node --check` and `git diff --check`. Migration replay and direct-client/authorized-server RPC runtime checks were unavailable. Do not equate this local candidate with PR #62's stale base or confirmed staging migration history. |
| #64 | No conflicting paths in exact local tree comparison | GitHub API says `dirty`; local comparison found no conflicting paths. | Unresolved discrepancy; refresh refs and rerun before rebase/merge. |

These are local candidate resolutions, not updates to GitHub branches. PR #62's
base SHA mismatch and the conflict candidates' lack of remote CI remain gates.

## Phase 2 implementation evidence

| PR | Local candidate commit | Change / evidence | Validation and remaining gate |
|---|---|---|---|
| #75 | `da6d0d0b6962189341adbe36b95b26a43934489b` | Permission resolver excludes inactive memberships; regression covers inactive membership and tenant intersection. | Focused permission/gate contracts 5/5; `quality-checks` PASS; staging release contracts PASS. Deno unit test NOT RUN (`deno` unavailable); no push. |
| #63 | `b99950e645ef38ef43491520ef0869503e4fd789` | Preserve exact-origin CORS fail-closed behavior; uncertified public/admin service-role actions stay closed behind release gates. | Authorization/CORS contracts 3/3; no production probe or deployment; no push. |
| #71 | `1641d90781da73f68f9b9eefb0d0032588902c81` | Remove manual runtime dispatch; tenant probe runs only on trusted `staging` pushes. | Workflow contract 1/1. Probe with missing credentials reports `FAIL`, 0/9 executed, 9 BLOCKED, exit 2; no false PASS and no fabricated identities. |
| #76 | `d567bdf77a5b9351f600c3d93c059f23d567c3b0` | Strengthen contract coverage that command-center access is platform-owner-only and aggregates only branch IDs from the authorized server path. | Command-center contract 4/4; SQL replay and live tenant aggregation NOT RUN (Supabase CLI/PostgreSQL unavailable). |
| #77 | No code change; remote head `f8c66324c0545857c3c58b2b5a194b97b99eb879` | Existing atomic checklist RPC and branch/tenant membership checks retained. | Checklist + KDS contracts 21/21. Wrong-branch runtime probes require real staging identities and remain BLOCKED. |
| #78 | `0bfd58fc584d7407a62ca04015a37f763cbd6c7a` | Add disposable Auth Admin API fixtures in the same temp replay context; SQL tests no longer write Auth metadata. Add duplicate-owner and audit-failure rollback assertions. | Node contracts 10/10, fixture-script syntax and workflow YAML parse PASS. pgTAP/migration replay NOT RUN (Supabase CLI/PostgreSQL unavailable); no staging/production Auth metadata changes. |
| #21 / #22 | No code change; heads `3cb0089f3c673e522dc9f0c688bd38d6d7b9f690` / `acfe37ead0125a94a1e918e529c76615cf2b4adc` | Both shared migration blobs reverified identical: `ce0e703…` and `fa1ae70…`. #21 is a 3-file schema/docs change; #22 is a 17-file API/UI/migration change. | No tests are tracked on either head; concurrency, idempotency, rollback, authorization, and disposable replay remain unverified. Select one migration owner and stack/re-scope before accepting. |
| #31 | No code change; remote head `6adce27672d3f9e73c376234934e8a4d30992907` | Existing staging acceptance workflow retained. | Acceptance probe syntax PASS; live staging business-flow acceptance NOT RUN. |

Existing remote CI results are unchanged. #74 `auth-negative` remains failed
because `STAGING_TEST_BRANCH_A_USERNAME` is unavailable
([run 43434328863](https://github.com/dlice8888/dlice-landing-page/actions/runs/43434328863)).
#71 `auth-negative` has the same missing-credential blocker
([run 42423209284](https://github.com/dlice8888/dlice-landing-page/actions/runs/42423209284)).
#64 `runtime-gates` had no valid Tenant A/B JWTs; zero probes executed
([run 42094053543](https://github.com/dlice8888/dlice-landing-page/actions/runs/42094053543)).
No new CI run URL exists because no local candidate was pushed.

## File overlap and technical scope

The changed-file sets confirm that #79/#74/#73 are large, overlapping snapshots,
not independent narrowly scoped changes. `supabase/functions/dlice-orders/index.ts`
appears in 11 PRs; `.github/workflows/quality-checks.yml` in 7; the tenant runtime
probe in 6; and the disposable migration workflow in 5. The three broad branches
share the same 45 migration paths. #21/#22 share two order/receiving migration
paths, and all 11 #22 migration blobs were byte-identical to #79 at the queried
heads. These shared paths must not be interpreted as permission to apply the
migrations again.

PR #79 reports 135 changed files across 18 PRD domains. This snapshot confirms
the size and overlap but does not claim that every domain's backend, schema,
UI, and tests were individually accepted. Split it at domain boundaries and
avoid duplicating the separate permission, command-center, checklist, bootstrap,
and order/ERP workflow PRs.

## Migration inventory

The PR file lists contain 50 distinct migration paths:

| Source(s) | Paths/count | Reconciliation finding |
|---|---|---|
| #79, #74, #73 | 45 paths listed below, covering ordering, POS/ERP, production/finance, branch operations, tenant foundation, procurement, internal-table denial, and trigger-only RPC revocation | Same paths appear in all three large snapshots. No disposable replay was available; do not promote the entire set as a unit. |
| #21, #22, #79 | `20261020194817_order_fulfillment_production_finance_controls.sql`; `20261020195004_atomic_purchase_receiving_and_production_consumption.sql` | Exact SHA-256 contents match between #21, #22, and #79. One migration owner/stack must be chosen; do not apply duplicate copies. |
| #22, #79 | Nine additional paths within the shared 45-path set: branch-routed checkout, finance refund/settlement guards, capacity edits, settlement matching, immutable refund records, paid-payment settlement guard, refund update guard, recipe activation, and deterministic production stock locks | Blob identity was checked for all 11 #22 migration paths against #79. |
| #62, #79, #74, #73 | `20261027140145_revoke_client_execute_on_trigger_only_functions.sql` | Same path in multiple branch diffs. PR #62 says staging already applied; verify migration history through authorized read-only evidence before any replay. |
| #64 | `20261028120000_enforce_same_tenant_stock_transfers.sql` | Same-tenant transfer enforcement; runtime/replay evidence not available here. |
| #71 | `20261108090000_atomic_tenant_audit_operations.sql` | Tenant audit operations; current fixture/auth acceptance fails and must be retested after trusted configuration. |
| #76 | `20261114110000_command_center_summary.sql` | Command-center summary RPC; review authorization and replay evidence. |
| #77 | `20261114120000_atomic_branch_checklist_audit.sql` | Checklist/audit atomicity; PR text claims disposable replay, not reproduced in this environment. |
| #78 | `20261114150000_atomic_owner_and_tenant_bootstrap.sql` | Bootstrap RPC; preserve server-side authorization and test rollback/ambiguous outcomes in disposable DB. |

No migration was applied. No rollback was needed because no migration was run.
This list reflects migration paths changed by the 14 PRs, not proof of which
versions are already present in staging or production.

The 45 shared core paths are:

```text
20261017183506_initial_dlice_ordering_schema.sql
20261017183509_index_ordering_foreign_keys.sql
20261017183535_atomic_checkout_and_private_payment_proofs.sql
20261017183537_seed_dlice_catalog.sql
20261017183540_admin_role_permissions.sql
20261017183542_product_catalog_storage.sql
20261017184921_admin_username_accounts.sql
20261017205317_receipt_payment_notification_gates.sql
20261017205718_payment_assets_and_settings_seed.sql
20261019183939_add_free_rate_limiting.sql
20261019184047_add_privacy_preserving_funnel_metrics.sql
20261019185240_atomic_payment_verification.sql
20261019185629_atomic_operational_status_changes.sql
20261020160307_lock_internal_table_rls.sql
20261020171825_safe_operational_retention_and_rpc_acl.sql
20261020185740_align_product_copy_and_prices.sql
20261020193327_multi_branch_pos_erp_foundation.sql
20261020193920_index_erp_foreign_keys.sql
20261020194817_order_fulfillment_production_finance_controls.sql
20261020195004_atomic_purchase_receiving_and_production_consumption.sql
20261020201601_branch_routed_online_checkout_capacity.sql
20261020201654_finance_refund_settlement_and_period_guards.sql
20261020201715_branch_capacity_on_order_edits.sql
20261020201812_atomic_payment_settlement_matching.sql
20261020202158_immutable_final_refund_records.sql
20261020202449_settlement_match_only_paid_payments.sql
20261020202805_refund_guard_all_updates.sql
20261020202830_atomic_recipe_version_activation.sql
20261020202841_deterministic_production_stock_lock_order.sql
20261021150339_deny_direct_client_access_on_internal_tables.sql
20261021151246_branch_timezone_checkout_cutoff.sql
20261021151524_index_remaining_erp_foreign_keys.sql
20261021182634_branch_operation_checklists.sql
20261022124132_stock_transfers_and_counts.sql
20261022130135_stock_transfer_approval_pick_reconcile.sql
20261023003006_revoke_direct_client_access_stock_workflows.sql
20261023160257_purchase_requisitions.sql
20261023160440_purchase_requisition_conversion_index.sql
20261023175347_kitchen_kds_idempotency_modifiers.sql
20261023175514_tenant_branch_platform_foundation.sql
20261023175946_tenant_branch_integrity_constraints.sql
20261023180455_kds_pos_deferred_dispatch.sql
20261025115812_fix_pos_idempotency_digest_schema.sql
20261027112330_explicit_deny_policies_server_only_tables.sql
20261027140145_revoke_client_execute_on_trigger_only_functions.sql
```

The five additional distinct paths are `20261028120000_enforce_same_tenant_stock_transfers.sql`,
`20261108090000_atomic_tenant_audit_operations.sql`,
`20261114110000_command_center_summary.sql`,
`20261114120000_atomic_branch_checklist_audit.sql`, and
`20261114150000_atomic_owner_and_tenant_bootstrap.sql`.

## Dependency graph and merge order

The PR bases show three independent integration families: main-targeted (#63,
#73, #74, #79), staging-targeted (#31, #62, #64, #71, #75–#78), and the
`feat/staging-order-receipt-gates` stack (#21/#22). Similar names and overlapping
files do not establish a Git dependency by themselves.

See [PR_DEPENDENCY_GRAPH.md](./PR_DEPENDENCY_GRAPH.md) for the graph and proposed
sequence. In particular:

- Keep #64 Draft/HOLD. Tenant release gates remain closed.
- Keep #78 Draft/HOLD pending authorized Owner/Auth Admin verification and
  transaction-level tests.
- #21 and #22 are same-base siblings, not a GitHub stack; shared migration
  identity suggests one schema owner and a rebase/stack decision before review.
- #31 is an acceptance gate, not evidence that #21/#22 runtime acceptance passed.
- #74 must not be merged as a staging-to-main promotion. Promote only scoped,
  production-reviewed changes after required checks and independent approval.
- Preserve all active branches. No branch was marked safe to delete.

## Local validation performed

| Check | Result |
|---|---|
| `node --test` for tenant refund scope, public-routing gate, and runtime tenant preflight contracts | PASS, 9/9; 0 skipped |
| `node scripts/quality-checks.mjs` | PASS |
| `node scripts/staging-release-contract-tests.mjs` | PASS; these are repository contract checks, not browser/runtime E2E |
| `deno test supabase/functions/dlice-orders/tenant-permissions_test.ts` | NOT RUN — `deno` executable unavailable |
| Disposable migration replay / `supabase test db` | NOT RUN — Supabase CLI and PostgreSQL client unavailable; PR #78 now provisions local Auth fixtures through Auth Admin for CI |
| Staging Tenant A/B, CORS runtime, or Auth Admin acceptance | BLOCKED — no authorized runtime/configuration access |

The current checkout's five pre-existing modified files were preserved. All
implementation commits are isolated, local, and unpushed. No PR was edited or
merged, no branch was deleted, and no staging/production migration or deployment
was performed.

## External authorization required

1. Repository administrators: provide authorized access to read branch
   protection/rulesets and verify required reviewers/checks for `main` and
   `staging`. Current API returned HTTP 403.
2. Staging environment administrators: verify the names/presence of required
   secrets and variables through GitHub Environment settings; this integration
   returned HTTP 403. Do not post values in chat.
3. Supabase administrators: verify real Tenant A/B IDs, active memberships,
   branch ownership, QA identities, and migration history through approved
   read-only/Admin paths. Do not fabricate fixtures or alter Auth metadata with
   SQL.
4. An authorized Auth Admin: configure any platform-owner identity/allowlist
   only through approved secret management and Auth Admin; independently verify
   metadata.
5. A maintainer: review the local conflict candidates, refresh/rebase PR #62
   against its actual target base, and run required CI before any push.

**Decision:** `PHASE 2 PARTIAL — LOCAL CANDIDATES READY FOR INDEPENDENT REVIEW;
EXTERNAL BLOCKERS REMAIN.` Four conflict candidates and scoped security/test
changes are committed only in isolated local worktrees. No GitHub PR head
changed. Database replay, complete ERP concurrency/authorization tests, trusted
staging acceptance, full #79 domain decomposition, required-review
configuration, and independent approval remain incomplete.
