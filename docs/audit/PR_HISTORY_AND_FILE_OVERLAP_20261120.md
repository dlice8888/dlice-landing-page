
**Snapshot:** 20 November 2026  
**Repository:** `dlice8888/dlice-landing-page`  
**Purpose:** full historical inventory from the first PR, with integration disposition. This is an audit record, not merge authorization.

## 1. Repository-wide counts

- Pull requests retrieved: **105** (PR numbers 1–107; gaps in numbering are preserved).
- Merged: **75**.
- Closed without merge: **25**.
- Open: **5**.
- Branches retrieved: **104**.
- Branches whose head is not referenced by any PR: **5**.
- Across the 105 PRs: **2,154 commits**, **894 PR-level file touches**, **69,654 additions**, and **2,061 deletions**. File touches are summed per PR and therefore include repeated files; they are not unique repository paths.

### PR count by target branch

| Base branch | Total | Merged | Closed unmerged | Open |
|---|---:|---:|---:|---:|
| `staging` | 57 | 38 | 15 | 4 |
| `feat/staging-order-receipt-gates` | 19 | 16 | 3 | 0 |
| `feat/staging-kds-offline-tenant-20261024` | 11 | 11 | 0 | 0 |
| `main` | 10 | 4 | 5 | 1 |
| `feat/supabase-ordering-backend` | 1 | 0 | 1 | 0 |
| `feat/supabase-product-catalog` | 1 | 0 | 1 | 0 |
| `feat/staging-erp-workflows-api` | 1 | 1 | 0 | 0 |
| `feat/staging-ux-cx-final-reconcile-20261021` | 1 | 1 | 0 | 0 |
| `fix/staging-security-timezone-20261021` | 1 | 1 | 0 | 0 |
| `feat/fnb-os-staging-implementation-20261021` | 1 | 1 | 0 | 0 |
| `feat/fnb-os-branch-ops-checklists-20261022` | 1 | 1 | 0 | 0 |
| `feat/p1-stock-transfer-count-20261022` | 1 | 1 | 0 | 0 |

## 2. Current open PR disposition

| PR | Base → head | Scope | Current disposition |
|---:|---|---|---|
| [#64](https://github.com/dlice8888/dlice-landing-page/pull/64) | `staging` → `audit/tenant-isolation-inventory-20261028` | docs(security): staging tenant isolation audit and release gates | STRICT HOLD — tenant stock-transfer migration and tenant runtime acceptance incomplete |
| [#71](https://github.com/dlice8888/dlice-landing-page/pull/71) | `staging` → `fix/staging-tenant-fixtures-20261103` | ci(security): externalize and validate staging tenant fixtures | HOLD — canonical A/B fixtures and all P01–P09 runtime probes still blocked |
| [#104](https://github.com/dlice8888/dlice-landing-page/pull/104) | `main` → `security/production-cors-contract-main-20261120` | security(cors): track production Edge Function source and fail-closed contract | HOLD — production CORS source; verify production runtime contract and independent review |
| [#106](https://github.com/dlice8888/dlice-landing-page/pull/106) | `staging` → `reconcile/migration-version-rpc-acl-20261120` | fix(db): align RPC ACL migration source with staging history | DRAFT — source filename reconciliation for ACL migration; current CI checks pass, independent review required |
| [#107](https://github.com/dlice8888/dlice-landing-page/pull/107) | `staging` → `feat/staging-runtime-config-smoke-20261118` | feat(frontend): use environment-validated Supabase runtime config | DRAFT — environment-scoped runtime config; latest Preview runtime smoke not yet executed |
| [#108](https://github.com/dlice8888/dlice-landing-page/pull/108) | `staging` → `docs/pr-history-inventory-20261120` | docs(audit): add full PR history and file-overlap inventory | DRAFT — documentation-only audit artifact; independent review of completeness required |
| [#109](https://github.com/dlice8888/dlice-landing-page/pull/109) | `staging` → `security/stock-transfer-same-tenant-20261120` | security(stock): enforce same-tenant stock transfers | DRAFT/HOLD — strict same-tenant boundary aligns with PRD; awaiting green CI, P01–P09 runtime gate, and independent review |

No open PR is approved for merge by this inventory. PR #74 is not used as a merge path.

## 3. File overlap, duplicate and dependency findings

### Confirmed identical or overlapping changes

1. **PR #97 and PR #100 — duplicate PR content.** Both target `staging`, have the same head branch and exact head SHA `34c73faf41fd745f9777eaa1c748f35ab1d91e72`, and the same five changed-file blob SHAs:
   - `.github/workflows/staging-kds-pos-stock-positive-e2e.yml`
   - `.github/workflows/staging-procurement-positive-e2e.yml`
   - `scripts/staging-release-contract-tests.mjs`
   - `tests/contracts/tenant-runtime-probe-contract.test.mjs`
   - `tests/runtime/dlice-tenant-jwt-isolation.mjs`
   
   PR #97 merged first; PR #100 merged later. The merge commits have different tree SHAs because other work landed between them. Treat #100 as a redundant re-merge of the same five file contents, not as a second feature implementation.

2. **PR #63 and PR #104 — same production Edge Function source.** The `supabase/functions/dlice-orders/index.ts` blob in PR #63 and PR #104 is identical (blob SHA `fbfa91717edf96601e78fd9d8cf59010ffe41dfa`). PR #104 adds the production CORS contract and supporting workflow/tests. Current `main` has no `supabase/functions/dlice-orders/index.ts` source file; this is a source-control reproducibility gap for production.

3. **Owner bootstrap — PR #78 → PR #102.** PR #102 renames the migration to monotonic timestamp `20261120100000_atomic_owner_and_tenant_bootstrap.sql`. This migration is in staging source but not applied to shared staging.

4. **Command Center — PR #76 superseded by PR #103.** PR #103 carries the current migration `20261120110000_command_center_summary.sql`, UI/API work and contract tests. The earlier #76 migration is not a separate migration to apply.

5. **Branch checklist — PR #77 superseded by PR #105.** PR #105 carries `20261120120000_atomic_branch_checklist_audit.sql` and current tests. Do not apply the old #77 migration separately.

6. **RPC ACL progression — PR #62 → #94 → #99.**
   - #62: trigger-only function ACL source.
   - #94: five stock workflow RPCs revoked from client roles; applied to staging as `20261118165519`.
   - #99: default public function EXECUTE revocation; applied to staging as `20261119182606` by the Supabase migration tool.
   - #106: aligns the repository filename with that exact applied version. Do not reapply the SQL.

7. **Initial product/order foundation — PRs #1–#3.** Their branch heads are ancestors of current staging. The ordering backend, product catalog and Indonesian operations UI are therefore represented in staging history, even though those original PRs closed without merging. They are not proof that the same implementation is present in `main`.

### Unique or potentially valuable work not to discard

- **PR #31:** a read-only role/branch acceptance workflow for P2P, O2C and Finance is not present in current staging at its original paths. It uses legacy secret names and a hard-coded Branch B UUID; salvage the test scenarios, not the old workflow unchanged.
- **PR #43:** adds a daily schedule to procurement E2E. Main already contains a scheduled procurement workflow; staging currently has a guarded manual workflow. Compare the main and staging guards and environment protection before deciding whether to port scheduling.
- **PR #73:** branch cleanup inventory/reconciliation documents contain useful historical evidence but were captured 13 November and are stale. Refresh before porting.
- **PR #79:** large Enterprise FnB OS PR to main. Its head is an ancestor of current staging (0 commits ahead, 36 behind); it is a broad snapshot, not a safe integration unit. Do not merge it or PR #74 wholesale.
- **PR #85:** branch-scoped inventory read implementation differs from the current staging handler. Current staging checks branch access and limits item metadata to inventory IDs present in the authorized branch balances. Preserve the current implementation; test the authorization boundary rather than replacing it with the older PR code.
- **PR #90:** ordinary `branch_worker` profile-role migration and P03 worker identity test. The migration source is now represented by applied staging version `20261119155309`; however current QA assignments contain no `branch_worker` profiles. Worker identity acceptance remains unproven.
- **PR #96:** merged to main and added only the guarded P01–P09 workflow file. A Vercel Production deployment was created after the merge; no app, Edge Function, schema or business-data change was part of that PR.
- **PR #22:** its index.html blob matches staging; the UX audit document is present in staging. No unique frontend code needs to be ported from that PR.

## 4. Branches without any PR head

- `docs/audit-current-fnb-os-delta-20261120` — `c8dfcfee725d75053a2f3cf6ffe3c87ee3642036` (protected=true)
- `feat/staging-order-receipt-gates` — `193dbe1b04aca38d04765638f56638d3b9ca6a86` (protected=true)
- `feat/staging-ux-cx-audit-motion-20261021` — `61f6678ae89ecc492ffa1525d90e2febdfee3c2e` (protected=true)
- `test/staging-150-branch-readonly-load` — `d55efa2240910227f41fcd515ac2b5cc72752e30` (protected=true)
- `test/strict-pos-kds-stock-report-slice` — `061e9fd8b7adb66dffc2cb49824ebe0c9b9c91ab` (protected=true)

Specific branch comparisons against current staging:
- `docs/audit-current-fnb-os-delta-20261120`: 30 commits ahead, 1 behind; 17 documentation files only. Useful audit evidence, but its migration count and RPC ACL section predate the ACL application in this continuation. Refresh before merging.
- `feat/staging-order-receipt-gates`: 0 ahead, 267 behind; ancestor only.
- `feat/staging-ux-cx-audit-motion-20261021`: 1 unique commit, one index.html change; review as a small UX candidate.
- `test/staging-150-branch-readonly-load`: 0 ahead, 79 behind; ancestor only.
- `test/strict-pos-kds-stock-report-slice`: 114 ahead, 81 behind and 20 changed paths; legacy snapshot with older migration timestamps. Preserve for test-scenario recovery, do not merge wholesale.

## 5. Main versus staging

- Current `main`: `2bb254bfb06baa8a3847b9112552f9413420b9f0`.
- Current `staging`: `39a9c96156b5c0af8b70e689da10cdd9b3b10122`.
- Compare status: diverged; main has 20 commits not in staging and staging has 370 commits not in main.
- Current main tree contains 2 migration source files and no `supabase/functions/dlice-orders/index.ts`; staging contains 52 migration files and the large Edge Function source.
- Do not merge staging wholesale. Port reviewed components into main through scoped PRs with production-specific configuration and independent review.

## 6. Branch protection / release governance

An active repository ruleset exists: ID `27559290`, applies to `~ALL`; both `main` and `staging` report `protected=true`.

Important limitations in the live ruleset:
- Required approving review count: **0**; required reviewers: **none**.
- Required status checks: **empty**.
- Required deployment environments: **empty**.
- Code-owner review and last-push approval flags are enabled, but no independent approval count is required. No CODEOWNERS file was found at the repository root, `.github/CODEOWNERS`, or `docs/CODEOWNERS`, so code-owner routing has no configured owners.
- Bypass actors include repository roles and integrations with `always`; current connected actor reports `current_user_can_bypass=always`.

Therefore the ruleset is active but does **not** enforce independent approval, required CI, or a staging deployment reviewer gate. Do not treat `protected=true` as proof that the release gate is complete. Repository administrator must tighten the ruleset through GitHub Settings.

## 7. Database and security snapshot

Supabase staging project: `higoadrzxnhzbbwhdbmh`.

| Item | Current verified result |
|---|---:|
| Source migrations on staging branch | 52 |
| Applied migration history rows | 49 |
| Applied DB version missing exact source filename | 1 — `20261119182606` (PR #106 corrects it) |
| Source migrations not yet applied | 3 — `20261120100000`, `20261120110000`, `20261120120000` |
| Duplicate source migration versions | 0 |
| Public tables with RLS enabled | 64/64 |
| Public functions | 29 |
| Public functions executable by anon | 0 |
| Public functions executable by authenticated | 0 |
| Public functions executable by service_role | 29 |

Additional SQL provenance review found:
- `20261017183537_seed_dlice_catalog`: the stored migration-history statement contains literal backslash-n separators while current source uses real line breaks. The three expected product rows exist (created at 2026-10-17 18:36:33 UTC) and were updated at 2026-10-20 18:57:40 UTC, matching the later catalog-copy migration timestamp. No missing catalog rows were found; confirm original seed provenance from the initial deployment/commit trace, and do not re-seed blindly.
- `20261019185240_atomic_payment_verification`: stored history statement lacks the explicit `p_order_id::text` cast now present in source; the live function definition contains the cast. Record as source/history provenance drift, not as an instruction to reapply.
- `20261020201654_finance_refund_settlement_and_period_guards`: stored history SQL is older than source; the live refund guard has the stronger immutable-field checks in source. Reconcile the function definition and original change provenance before any new migration.
- `20261022124132_stock_transfers_and_counts`: source and history order the two stock-transfer indexes differently; both indexes exist in staging. This is a statement-order difference, not a missing index.

The global ACL migration was applied to staging in this continuation. The `postgres` default privileges now revoke client EXECUTE; the `supabase_admin` default ACL still includes client EXECUTE for future objects owned by that role. No current public function is owned by `supabase_admin`; do not change internal role privileges without a supported role-lifecycle review.

## 8. Tenant and runtime acceptance

Read-only staging aggregates:
- Tenants: 2 total; 1 active and 1 trial.
- Active tenant memberships: 3 across 2 tenants; 2 branch-manager memberships and 1 tenant-owner membership.
- Active branch assignments: 3 across 2 tenants; 0 assigned profiles currently have the `branch_worker` profile role.
- Active Owner profiles: 1; linked Auth identity with JSON boolean `app_metadata.platform_owner=true`: 0.

Latest P01–P09 run on staging: **BLOCKED 9 / executed 0 / skipped 0** because credential and fixture inputs were empty. This is not a tenant-isolation pass or a test failure; no probe requests were sent. Authenticated A/B negative tests, POS/KDS/Stock positive E2E, and P0 HTTP Owner bootstrap were likewise blocked at preflight. Procurement receiving contract, KDS offline contract, CORS runtime probes and browser smoke have passed in their respective CI runs.

Release flags remain:
- `TENANT_ISOLATION_RELEASED=false`
- `PUBLIC_TENANT_ROUTING_RELEASED=false`

## 9. Integration rules

1. Review every PR against its actual changed files and blob SHAs, not just title or closed/merged status.
2. Resolve duplicates and timestamp conflicts before migration review.
3. Preserve unique tests and operational knowledge from closed-unmerged PRs, but port only current, fixture-safe versions.
4. Do not merge PR #74 or PR #79 as mass integration.
5. Do not apply the three pending migrations to shared staging until independent review, backup/restore evidence and explicit migration approval.
6. Do not promote to main or Production until P01–P09, tenant A/B negative tests, POS/KDS/Stock E2E, Procurement E2E, 18-domain regression, and backup/restore all pass.
7. No Production migration, alias change or deployment was performed as part of this audit.

## 10. Complete PR metadata inventory

The table below records every PR returned by the paginated GitHub API at the snapshot time. File counts are GitHub's PR-level counts; detailed overlap groups and dispositions are documented above.

| PR | State | Base | Head | Commits | Files | Churn | Title |
|---:|---|---|---|---:|---:|---:|---|
| #1 | CLOSED—UNMERGED | `main` | `feat/supabase-ordering-backend` | 12 | 7 | +383/-2 | feat: integrate Supabase ordering backend and admin panel |
| #2 | CLOSED—UNMERGED | `feat/supabase-ordering-backend` | `feat/supabase-product-catalog` | 16 | 8 | +207/-24 | Draft: Supabase-backed D’Lice product catalog |
| #3 | CLOSED—UNMERGED | `feat/supabase-product-catalog` | `feat/indonesian-operations-ui` | 13 | 3 | +63/-45 | Gunakan bahasa Indonesia untuk operasional D’Lice |
| #4 | MERGED | `feat/staging-order-receipt-gates` | `feat/free-hardening-optimizations` | 49 | 14 | +695/-21 | Staging: free hardening, security, and release gates |
| #5 | MERGED | `feat/staging-order-receipt-gates` | `fix/rls-advisor-service-role-policies` | 2 | 2 | +90/-0 | Staging: lock internal tables to service_role |
| #6 | MERGED | `feat/staging-order-receipt-gates` | `docs/23-item-staging-readiness` | 1 | 1 | +57/-0 | Docs: track 23-item staging readiness and production blockers |
| #7 | MERGED | `feat/staging-order-receipt-gates` | `test/staging-release-contract-gates` | 2 | 2 | +53/-0 | Test: add staging order release contract gates |
| #8 | MERGED | `feat/staging-order-receipt-gates` | `main` | 2 | 1 | +175/-108 | Docs: integrate production-branch PRD updates into staging |
| #9 | CLOSED—UNMERGED | `feat/staging-order-receipt-gates` | `feat/free-hardening-optimizations` | 49 | 14 | +695/-21 | Integration audit: reconcile free hardening branch with staging |
| #10 | MERGED | `feat/staging-order-receipt-gates` | `fix/staging-payment-proof-signature-validation` | 5 | 2 | +24/-1 | Fix: validate payment proof file signatures on staging |
| #11 | MERGED | `feat/staging-order-receipt-gates` | `feat/staging-safe-retention-rpc-audit` | 4 | 4 | +91/-3 | Staging: add safe operational retention and tighten RPC ACLs |
| #12 | MERGED | `feat/staging-order-receipt-gates` | `fix/staging-migration-version-parity` | 4 | 3 | +5/-7 | Fix staging migration version parity |
| #13 | MERGED | `feat/staging-order-receipt-gates` | `docs/2026-10-21-staging-audit` | 1 | 1 | +76/-0 | docs: record staging-only implementation audit |
| #14 | MERGED | `feat/staging-order-receipt-gates` | `feat/staging-elegant-responsive-motion` | 3 | 3 | +90/-2 | feat: elegant responsive D’lice staging experience |
| #15 | MERGED | `feat/staging-order-receipt-gates` | `fix/staging-product-copy-migration-version` | 3 | 3 | +9/-37 | fix: align catalog migration history with staging |
| #16 | MERGED | `feat/staging-order-receipt-gates` | `feat/staging-multi-branch-erp-foundation` | 8 | 6 | +739/-15 | feat: add multi-branch POS ERP workspace for staging |
| #17 | MERGED | `feat/staging-order-receipt-gates` | `fix/staging-erp-migration-version` | 3 | 2 | +3/-0 | fix: align ERP migration history with staging |
| #18 | MERGED | `feat/staging-order-receipt-gates` | `fix/erp-branch-scope-and-role-permissions` | 3 | 3 | +15/-6 | fix: enforce ERP branch isolation and job-based permissions |
| #19 | MERGED | `feat/staging-order-receipt-gates` | `perf/staging-erp-foreign-key-indexes` | 2 | 2 | +21/-0 | perf: index ERP foreign-key lookup columns |
| #20 | MERGED | `feat/staging-order-receipt-gates` | `fix/staging-erp-index-migration-version` | 3 | 2 | +1/-1 | fix: align ERP index migration version with staging |
| #21 | CLOSED—UNMERGED | `feat/staging-order-receipt-gates` | `feat/staging-order-fulfillment-finance-production` | 3 | 3 | +264/-0 | feat: add staged order fulfillment, production and finance controls |
| #22 | CLOSED—UNMERGED | `feat/staging-order-receipt-gates` | `feat/staging-erp-workflows-api` | 41 | 17 | +1098/-45 | feat: wire order fulfillment, production and finance workflows |
| #23 | MERGED | `feat/staging-erp-workflows-api` | `feat/staging-ux-cx-final-reconcile-20261021` | 5 | 2 | +86/-0 | feat: reconcile staging responsive UX and motion |
| #24 | MERGED | `feat/staging-ux-cx-final-reconcile-20261021` | `fix/staging-security-timezone-20261021` | 15 | 7 | +449/-43 | fix: harden staging CORS and branch timezone handling |
| #25 | MERGED | `fix/staging-security-timezone-20261021` | `feat/fnb-os-staging-implementation-20261021` | 71 | 13 | +1619/-10 | docs: audit FnB OS staging capability and track implementation |
| #26 | MERGED | `feat/fnb-os-staging-implementation-20261021` | `feat/fnb-os-branch-ops-checklists-20261022` | 37 | 8 | +524/-18 | feat: add branch opening and closing checklists |
| #27 | MERGED | `feat/fnb-os-branch-ops-checklists-20261022` | `feat/p1-stock-transfer-count-20261022` | 19 | 4 | +202/-0 | P1: Add branch stock transfer and cycle count workflows |
| #28 | MERGED | `feat/p1-stock-transfer-count-20261022` | `feat/p0-cors-origin-hardening-20261022` | 9 | 2 | +34/-3 | P0: Harden CORS responses for staging origin allowlist |
| #29 | MERGED | `main` | `chore/integrate-superpowers` | 5 | 5 | +120/-0 | chore: pin Superpowers submodule and engineering workflow |
| #30 | MERGED | `staging` | `feat/p1-stock-transfer-count-20261022` | 69 | 14 | +849/-371 | feat(staging): integrate P0 security and P1 stock workflows |
| #31 | CLOSED—UNMERGED | `staging` | `feat/staging-next-workflow-acceptance-20261023` | 2 | 2 | +202/-0 | test(staging): add next FnB OS workflow acceptance gate |
| #32 | MERGED | `staging` | `fix/staging-cors-secret-only-20261023` | 1 | 1 | +2/-5 | fix(staging): make CORS depend only on exact origin secret |
| #33 | MERGED | `staging` | `docs/fnb-os-prd-traceability-superpowers-20261023` | 1 | 1 | +86/-0 | docs: map all 18 FnB OS domains to verified staging evidence |
| #35 | MERGED | `staging` | `fix/staging-procurement-receipt-item-ids-20261023` | 8 | 5 | +305/-1 | fix(staging): restore PO receiving line IDs and add positive E2E gate |
| #36 | MERGED | `staging` | `feat/staging-purchase-requisitions-20261023` | 11 | 6 | +459/-4 | feat(staging): add purchase requisition workflow |
| #37 | MERGED | `staging` | `ci/staging-cors-runtime-gate-20261023` | 1 | 1 | +5/-0 | ci(staging): gate Edge Function changes on runtime CORS |
| #38 | CLOSED—UNMERGED | `staging` | `test/staging-purchase-requisition-e2e-contract` | 1 | 1 | +4/-0 | test(staging): verify requisition-to-stock E2E harness |
| #39 | MERGED | `staging` | `test/staging-procurement-e2e-contract-v2` | 1 | 1 | +4/-0 | test(staging): verify updated requisition-to-stock harness |
| #40 | MERGED | `staging` | `feat/staging-kds-offline-tenant-20261024` | 117 | 20 | +2428/-51 | [DRAFT] Kitchen/KDS, offline POS and SaaS branch platform foundation |
| #41 | MERGED | `main` | `chore/default-branch-staging-e2e-entrypoints` | 5 | 4 | +560/-6 | Expose guarded staging E2E workflows on the default branch |
| #42 | MERGED | `staging` | `fix/staging-explicit-deny-policies-20261025` | 7 | 4 | +263/-0 | [DRAFT] P0: make server-only table denial explicit |
| #43 | CLOSED—UNMERGED | `staging` | `ci/staging-e2e-auto-schedule-20261025` | 1 | 1 | +4/-1 | ci: automate guarded staging procurement E2E |
| #44 | MERGED | `main` | `fix/staging-e2e-schedule-main-20261025` | 2 | 2 | +8/-2 | ci: run guarded staging E2E schedules from main |
| #46 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `feat/staging-pos-kds-stock-reconciliation-owner-e2e` | 2 | 2 | +8/-19 | test(staging): unblock POS to KDS to stock E2E without Branch A login |
| #47 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/kds-e2e-owner-auth-contract` | 1 | 1 | +6/-2 | test(staging): align KDS E2E contract with Owner-only auth |
| #48 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/auto-run-staging-pos-kds-e2e` | 3 | 2 | +10/-11 | ci(staging): remove manual dispatch gate for POS/KDS/stock E2E |
| #49 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/staging-owner-profile-e2e` | 2 | 2 | +24/-0 | fix(staging): restore Owner operational profile for POS E2E |
| #50 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/owner-only-pos-e2e-scope` | 1 | 1 | +2/-27 | test(staging): scope positive E2E to POS/KDS/stock/report vertical slice |
| #51 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/pos-idempotency-digest-schema` | 3 | 3 | +171/-0 | fix(db): qualify pgcrypto digest in POS idempotency |
| #52 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/qa-recipe-repeatable-e2e` | 1 | 1 | +1/-14 | test(staging): keep QA recipe reusable between E2E runs |
| #53 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `test/strict-pos-kds-stock-report-slice-v2` | 2 | 2 | +8/-56 | test(staging): isolate required POS to report acceptance slice |
| #54 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `test/contracts-match-vertical-slice` | 1 | 1 | +8/-9 | test(contract): align staging E2E contract with automated vertical slice |
| #55 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `chore/align-applied-migration-version` | 3 | 2 | +1/-1 | chore(db): align migration file with applied staging version |
| #56 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `ci/trigger-staging-pos-e2e-on-push` | 1 | 1 | +1/-0 | ci(staging): run POS/KDS E2E after staging branch updates |
| #57 | MERGED | `staging` | `fix/staging-owner-preflight-wording` | 1 | 1 | +1/-1 | fix(staging): clarify Owner credential preflight |
| #58 | MERGED | `staging` | `fix/refund-tenant-scope-guard-20261027` | 23 | 4 | +171/-17 | fix(security): fail closed for unscoped refund processing |
| #59 | MERGED | `staging` | `fix/staging-migration-history-align-20261027` | 5 | 4 | +11/-4 | chore(staging): align deny-policy migration history |
| #60 | MERGED | `staging` | `audit/staging-migration-drift-denial-evidence-20261027` | 1 | 1 | +106/-0 | docs(staging): migration drift and denied-access no-mutation evidence |
| #61 | MERGED | `staging` | `audit/migration-reconciliation-runtime-tests-20261027` | 17 | 21 | +363/-10 | audit(staging): reconcile migration provenance and add runtime deny probes |
| #62 | CLOSED—UNMERGED | `staging` | `security/revoke-trigger-rpc-execute-20261027` | 15 | 11 | +979/-0 | Security: revoke client RPC access to trigger-only functions |
| #63 | CLOSED—UNMERGED | `main` | `security/production-cors-fail-closed-20261027` | 1 | 1 | +238/-0 | Security: fail closed on production order-function CORS |
| #64 | OPEN | `staging` | `audit/tenant-isolation-inventory-20261028` | 49 | 12 | +950/-2 | docs(security): staging tenant isolation audit and release gates |
| #65 | MERGED | `staging` | `fix/staff-password-minimum-8-20261029` | 1 | 1 | +2/-2 | fix(auth): set staff password minimum to 8 characters |
| #66 | MERGED | `staging` | `fix/staging-public-p0-independent-20261030` | 2 | 1 | +73/-0 | test: run public staging P0 checks independently of Owner login |
| #67 | MERGED | `staging` | `staging-acl-source-sync-20261102` | 1 | 1 | +7/-0 | chore(db): sync applied staging ACL migration source |
| #68 | MERGED | `staging` | `staging-runtime-tenant-gate-20261102` | 3 | 2 | +298/-0 | ci(security): stage trusted two-tenant runtime isolation gate |
| #69 | MERGED | `staging` | `fix-staging-tenant-secret-map-20261102` | 1 | 1 | +4/-4 | fix(ci): align runtime gate with current staging tenant secrets |
| #70 | MERGED | `staging` | `fix-staging-tenant-auth-fallback-20261102` | 2 | 2 | +24/-7 | fix(ci): support per-tenant staging login and JWT fallback |
| #71 | OPEN | `staging` | `fix/staging-tenant-fixtures-20261103` | 44 | 8 | +745/-258 | ci(security): externalize and validate staging tenant fixtures |
| #72 | MERGED | `staging` | `audit/staging-completion-20261113` | 1 | 3 | +16/-6 | security(ci): restrict staging auth probes to trusted pushes |
| #73 | CLOSED—UNMERGED | `main` | `audit/branch-cleanup-20261113` | 310 | 126 | +12132/-24 | Audit/branch cleanup 20261113 |
| #74 | CLOSED—UNMERGED | `main` | `staging` | 369 | 162 | +16067/-24 | Staging |
| #75 | MERGED | `staging` | `fix/tenant-scoped-permissions-qa` | 41 | 28 | +2528/-269 | fix(authz): resolve tenant-scoped permissions and staging isolation probes |
| #76 | CLOSED—UNMERGED | `staging` | `feat/erp-command-center-foundation` | 15 | 9 | +565/-18 | feat(erp): add owner command-center summary |
| #77 | CLOSED—UNMERGED | `staging` | `fix/branch-checklist-audit-atomicity-20261114` | 9 | 8 | +839/-58 | fix(branch-ops): make checklist audits atomic |
| #78 | MERGED | `staging` | `fix/atomic-tenant-bootstrap-staging-20261114` | 8 | 7 | +445/-11 | fix(authz): bootstrap tenant membership atomically |
| #79 | CLOSED—UNMERGED | `main` | `feat/enterprise-fnb-os-integration` | 334 | 135 | +13087/-24 | Feat/enterprise fnb os integration |
| #80 | CLOSED—UNMERGED | `staging` | `docs/staging-execution-baseline-20261117` | 14 | 6 | +377/-0 | docs(release): record verified staging execution baseline |
| #81 | MERGED | `staging` | `fix/staging-tenant-negative-probes-canonical-fixtures-20261118` | 4 | 3 | +20/-9 | fix(staging): align tenant negative probes with canonical fixtures |
| #82 | CLOSED—UNMERGED | `staging` | `docs/reconcile-tenant-evidence-20261118` | 1 | 2 | +4/-4 | docs(release): normalize staging evidence whitespace |
| #83 | CLOSED—UNMERGED | `staging` | `fix/p0-tenant-isolation-preflight-20261118` | 3 | 4 | +61/-5 | fix(security): fail closed on missing tenant probe inputs |
| #84 | MERGED | `staging` | `audit/fnb-os-continuation-20261118` | 97 | 10 | +3266/-0 | docs(audit): reconcile FnB OS implementation and release evidence |
| #85 | CLOSED—UNMERGED | `staging` | `fix/tenant-scoped-inventory-read-20261118` | 7 | 3 | +56/-22 | fix(security): scope inventory reads to authorized branch |
| #86 | CLOSED—UNMERGED | `staging` | `fix/tenant-worker-profile-role-20261118` | 6 | 6 | +148/-2 | fix(authz): distinguish branch workers from admin profiles |
| #87 | CLOSED—UNMERGED | `staging` | `test/tenant-p03-worker-identity-evidence-20261118` | 6 | 4 | +75/-39 | test(security): verify ordinary worker identity and masked P03 evidence |
| #88 | MERGED | `staging` | `fix/recover-migration-source-20261022140302-20261118` | 4 | 4 | +93/-0 | fix(db): restore missing applied migration source |
| #89 | MERGED | `staging` | `fix/staging-tenant-probe-scope-20261118` | 7 | 4 | +61/-24 | Fix staging tenant-isolation probe scope |
| #90 | MERGED | `staging` | `feat/staging-worker-identity-acceptance-20261118` | 8 | 8 | +224/-38 | Add ordinary worker identity and P03 tenant acceptance |
| #91 | MERGED | `staging` | `fix/staging-auth-negative-preflight-20261118` | 3 | 3 | +54/-5 | Fix authenticated staging negative-probe preflight |
| #92 | MERGED | `staging` | `fix/kds-staging-env-secret-scope-20261118` | 3 | 2 | +18/-6 | Use staging Environment secrets in KDS/POS/Stock E2E |
| #93 | CLOSED—UNMERGED | `staging` | `fix/staging-module-inline-contract-20261118` | 2 | 1 | +11/-2 | fix(ci): validate inline ES modules without rejecting top-level await |
| #94 | MERGED | `staging` | `security/staging-stock-workflow-rpc-acl-20261118` | 13 | 4 | +70/-0 | fix(security): revoke public execute on stock workflow RPCs |
| #95 | CLOSED—UNMERGED | `staging` | `fix/staging-tenant-p03-role-and-env-reconciliation-20261119` | 4 | 4 | +28/-16 | fix(staging): align tenant isolation roles and E2E config |
| #96 | MERGED | `main` | `fix/enable-staging-tenant-isolation-dispatch-main-20261119` | 1 | 1 | +108/-0 | ci(staging): enable P01-P09 manual dispatch from main |
| #97 | MERGED | `staging` | `reconcile/staging-ci-and-tenant-fixtures-20261119` | 6 | 5 | +43/-22 | fix(staging): reconcile CI parser and tenant E2E fixtures |
| #98 | MERGED | `staging` | `chore/reconcile-applied-branch-worker-migration-20261119` | 8 | 4 | +24/-34 | chore(db): reconcile applied branch worker migration source |
| #99 | MERGED | `staging` | `security/revoke-default-public-function-execute-20261119` | 18 | 6 | +120/-1 | security(db): revoke default client EXECUTE on future public RPCs |
| #100 | MERGED | `staging` | `reconcile/staging-ci-and-tenant-fixtures-20261119` | 6 | 5 | +43/-22 | fix(staging): consolidate validated tenant and CI contract fixes |
| #101 | CLOSED—UNMERGED | `staging` | `reconcile/recovered-migration-source-20261022140302-20261120` | 1 | 1 | +2/-0 | fix(db): restore exact applied FK index migration source |
| #102 | MERGED | `staging` | `fix/migration-order-owner-bootstrap-20261120` | 4 | 3 | +3/-1 | fix(db): preserve monotonic staging migration order for Owner bootstrap |
| #103 | MERGED | `staging` | `feat/command-center-summary-staging-20261120` | 7 | 7 | +361/-16 | feat(erp): add Owner Command Center summary |
| #104 | OPEN | `main` | `security/production-cors-contract-main-20261120` | 7 | 4 | +294/-0 | security(cors): track production Edge Function source and fail-closed contract |
| #105 | MERGED | `staging` | `feat/branch-ops-atomic-checklist-staging-20261120` | 9 | 7 | +830/-56 | feat(branch-ops): make branch checklist mutations atomic |
| #106 | OPEN | `staging` | `reconcile/migration-version-rpc-acl-20261120` | 4 | 3 | +35/-1 | fix(db): align RPC ACL migration source with staging history |
| #107 | OPEN | `staging` | `feat/staging-runtime-config-smoke-20261118` | 11 | 6 | +267/-5 | feat(frontend): use environment-validated Supabase runtime config |
| #108 | OPEN | `staging` | `docs/pr-history-inventory-20261120` | 27 | 1 | +497/-0 | docs(audit): add full PR history and file-overlap inventory |
| #109 | OPEN | `staging` | `security/stock-transfer-same-tenant-20261120` | 14 | 7 | +390/-15 | security(stock): enforce same-tenant stock transfers |


### Audit artifact provenance
This document records the 105-PR / 104-branch snapshot taken immediately before this audit document was submitted. The documentation PR that carries this file is excluded from that historical count to avoid self-reference.

### CI state at snapshot
- PR #106 latest head `c256de028f1728bcc00255718a66c9f84307721f`: Free quality checks, KDS contract and disposable migration replay all PASS. It remains Draft and requires independent review.
- PR #107 latest Preview CORS probes and Procurement receiving contract PASS; Free quality and requisition contract checks were still running. Runtime-config smoke against the exact Preview URL has not yet been executed.


### Post-snapshot update
After this inventory snapshot, PR #108 was created to carry this audit document. The current open-PR count therefore includes PR #108; the 105-PR / 5-open count above is intentionally frozen at the snapshot before PR #108.


## 11. Post-snapshot verification addendum — 20 Nov 2026

### P0 RPC ACL runtime
- Supabase staging applied migration version `20261119182606_revoke_default_public_function_execute`.
- Read-only post-application inventory: 29 public functions; 0 executable by `anon`; 0 executable by `authenticated`; 29 executable by `service_role`.
- All 29 current public functions are owned by `postgres`; five are SECURITY DEFINER. The default function ACL for `postgres` revokes client EXECUTE. The `supabase_admin` default ACL still includes client EXECUTE for future functions created under that role; no current public function is owned by `supabase_admin`. Do not alter internal role membership/ACL without a supported Supabase role-lifecycle review.
- PR #106 is a filename/source-history rename only: `20261119160000_...` → `20261119182606_...`; SQL bytes are unchanged. Latest PR #106 checks: Free quality checks, KDS offline contract and disposable migration replay all SUCCESS. It remains Draft/open and requires independent review. Do not reapply the migration.

### Tenant fixture correction
- Latest staging P01–P09 run `44579674471`: **BLOCKED 9 / executed 0 / skipped 0**. Four canonical username/password secrets and six tenant/branch/user variables were empty; no authenticated probe request ran.
- Tenant A's earlier fixture user `378f02bc-2719-4b07-9107-4ce94299aa27` is a global admin profile `owner` and tenant membership `tenant_owner`, not an ordinary branch-manager identity. Do not use it for branch-manager negative isolation acceptance.
- Correct Tenant A branch-manager identity: `b930897c-f8fb-443b-9056-e70c08b31446`; Auth identity confirmed and not banned, active Tenant A `branch_manager` membership, active assignment to QA branch A `90000000-0000-4000-8000-000000000001`.
- Tenant B identity `e1de1ffc-9fae-412f-9dd7-0993b54cb631` remains valid: Auth confirmed and not banned, active Tenant B `branch_manager` membership, active assignment to QA branch B `90000000-0000-4000-8000-000000000004`.
- Both QA branches currently have two real `branch_inventory` rows; total `on_hand` is 1,240 for A and 800 for B. Own-branch and cross-tenant behavior still require authenticated runtime proof.
- Tenant B admin-profile display name still refers to “Branch A Manager”; treat as stale QA profile text and correct only through authorized admin UI after confirming the account owner.
- PR #71 description was updated with the corrected fixture and these blockers. PR #71 remains Draft/HOLD.

### PR #71 migration ordering and salvage candidate
- PR #71 introduces `20261108090000_atomic_tenant_audit_operations.sql` with four SECURITY INVOKER/service-role RPCs: `platform_bootstrap_tenant_owner`, `erp_create_warehouse_with_audit`, `erp_transition_purchase_order_with_audit`, and `erp_create_purchase_order_with_audit`.
- This timestamp is older than the current staging applied migration version `20261119182606`. Do not merge or apply this migration filename as-is. If its functionality is retained after independent security and rollback review, regenerate it with a new forward-only timestamp and replay the complete migration chain in a disposable database.
- These four RPCs are potentially useful atomicity improvements for tenant bootstrap, warehouse audit, and PO create/transition audit. They are not yet part of staging's current 52-file migration source or 49-row applied history. Their inclusion in PR #71 must be evaluated function-by-function; do not merge PR #71 wholesale.

### Current migration parity
- Staging source: 52 migration files; applied history: 49 rows.
- Applied version missing exact source filename on the staging branch: `20261119182606` (PR #106 carries the rename).
- After PR #106 source reconciliation, three newer source migrations remain unapplied: `20261120100000_atomic_owner_and_tenant_bootstrap.sql`, `20261120110000_command_center_summary.sql`, and `20261120120000_atomic_branch_checklist_audit.sql`.
- No duplicate source timestamps were found.


### Tenant fixture auto-discovery candidate branch
- Branch `fix/tenant-isolation-discover-fixtures-20261120`, head `f18748e96f6b0329af8aa77f026f49984151049e`, is 8 commits ahead of current `staging` and 0 behind at the time checked. It is not associated with an open PR.
- It modifies the current `staging-tenant-isolation-acceptance.yml` workflow and the P01–P09 runner to derive tenant, branch, and user IDs from the two authenticated users' self-membership and assigned-branch responses. This removes the six currently empty ID variables while retaining the four canonical username/password secrets and exact staging URL/public key checks.
- Its resolver enforces distinct Auth identities and tenants, active membership, supported `sales_admin` global profile, `branch_manager` tenant role, equal non-empty tenant permission sets, branch assignment separation, and exact unique QA branch-code matches. It supports multiple same-tenant branch assignments for Tenant A.
- Latest Free quality checks run `44593578517` completed SUCCESS. The job ran static checks, runtime probe contract tests, tenant permission tests, and the new authenticated-fixture-discovery unit tests. It did **not** run staging P01–P09; the four canonical login secrets remain unavailable/empty.
- The candidate is more suitable than the six-ID-variable version for this staging fixture model. Preserve it for a narrow port/review into PR #71 or a single scoped follow-up; do not merge the branch or create another PR automatically. It still cannot close the runtime gate without valid canonical credentials for the corrected A and B users.


### Current open-PR head/base reconciliation — 20 Nov 2026
GitHub compare results against each PR's current base branch:

| PR | Head commits ahead | Base commits behind head | Changed files | Compare state | Mergeable |
|---:|---:|---:|---:|---|---|
| #64 | 49 | 76 | 12 | Closed without merge | No |
| #71 | 44 | 63 | 8 | Diverged | No |
| #104 | 7 | 0 | 4 | Ahead | Yes |
| #106 | 4 | 0 | 3 | Ahead | Yes |
| #107 | 11 | 10 | 6 | Diverged | Yes |
| #108 | 27 | 0 | 1 | Ahead | Yes |
| #109 | 14 | 0 | 7 | Ahead | Yes |

Implications:
- #64 and #71 are stale against current staging and cannot be merged without explicit reconciliation/rebase. Do not use their stale base snapshots as integration targets.
- #107 is technically mergeable but diverged from current staging; review the exact six-file patch and refresh its base before any merge.
- #104 is a clean seven-commit production-source PR against current main, but remains Draft/HOLD pending production CORS runtime evidence and independent review.
- #106 and #108 are clean, scoped staging PRs. #106 is source/history parity only; #108 is documentation only. Neither is a release authorization.



### RPC ACL migration SQL provenance clarification
- PR #106 preserves the original SQL file body while renaming its migration version to the version recorded in staging history.
- A normalized comparison of the source migration SQL and the exact SQL passed to the staging migration application confirms all executable SQL statements match. The only textual difference is explanatory comment wording; there is no executable-statement difference.
- Live staging ACL aggregate remains 29 public functions, 0 `anon` EXECUTE, 0 `authenticated` EXECUTE, 29 `service_role` EXECUTE, including 5 SECURITY DEFINER functions. This is runtime privilege evidence, not proof that every Edge Function authorization path has passed tenant A/B testing.


### Stock-transfer policy — PRD resolves to strict same-tenant
- The D’Lice PRD defines one tenant per organization (150 branches are not 150 tenants), transfers between warehouses/branches, and the lifecycle Draft → Approved → Picked → Shipped → Received → Reconciled. It requires tenant isolation and cross-tenant denial and does not authorize a Platform Owner/HQ cross-tenant stock-transfer exception.
- The current staging Edge Function's platform-owner cross-tenant approval exception and its old contract test were inconsistent with the PRD. PR #109 removes the exception, enforces same-tenant at API + database layers, and updates the contract test to the PRD.
- Current staging has zero stock-transfer rows and no same-tenant trigger. The SECURITY DEFINER RPC itself does not compare tenant IDs; the database trigger is necessary defense-in-depth even though direct client EXECUTE has been revoked.
- PR #109 uses a forward-only migration timestamp `20261120130000`, a disposable PostgreSQL regression, and API contract tests. Keep it Draft/HOLD until all CI is green, independent review is complete, and the P01–P09 tenant runtime gate is unblocked. Do not apply the migration before these gates.


### Frontend runtime-config completeness
- PR #107 is a useful six-file change for `index.html` and `erp.html`, but it does not update `track.html`.
- Current `staging/track.html` still selects staging/production Supabase project URLs based on `location.hostname`. This remains a hard-coded environment-routing path and is outside PR #107's current smoke coverage.
- `admin.html` currently has no Supabase client/config reference; confirm whether it is an inactive placeholder before including it in scope.
- PR #107 description now records this gap. Do not call runtime configuration complete until `track.html` is migrated and smoke-tested.


## 12. Current repository inventory update — after PR #109
The original historical snapshot covered PR #1–#107 (105 actual PRs; #34 and #45 do not exist). Two audit PRs have since been added:
- #108 — full PR history and overlap inventory: 27 commits, 1 changed file, +497/-0.
- #109 — proposed stock-transfer tenant boundary: 14 commits, 7 changed files, +390/-15.

Current repository totals:
- **107 actual PRs** across the number range #1–#109.
- **75 merged**, **26 closed without merge**, **6 open**.
- **2,195 total PR commits**, **902 PR-level file touches**, **70,541 additions**, **2,076 deletions**. These are per-PR aggregate metrics, not unique files/commits across Git history.

Current open PRs: #71, #104, #106, #107, #108, #109. All are Draft. No PR was merged or closed during this audit.

### PR #109 latest validation
- Dedicated `Stock transfer same-tenant boundary` workflow run `44596628557`: **SUCCESS**. The isolated PostgreSQL test and API contract test passed.
- The corrected PR #109 head `2d1a7249ad5e8e00a164b08af8137b033294c59b` now has all relevant checks SUCCESS: Free quality checks, full disposable migration replay, dedicated API/PostgreSQL same-tenant regression, CORS probes, KDS offline contract, procurement receiving, and procurement requisition contracts.
- Disposable full migration replay run `44596627981` was still in progress at the last check.
- PR #109 remains Draft/HOLD. The API/trigger change must not merge until Product Owner decides the cross-tenant stock-transfer policy and the full migration replay/independent review pass.


- Latest PR #109 evidence at head `2d1a7249ad5e8e00a164b08af8137b033294c59b`: dedicated boundary regression `44599359879` SUCCESS; disposable full migration replay `44599359836` SUCCESS; Free quality checks `44599359868` SUCCESS; CORS, KDS, procurement receiving, and procurement requisition checks SUCCESS. It remains Draft/HOLD pending independent review and P01–P09 runtime gate.


### Scheduled staging mutation workflows on main — latent release blocker
- Main contains two scheduled positive-path workflows: procurement at `02:23 UTC` (09:23 WIB) and KDS/POS/stock at `02:17 UTC` (09:17 WIB).
- Both use the condition `github.event_name == 'schedule' || inputs.confirm_staging_mutations == true`. A scheduled run therefore bypasses the manual `confirm_staging_mutations` input and can write QA-prefixed business records to shared staging if the Environment credentials become available.
- Latest scheduled runs inspected:
  - Procurement `44506173400` (19 Nov) and `44284617369` (18 Nov): failed at the positive E2E script preflight because Owner username/password and Branch A username were missing.
  - KDS/POS/stock `44505286727` (19 Nov): failed at preflight because Owner username/password were missing.
- Logs show these runs stopped before the positive workflow began; no business mutations were executed in those runs.
- **Latent risk:** if those legacy secrets are later populated, the schedules will automatically start writing to staging without a manual confirmation. This conflicts with the current staging mutation gate. Repository administrator should disable the schedules or change them to read-only monitoring until a separately approved, protected QA schedule is designed. Do not add or populate those legacy secrets as a workaround.
- The current `staging` branch version of the KDS workflow has a preflight and QA artifact validation; the main version does not have the same preflight and runs the positive script directly. Main's scheduled workflow is therefore also missing the newer staging safeguards.


### Vercel production deployment and alias verification
- Current latest production deployment: `dpl_6wzdyEyDiyif7KRRWsdhDoRAUH6Q`, state READY, commit `2bb254bfb06baa8a3847b9112552f9413420b9f0` on `main`.
- Deployment alias list confirms `dlice.vercel.app`, `dlice-landing-page-dlice8888-7332.vercel.app`, and `dlice-landing-page-git-main-dlice8888-7332.vercel.app` all point to that deployment.
- This is the production deployment created after PR #96. PR #96 changed only the guarded P01–P09 workflow entrypoint; it did not change app HTML/JS, Edge Function source, Supabase schema, Auth metadata, or business data. The production build/deployment happened, but there is no evidence of a functional app-code change from that PR.
- Previous production deployment `dpl_83d9ZYmZjAVuiifaczxKqegHJ6do` remains READY in deployment history. No rollback or alias reassignment was performed; the current alias mapping is now verified directly from the deployment record.
- Preview deployments are being created for audit branches and Draft PRs, but no production deployment was created by PR #108/#109. No deployment promotion, rollback, or production code change was performed in this audit.


### Current open-PR CI and independent review matrix
Latest head commit checks and submitted reviews inspected after PR #109:

| PR | Latest relevant CI | Independent submitted approval/review | Gate interpretation |
|---:|---|---|---|
| #64 | No qualifying workflow run | None; one self-authored COMMENTED review | Closed without merge; superseded by PR #109 |
| #71 | Migration replay, CORS probes, Free quality, KDS contract, tenant static checks, procurement contracts all SUCCESS | None; one self-authored COMMENTED review | Static/contract only; P01–P09 runtime remains BLOCKED |
| #104 | Verify Superpowers submodule SUCCESS only | None | No production CORS runtime proof |
| #106 | Free quality, KDS contract, disposable migration replay all SUCCESS | None | Source/history parity candidate only |
| #107 | Free quality, CORS probes, procurement contracts all SUCCESS | None | Exact Preview runtime-config smoke not executed; track.html gap remains |
| #108 | Free quality SUCCESS | None | Documentation artifact; independent completeness review still needed |
| #109 | Free quality, full disposable migration replay, SQL/API boundary regression, CORS, KDS, procurement checks SUCCESS | None | Draft/HOLD pending independent review and P01–P09 runtime gate |

No open PR has an independent submitted approval. The repository ruleset currently requires zero approvals and zero named status checks, so these missing reviews are not blocked by the live ruleset.


### Supabase Edge Function source/runtime drift
- Supabase staging `dlice-orders` is ACTIVE at **version 70**, last updated `2026-11-18`, with `verify_jwt=false` and explicit action-level Auth validation inside the handler.
- Its deployed `tenant-permissions.ts` matches the current `staging` branch file exactly. Its deployed `index.ts` does **not** match current `staging` source: deployed 219,189 bytes / 2,251 lines vs GitHub staging 217,003 bytes / 2,271 lines.
- Deployed v70 still uses non-atomic direct Auth/profile bootstrap and direct tenant/membership inserts; current staging source calls `dlice_bootstrap_initial_owner` and `dlice_create_tenant_with_owner`.
- Deployed v70 still computes a legacy global Command Center summary directly from branches/inventory/shifts/sales/expenses/POs; current staging source calls `dlice_get_command_center_summary` with explicit branch IDs and a bounded date range.
- Deployed v70 still performs branch checklist start/item update/completion through separate table writes and separate audit inserts; current staging source calls `dlice_manage_branch_checklist` for atomic mutation + audit and optimistic locking.
- Current staging also validates branch timezone against the supported timezone set; deployed v70 falls back silently to `Asia/Jakarta` for unsupported values.
- The three supporting migrations for the newer code (`20261120100000`, `20261120110000`, `20261120120000`) are not yet applied to staging. This is expected source/runtime drift while release gates are held, but it means the newer bootstrap, Command Center, and atomic checklist features are **not active in the deployed Edge Function** yet.
- Do not deploy the newer function source before the three migrations are reviewed/applied in the correct order and the staging P0 tenant gate passes. No Edge Function deployment was performed in this audit. Both `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false` are still present in deployed v70 and current staging source.


### Vercel staging deployment alignment
- Current Vercel staging deployment `dpl_J3n6BBXyjWNJZvMqzV6C1fZ9RP2M` is READY from branch `staging`, commit `4a13e70ce29e3fe117b6b6e7705089fa4241298a`, with alias `dlice-landing-page-git-staging-dlice8888-7332.vercel.app`.
- The web deployment therefore contains the newer staging source (including the atomic branch checklist client changes), while Supabase `dlice-orders` remains at v70 and does not contain the newer atomic checklist/Command Center/owner bootstrap handlers. This is a cross-service version mismatch, not a Vercel build failure.
- Do not treat the READY Vercel staging deployment as proof that its Supabase-backed features are runtime-ready. Align database migrations and Edge Function version only after P0 tenant runtime evidence and migration review.

- PR #109's previous Free quality failure was caused by the stale platform-owner exception contract. The contract was corrected to the PRD's strict same-tenant rule at commit `29db1c85a34cd40519d961356732b5a7bf948e2c`; rerun CI is in progress.


### PR #71 migration salvage classification
- `platform_bootstrap_tenant_owner` in `20261108090000_atomic_tenant_audit_operations.sql` hard-codes staging Tenant B ID `00000000-0000-4000-8000-000000000002`, QA Branch B ID `90000000-0000-4000-8000-000000000004`, and slug `dlice-qa-isolation-b`. It is a staging-fixture bootstrap helper, not a reusable SaaS tenant-onboarding API; do not promote it to main.
- The generic atomic owner/tenant bootstrap in PR #102 (`dlice_bootstrap_initial_owner`, `dlice_create_tenant_with_owner`) is the preferred production candidate, but its migration and Edge Function source are not yet deployed to staging.
- The other PR #71 RPCs are potentially reusable after independent review: `erp_create_warehouse_with_audit`, `erp_transition_purchase_order_with_audit`, and `erp_create_purchase_order_with_audit`. They are SECURITY INVOKER, service_role-only, tenant-membership scoped, and write audit rows in the same transaction. Review their actor/role checks, PO item validation, idempotency, and rollback behavior before salvaging them into forward-only migrations.
- Keep PR #71 Draft/HOLD; do not merge its old migration timestamp or staging-specific bootstrap helper.


### Release protection audit — active ruleset is not an effective merge gate
- GitHub reports both `main` and `staging` as `protected=true`, and one active repository ruleset exists (`27559290`).
- The ruleset currently has `required_approving_review_count=0`, `required_status_checks=[]`, and `required_deployments.required_deployment_environments=[]`. The `required_reviewers` list is empty.
- `require_code_owner_review=true` is configured, but the repository tree has no `CODEOWNERS` file, so there is no mapped code-owner reviewer set.
- The ruleset allows multiple repository roles and integrations to bypass always; the active connection reports `current_user_can_bypass=always`.
- Existing safeguards do include deletion, non-fast-forward, creation/update restrictions, required linear history, and required signatures. Those do not substitute for independent review, mandatory CI, or staging deployment approval.
- GitHub branch-protection GET is 403 for this integration and no ruleset mutation action is available. Repository administrator must configure at least one independent approval, required general CI checks, code-owner mappings, staging required deployment reviewers, and a minimal break-glass bypass list. Do not claim "protected" means "release-gated" until the actual ruleset configuration is verified.


## 13. Main-only history and salvage map
A commit-set comparison found **20 commits on main not reachable from staging**. They are not a single feature bundle; they include audit docs, guarded E2E entrypoints, schedules, Superpowers governance, and two migrations later intentionally reverted from main.

### Preserve / reconcile
- **Superpowers engineering governance:** main contains `AGENTS.md`, `.gitmodules`, `docs/engineering/superpowers-integration.md`, `tools/superpowers` gitlink pinned to upstream `2ce8aa15d05bd57213e6f746f953aafb7ded7a8b` (v7.0.1), and `verify-superpowers.yml`. These are absent from staging. They encode the requested TDD/review/PR/no-production-without-Owner-approval method and should be preserved in the eventual branch integration. The submodule itself does not activate an agent plugin.
- **E2E evidence harnesses:** main has `tests/staging/kds-pos-stock-positive.mjs` and `tests/staging/procurement-receiving-positive.mjs`; staging has different versions of both. Do not overwrite one with the other. Main KDS harness includes branch checklist start/item/completion E2E but requires a Branch A credential; staging KDS harness adds safer auth-blocked classification and offline replay/idempotency but uses the Owner identity for the business flow. Port the checklist scenario to the new atomic checklist API after the supporting migration/function is deployed; retain branch-manager authorization coverage.
- **Procurement E2E:** staging's script has stronger blocked-auth classification and explicit target validation; main's version has additional result/evidence formatting. Reconcile behavior and preserve the stronger preflight, not a whole-file replacement.
- **PRD matrix:** both main and staging contain the 18-domain / 189-feature `FNB_OS_IMPLEMENTATION_MATRIX.json` snapshot at `2026-11-18T20:05:00+07:00`. The per-feature `audit_status` values are identical across branches; evidence text differs. It is useful historical traceability, not a current completion percentage or runtime proof.
- **Production fixes:** main-only commits `9fdbf413` (atomic recipe activation) and `60471e6a` (deterministic production ingredient lock order) were later reverted from main by `7f6c2ba2` and `56f03f31`. Their migration files exist on staging as `20261020202830` and `20261020202841`; the feature is present in staging source. Do not re-add the old main snapshots or treat these as missing staging features.

### Do not port unchanged
- Main's scheduled positive-path workflows (`staging-kds-pos-stock-positive-e2e.yml` and `staging-procurement-positive-e2e.yml`) bypass `confirm_staging_mutations` for schedule events. The staging KDS workflow also auto-runs on `push`; this bypasses the manual mutation gate. The scheduled runs inspected so far failed preflight, but if legacy credentials are populated these workflows can automatically write QA data. Convert to read-only monitoring or require an explicit protected dispatch before any future positive-path mutation.
- Main's `procurement-requisition-contract.yml` watches stale migration path `20261023170000_purchase_requisitions.sql`; staging's version watches the actual current migration files `20261023160257` and `20261023160440`. Preserve the staging path filters.
- Main's KDS workflow requires legacy `STAGING_TEST_BRANCH_A_*` credentials. The known legacy profile mapping is inconsistent with the actual tenant/branch assignment; do not restore that credential mapping without verifying the account's current membership and branch assignment.
- The two main-only migration revert commits intentionally keep staging-only migrations out of production main. Preserve this boundary; do not merge staging migrations wholesale into main.

### Main-only commit inventory (20)
`2bb254b` guarded P01–P09 dispatch; `11d2609` PR83/migration audit evidence; `85d8899` restore main tree after audit artifact; `4b2c281` migration source recovery docs; `ab47e1b` remove accidental audit artifact; `eddc1cf` staging CORS runtime evidence; `8d74dbd` schedule positive E2E from main; `7d4d68b` PR41 E2E entrypoints; `0dfb8a9` procurement reconciliation evidence; `1d70c77` payment status/cleanup assertions; `aa4b605` procurement workflow entrypoint; `03ad0e4` KDS/POS/stock workflow entrypoint; `bc2d9d0` KDS/POS/stock E2E harness; `79d7b30` requisition lifecycle/generated PO; `8acc74d` procurement harness syntax check; `53631a8` Superpowers integration; `56f03f3` and `7f6c2ba` staging-migration reverts; `60471e6` and `9fdbf41` production recipe/stock migrations later reverted from main.


### Closed-unmerged E2E scenarios worth salvaging — PR #31
PR #31's `tests/staging/next-workflow-acceptance.mjs` is not present at that path in current staging, but contains useful negative and cross-role scenarios not fully represented by the current vertical-slice contracts:
- P2P: Owner/Procurement create and list requisitions/POs; branch manager can receive only assigned-branch PO; cross-branch receive denied; no-permission and inactive users denied; unknown PO ID returns not-found without mutation.
- O2C: branch-scoped fulfillment list; cross-branch fulfillment read/update denied; no-permission/inactive identities denied; unknown order ID returns not-found without mutation.
- Finance: Head Office settlement listing; branch manager cannot create settlement; no-permission/inactive identities denied; cash reconciliation is branch-scoped.
- Stock: unknown transfer/count identifiers must fail closed without changing ledger state.
- The PR's workflow provisions temporary QA users and writes evidence artifacts, but uses legacy Owner/Branch A secrets and a hard-coded old Branch B UUID. Do not merge it unchanged. Port the scenarios into the current dynamic fixture-discovery runner, use the verified A/B branch-manager identities, and preserve no-SKIPPED semantics.
- PR #31 is a test scenario source, not runtime acceptance evidence; it was closed without merge and no qualifying staging run is recorded.

## 14. Live verification addendum — 20 November 2026

This addendum corrects the PR metadata totals and records direct read-only verification from GitHub, Supabase staging, and Vercel. It does not authorize merging, applying migrations, deploying Edge Functions, or changing release flags.

### Corrected PR inventory
- Re-enumerated all actual PRs, including the first seven PRs separately because the repository search result page returns at most 100 records.
- Actual PR count: **107** (PR numbers #1–#109 with gaps; #34 and #45 are not PRs).
- Current disposition: **75 merged**, **26 closed without merge**, **6 open**.
- Sum of the current GitHub PR `commits` metadata: **2,198**. The previous aggregate of 2,195 is stale by 3 because PR #108 currently reports 30 commits, not 27.
- Current open Draft PRs: #71, #104, #106, #107, #108, #109. PR #64 is now closed without merge; its stock-transfer finding is superseded by the narrower #109 candidate.
- No PR was merged or closed as part of this addendum. No code PR was created.

### Direct Supabase staging verification
Project: `higoadrzxnhzbbwhdbmh`.
- Applied migration history: **49** rows.
- Public tables: **64**, with RLS enabled on **64/64**.
- Public functions: **29**; current effective EXECUTE counts: anon **0**, authenticated **0**, service_role **29**.
- The repository staging branch still contains `20261119160000_revoke_default_public_function_execute.sql`, while staging history records the applied version as `20261119182606`. PR #106 is therefore a required source/history reconciliation before the next migration push. Do not reapply the ACL SQL.
- The three unapplied staging-source migrations remain ordered: `20261120100000_atomic_owner_and_tenant_bootstrap.sql`, `20261120110000_command_center_summary.sql`, and `20261120120000_atomic_branch_checklist_audit.sql`. PR #109 adds the later `20261120130000_enforce_same_tenant_stock_transfers.sql`; it is not applied.
- No same-tenant stock-transfer trigger currently exists in shared staging. Current `stock_transfers` row count is zero.
- Read-only membership/assignment checks confirm two distinct branch-manager identities with active memberships and active branch assignments: Tenant A (`dlice-default`) and Tenant B (`dlice-qa-isolation-b`). This does not prove username/password login or authenticated P01–P09 runtime behavior.

### P0 runtime and PR CI evidence
- PR #71 current head has successful static checks, migration replay, CORS, KDS and procurement contract workflows. No P01–P09 runtime workflow run was returned for that head. Treat tenant isolation as **NOT VERIFIED**, not PASS.
- A separate candidate branch `fix/tenant-isolation-discover-fixtures-20261120` is 8 commits ahead and 0 behind `staging`. It removes the six hard-coded fixture UUID Environment variables and derives tenants/branches from authenticated membership and branch responses; it still requires the four canonical Tenant A/B username/password secrets. It is a salvage candidate, not runtime evidence and not yet a PR.
- PR #109 exact head `2d1a7249ad5e8e00a164b08af8137b033294c59b` has seven relevant workflow runs completed SUCCESS: Free quality checks, disposable local Supabase migration replay, same-tenant API/PostgreSQL boundary regression, runtime CORS probes, KDS offline contract, procurement receiving contract, and procurement requisition contract. It remains Draft/HOLD because authenticated P01–P09 and independent review are outstanding.
- No submitted reviews were found on PRs #106, #107, or #109 at this verification point.

### Vercel and Edge Function alignment
- Vercel project `dlice-landing-page` has SSO protection enabled for deployments except custom domains.
- Latest staging deployment is READY at commit `4a13e70ce29e3fe117b6b6e7705089fa4241298a`. Current staging base `39a9c96156b5c0af8b70e689da10cdd9b3b10122` is one commit ahead; the only changed paths in that commit are ten audit documents.
- Latest Production deployment remains READY from `main` commit `2bb254bfb06baa8a3847b9112552f9413420b9f0`. No production deployment, alias change, rollback, or promotion was performed during this audit.
- Supabase staging `dlice-orders` remains ACTIVE at version **70**. No Edge Function deployment was performed. Do not deploy newer staging source until its ordered migrations and P0 runtime acceptance are reviewed and passed.
- PR #107 still does not cover `track.html`, which retains hostname-based Supabase project selection. Its exact Preview runtime-config smoke has not been executed.

### Remaining release-protection findings
- The active GitHub ruleset still does not require an independent approval, mandatory status checks, or a staging deployment reviewer. The current connected actor can bypass the ruleset. `protected=true` is not sufficient evidence of an effective release gate.
- Main contains scheduled positive-path staging workflows whose schedule condition bypasses the manual `confirm_staging_mutations` input. The previously inspected scheduled runs failed preflight before business mutations, but the latent write path remains. Disable those schedules or convert them to read-only monitoring before legacy credentials are populated.
- Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`. Do not merge PR #64/#71/#104/#106/#107/#108/#109, apply the four pending migrations, deploy Edge Functions, or change Production until the relevant independent review and runtime gates pass.

### Immediate sequence
1. Reconcile PR #106's ACL source filename with applied migration history before any future migration push.
2. Selectively port/review the authenticated fixture-discovery runner; populate canonical A/B credentials only through the protected GitHub Environment.
3. Run P01–P09 with two distinct real identities; require all nine probes executed with no BLOCKED or SKIPPED result.
4. Independently review PR #109 and then integrate/apply migrations in forward order: Owner bootstrap, Command Center, atomic checklist, same-tenant stock-transfer guard. Verify each migration separately before deploying the matching Edge Function source.
5. Fix PR #107's `track.html` coverage and execute exact-Preview runtime smoke.
6. Tighten GitHub ruleset and scheduled staging mutation workflows before treating staging as release-gated.

## 15. Follow-up execution checkpoint — 20 November 2026

### ACL migration reconciliation
- PR #106 contains the exact migration SQL under `supabase/migrations/20261119182606_revoke_default_public_function_execute.sql`; the prior `20261119160000_...` filename is absent from the PR head.
- Supabase staging history records version `20261119182606`; the current staging branch still contains the stale `20261119160000_...` filename until PR #106 is integrated.
- PR #106's disposable migration replay, free quality checks, and KDS contract workflow all completed successfully.
- PR #106 was moved from Draft to Ready for Review. It remains open and unmerged. No SQL was replayed or applied.

### Tenant fixture discovery port
- Created PR #110 from `fix/tenant-isolation-discover-fixtures-20261120` to `staging`, with six changed files and 8 commits. It is Ready for Review, open, and mergeable.
- Its Free quality checks completed successfully; Vercel status is success.
- Direct read-only staging inspection confirmed QA branch codes `QA-DLICE-A` and `QA-TENANT-B` are active and belong to different tenants. The two QA identities have distinct user IDs, active `branch_manager` memberships, and `sales_admin` admin profiles. Tenant A has two active branch assignments; the discovery logic permits multiple assignments within the same tenant.
- The four credential values were not read. GitHub Environment secret metadata is not exposed through the available connected actions, and workflow dispatch is not exposed either. Therefore P01–P09 have **not** been run; runtime acceptance remains NOT VERIFIED.
- No credentials were changed, no user passwords were reset, and no test JWTs were generated.

### Migration integration status — source vs shared staging
- PR #102 (Owner bootstrap), #103 (Command Center), and #105 (atomic branch checklist) are already **merged into the GitHub staging branch**. Their disposable migration replay and relevant contract workflows completed successfully.
- Supabase shared staging migration history still has 49 applied rows and does not include those three versions. They remain pending database application; GitHub merge is not equivalent to Supabase apply.
- PR #109 adds the fourth pending migration `20261120130000_enforce_same_tenant_stock_transfers.sql`. Its disposable local migration replay, same-tenant API/PostgreSQL boundary regression, Free quality checks, CORS, KDS, and procurement workflows all completed successfully.
- PR #109 remains Draft, open, mergeable, and has no submitted independent review. No migration was applied to shared staging.

### Code-review notes
- PR #109's SQL trigger rejects cross-tenant stock-transfer INSERT and source/destination UPDATE, and blocks tenant reassignment for branches referenced by transfer history. Its Edge Function checks source/destination tenant equality on create and rechecks tenant equality on every transition, including platform-owner requests. The disposable SQL regression covers valid same-tenant insert, cross-tenant insert, both endpoint updates, branch reassignment, no partial mutation, and client EXECUTE denial.
- Independent security review is still outstanding; static inspection and CI do not replace it.
- PR #102 and #105 service-role-only RPCs use `auth.role()` as a role guard. Supabase currently deprecates `auth.role()`; treat replacement with a JWT role claim check as a follow-up hardening item, after confirming the supported claim contract and testing in disposable replay. Do not alter the already merged migration in place; use a forward-only follow-up migration if needed.
- PR #103 Command Center is called only from the `erp-overview` route, which checks `isOwner` before querying branch IDs and invoking the service-role RPC. Keep this owner-only guard in regression coverage.
- PR #105 checklist writes use server-side branch access checks before calling the service-role atomic RPC; its migration test verifies rollback of checklist state when audit insertion fails.

### Updated execution blockers
1. PR #106 needs independent review and merge to reconcile the migration filename in the GitHub staging branch. Do not replay SQL.
2. PR #110 needs independent review, then trusted staging workflow dispatch after a maintainer verifies the four canonical Tenant A/B username/password Environment secrets. Require P01–P09 all executed, zero BLOCKED/SKIPPED.
3. PR #109 needs independent security review; keep it Draft/HOLD until review and runtime acceptance are complete.
4. Only after P0 runtime acceptance and the relevant reviews may migrations be applied to shared staging, one at a time in order: #102, #103, #105, #109. Verify the database history and postconditions after each apply.
5. Deploy `dlice-orders` only after the matching database migration and API source are both verified. Production remains untouched and both release flags remain false.

## 16. Owner authorization preflight — critical correction

A further read-only Supabase staging check found:
- One active `admin_profiles.role='owner'` row already exists.
- Its referenced Auth user exists.
- The Auth user's `app_metadata` does **not** contain the `platform_owner` key.
- There is one default tenant and one active `tenant_owner` membership.

Consequences:
- Do **not** call `dlice_bootstrap_initial_owner` or the initial-owner Edge Function as a way to create a second owner. Both intentionally reject when an owner profile already exists.
- The existing Owner authorization must be reconciled through the authorized Supabase Auth Admin path: preserve existing app_metadata, set `platform_owner` to boolean `true` only after verifying the account owner, then update the protected `DLICE_PLATFORM_OWNER_USER_IDS` allowlist with that exact existing Auth UUID. Do not expose credentials or metadata values in chat/logs.
- Re-read the resulting metadata/allowlist safely and verify the Owner route before any Owner-only action. This is a human/admin authorization gate; no metadata or environment secret was changed by this audit.
- The Owner bootstrap migration #102 may still be applied as schema code only after P0 gates; its initial-owner action must remain unused for this already-provisioned account.

This supersedes any assumption that staging has no Owner profile. It has an Owner profile, but it is not currently a verified platform Owner.

## 17. PR #109 concurrency hardening — pending CI

- Security review identified a check-then-write race between stock-transfer creation/update and concurrent `branches.tenant_id` reassignment.
- Patched `enforce_stock_transfer_same_tenant()` to lock both referenced branch rows with `FOR SHARE` in deterministic ID order before reading tenant IDs.
- Added disposable PostgreSQL regression assertion that the installed trigger function contains the row-lock guard, and a contract assertion for deterministic lock ordering.
- Updated PR #109 head: `ec01b23bec9c7cc96f3893dbaa9e0b184c97dbfb`.
- A review note was posted on PR #109. CI for the updated head is currently running: disposable migration replay, KDS, quality, procurement receiving, and stock-transfer boundary workflow. Procurement requisition and CORS checks have completed successfully. Do not treat the new head as passing until every relevant run completes successfully.
- PR #109 remains Draft/HOLD with no independent submitted review. No shared staging migration or Edge Function deployment was performed.

## 18. Current continuation audit — 20 November 2026 (supersedes stale counts above)

This section is the current read-only checkpoint. Sections 1–17 are retained as historical evidence and must not be interpreted as current PR totals or current runtime proof.

### Repository and PR checkpoint
- The paginated repository PR listing returned **109 actual pull requests** (not 111; issue-number gaps exist): **75 merged**, **26 closed without merge**, and **8 open**. This is the current count at this checkpoint; older totals in historical sections are superseded.
- Latest PR number observed: **#111**. This does not mean there are 111 PRs; issue-number gaps exist.
- Current relevant open PRs:
  - #71 — legacy staging fixture workflow; remains a runtime-gate predecessor, not proof of tenant isolation.
  - #104 — production CORS contract, Draft.
  - #106 — ACL migration filename/source parity, Ready for Review.
  - #107 — frontend Supabase runtime configuration, open.
  - #108 — this audit artifact, Draft.
  - #109 — same-tenant stock-transfer boundary, Draft.
  - #110 — authenticated tenant fixture discovery, Ready for Review.
  - #111 — OIDC tenant-session broker, Draft and stacked on #110.
- #106, #110, and #109 have technical COMMENTED reviews from the PR author `dlice8888`; these are not independent approvals. #111 has no submitted review.
- #110 latest head observed: `7b0f84de615442b7e41a123537fce31be7b1ed3a`. The latest Free quality-check workflow run completed successfully; its static-check job includes staging release contracts, tenant permission contracts, worker-role boundary, RPC ACL boundary, tenant runtime probe contracts, and authenticated fixture-discovery tests. This is static/contract CI, not an execution of P01–P09 against staging.
- #106's quality checks and disposable migration replay completed successfully. Its separate Vercel status context reported a build-rate-limit failure; distinguish that Preview status from migration/quality CI.
- #109's previously recorded CI suite passed its disposable migration replay, stock-transfer PostgreSQL/API boundary regression, CORS, KDS, and procurement checks. It remains Draft and requires independent review.
- #111 is not ready to integrate: its base is the #110 feature branch, not `staging`; it must be reconciled/rebased after #110 integration and pass a disposable replay before any shared-staging action.

### Latest direct Supabase staging checks
Project: `higoadrzxnhzbbwhdbmh`, status `ACTIVE_HEALTHY`.
- Applied migration history: **49** rows; latest version **20261119182606**.
- Public tables: **64**, RLS enabled on **64/64**.
- Public functions: **29**; effective EXECUTE: `anon=0`, `authenticated=0`, `service_role=29`. ACL expansion found no EXECUTE grant to `PUBLIC`; owner and `service_role` are the observed grantees.
- Active Owner profile rows: **1**. Active tenant memberships: **3** across **3** distinct member identities. Active branches: **5**.
- This does not prove platform Owner authorization: the existing Owner Auth user's `app_metadata.platform_owner` is still absent, and protected `DLICE_PLATFORM_OWNER_USER_IDS` reconciliation has not been completed. Do not create a second Owner.
- Three staging-source migrations remain unapplied: `20261120100000_atomic_owner_and_tenant_bootstrap.sql`, `20261120110000_command_center_summary.sql`, and `20261120120000_atomic_branch_checklist_audit.sql`. #109 adds the fourth candidate `20261120130000_enforce_same_tenant_stock_transfers.sql`. None was applied to shared staging in this checkpoint.
- #106 is a filename/source parity change for already-applied version `20261119182606`; do not replay its SQL.

### Tenant-isolation gate
- P01–P09 have **not** been executed against staging in this checkpoint. The GitHub connector exposes no workflow-dispatch action, and static contract tests do not substitute for runtime probes.
- Required result remains nine executed probes, zero BLOCKED, zero SKIPPED, distinct authenticated A/B identities, own-tenant reads allowed, cross-tenant reads and writes denied.
- The current #110 runner discovers fixtures from authenticated memberships and active branch assignments. A recent test correction accepts an empty authorized inventory response while still rejecting rows from another branch. This avoids falsely treating an empty QA stock ledger as an authorization failure.
- Four canonical A/B username/password values have not been read or changed. No credentials, JWTs, or service-role secrets were exposed.

### Release protection and deployment
- Current connected GitHub actions do not expose a usable branch-protection/ruleset read or mutation operation. Earlier direct attempts reported an empty ruleset result and 403 for branch-protection reads. Therefore independent approval requirements, mandatory checks, and staging deployment reviewers remain **not verified/enforced by current evidence**.
- Vercel SSO deployment protection was previously observed enabled for deployments except custom domains. This is not equivalent to a verified staging required-reviewer gate.
- No production deployment, promotion, rollback, Edge Function deployment, shared-staging migration replay, or release-flag change was performed.
- Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.

### Updated execution order
1. Complete historical PR/migration inventory with per-PR commits, changed-file overlaps, merge state, and migration provenance. Treat old aggregate counts in sections 1 and 14 as stale.
2. Obtain independent review for #106 and #110; verify latest CI and branch comparisons before integration.
3. Run staging P01–P09 through an authorized workflow dispatch after an administrator verifies the two canonical Auth identities and protected Environment configuration.
4. Verify GitHub ruleset/branch protection and staging deployment reviewers through an authorized repository administrator; preserve fail-closed behavior.
5. Independently review #109 before integrating its migration; run disposable replay and concurrency regression again on the exact reviewed head.
6. After #110 integration, retarget/rebase #111 to `staging`, run disposable replay, configure broker Function Secrets through authorized Supabase administration, and validate OIDC sessions before deploying the function.
7. Apply the pending migrations only after P0 gates and independent review, one migration at a time with postcondition checks.
8. Continue PRD domain-by-domain implementation and E2E, negative security, backup/restore, and staged load testing toward 150 branches.


## 19. Full disposition audit — all 26 closed without merge (20 November 2026)

This inventory is specifically intended to prevent loss of required product, security, migration, test, and governance work. A closed PR is not treated as irrelevant. Each item is classified by whether its implementation is present in the current staging source, replaced by a newer forward-only implementation, retained as historical evidence, or still needs follow-up. PR descriptions and file diffs were inspected; exact blob comparisons were used for selected high-risk files. This is not a claim that every historical runtime test was rerun.

| PR | Closed PR subject | Classification | What must be retained / current disposition |
|---:|---|---|---|
| #101 | Restore exact applied FK index migration source | Source recovered in staging | `20261022140302_add_missing_fk_supporting_indexes.sql` exists in current staging. PR is closed without merge; do not replay the already-applied migration. Verify all nine index names against live catalog if this is revisited. |
| #95 | Align tenant isolation roles and E2E config | Superseded / materially carried | Runtime tenant probe and KDS/POS workflow match current staging blob. Procurement workflow is a later blob but current staging now sources URL, public key and Edge URL from Environment secrets and uses canonical Tenant A inputs. The final P03 role model is global `sales_admin` plus tenant membership `branch_manager`; current #110 fixture discovery is the next replacement. |
| #93 | Inline ES module parser | Fix carried semantically | Current staging parser imports `path`, `os`, and `spawnSync` and checks module syntax with Node; do not reapply old patch blindly. |
| #87 | Ordinary worker identity and masked P03 evidence | Superseded by #90 | The original `branch_worker` P03 expectation was replaced by the actual role model. Preserve masking, identity separation, multi-branch semantics, and P03 evidence requirements; #110 further modernizes fixture discovery. |
| #86 | Distinguish branch workers from admin profiles | Superseded by #90 | Branch-worker role migration/API/UI work was consolidated into the later staging migration source `20261119155309_add_branch_worker_profile_role.sql`. Do not replay the stale branch migration `20261118190000`. Verify the final role model before changing live users. |
| #85 | Scope inventory reads to authorized branch | Superseded by #89 | Branch-scoped inventory authorization is in current staging. Preserve authorization-before-query, active membership/branch assignment, branch-specific stock rows, and no global inventory enumeration. |
| #83 | Fail closed on missing tenant probe inputs | Superseded by #91 | Preflight validation and secret indirection were incorporated into later workflow/runtime code. Keep fail-closed configuration checks; do not restore stale UUID fixtures. |
| #82 | Normalize staging evidence whitespace | Documentation-only | No functional feature or migration. Release gates and NO-GO status remain the controlling evidence. |
| #80 | Verified staging execution baseline | Historical evidence | Baseline findings are retained in its PR description and superseded by later direct Supabase/GitHub/Vercel checks and this audit. Do not reuse its old counts or migration history as current. |
| #79 | Enterprise FnB OS integration snapshot | Fully subsumed by current staging history | Its branch compares as 0 commits ahead and 36 behind current staging; the huge snapshot is not a missing integration. Its product/ERP, workflows, migrations and docs are represented in the later staging lineage. No bulk merge. |
| #77 | Atomic branch checklist audit | Replaced by forward-only #105 | Preserve atomic checklist writes + audit in one transaction, branch authorization, optimistic versioning, rollback tests, timezone fail-closed behavior. Use #105 migration version, not the old #77 migration. Still gated from shared staging. |
| #76 | Owner Command Center summary | Replaced by forward-only #103 | Preserve Owner-only API/UI, aggregate scoping and timezone fail-closed checks. Use #103 migration source, not old #76 timestamp. Still gated from shared staging. |
| #74 | Staging snapshot PR | No merge by design | PR attempted to merge the staging branch to main; its head is identical to current staging. Do not promote the staging snapshot wholesale to main/production. |
| #73 | Branch cleanup and audit evidence | Documentation was missing; recovered into this audit branch | Seven historical audit files were restored under `docs/audit/`: branch cleanup execution log, final report, deletion allowlist, branch inventory, branch reconciliation, repository protection audit, and staging migration reconciliation. They carry an explicit 13-Nov historical-snapshot warning. Current counts and protections must be rechecked. |
| #64 | Tenant isolation and stock-transfer boundary | Replaced by forward-only #109 | Preserve unconditional same-tenant stock-transfer rule, cross-tenant insert/update rejection, and no platform-owner bypass under current PRD. Old migration timestamp `20261028120000` is stale and must never be applied. |
| #63 | Production order-function CORS fail-closed | Superseded / still release-gated | Preserve exact-origin allowlist, no wildcard/fallback ACAO, foreign-origin rejection, and the rule that CORS is not authentication. #104 is the current production-source/contract track; no production deployment is authorized by this closure. |
| #62 | Revoke client RPC access to trigger-only functions | Migration carried; ancillary tooling not carried | Migration `20261027140145` is present in staging history/source and ACL results show client EXECUTE revoked. Its optional Superpowers submodule integration (`.gitmodules`, `AGENTS.md`, `tools/superpowers`, verification workflow) is absent from staging; this is not an ERP runtime dependency. Continue using the Owner-approved Superpowers engineering method without importing an unreviewed external submodule as a side effect. |
| #43 | Automate guarded procurement E2E | Duplicate / superseded by #44 | Schedule/workflow intent was moved to #44 on the actual default branch. Positive procurement E2E artifacts and trusted secrets remain separate release gates. |
| #38 | Requisition-to-stock E2E harness | Superseded harness | Harness evolved; current procurement test files exist in staging. Do not treat the old contract run as positive business-flow proof. |
| #31 | Next FnB workflow acceptance gate | Historical acceptance coverage not present as the same executable workflow | Historical run recorded 21 PASS for authorization/negative probes across P2P, O2C, stock and finance. The old workflow/script are absent from current staging and used legacy fixture assumptions. Preserve these test cases as required coverage to port into current fixture-discovery-based E2E; the old 21 PASS is not current runtime proof. |
| #22 | Wire order fulfillment, production and finance workflows | Feature lineage superseded/integrated; runtime acceptance remains open | Its API/UI/migrations cover branch-routed checkout, capacity, fulfillment, receiving, BOM/production, settlement, refunds, cash reconciliation and fiscal controls. Current staging contains the later ERP lineage. Outstanding positive-path, provider-refund, settlement-source and finance E2E remain release gaps. |
| #21 | Staged order fulfillment, production and finance controls | Feature lineage superseded/integrated; runtime acceptance remains open | Preserve schema/RPC controls for receiving-to-stock and production consumption; the earlier PR itself acknowledged API/UI wiring and business E2E gaps later addressed in subsequent staging work. |
| #9 | Reconcile free hardening branch with staging | Fully integrated by content | Historical comparison found 13/14 files byte-identical to staging; the remaining old workflow was superseded by newer quality/release-contract workflow. Do not merge its historical 49 commits. |
| #3 | Indonesian operations UI | Already ancestor/in staging | UI language change is present in staging ancestry; no extra merge required. |
| #2 | Supabase-backed product catalog | Already ancestor/in staging | Catalog/UI/backend/migration work is present in staging ancestry; no extra merge required. |
| #1 | Supabase ordering backend and admin panel | Superseded by staging integration | Its head has no commits absent from the staging integration lineage. No production merge was performed. |

### Critical carry-forward findings from the closed-PR audit

1. **No closed PR should be merged wholesale.** Several are snapshots, superseded versions, or migrations with stale timestamps.
2. **#73's seven governance/audit documents are now preserved in this audit branch** by documentation-only commits: `a5d22ce`, `0e87f33`, `7b7c628`, `20816e3`, `b31d487`, `f68f464`, `02c5bf6`.
3. **#31's 21-PASS authorization suite is historical evidence, not current runtime acceptance.** Its P2P/O2C/stock/finance negative cases must be mapped into the current 189-feature acceptance matrix rather than discarded.
4. **#62's migration is carried; its submodule/tooling is not.** No runtime feature is lost from the ACL migration, but the repository-level Superpowers integration is intentionally not silently imported. The approved engineering method remains applicable.
5. **#95's secret externalization and role correction are represented in current staging**, while #110 replaces its older fixture assumptions. Keep the final role semantics consistent.
6. **#77/#76/#64 are replaced by #105/#103/#109** respectively. Preserve behavior and tests, not old migration versions.
7. **#74 is not permission to merge staging to main.** The production branch remains separately controlled.

### User decision on review policy

The user has explicitly stated that a separate reviewer different from `dlice8888` is not an additional prerequisite for this work if the implementation is technically correct and all required checks pass. Therefore this audit does not create a fictitious independent approval or request a reviewer merely to satisfy an assistant-imposed preference. Any actual GitHub branch rule that is active must still be obeyed; its current status must be verified through repository-admin access. Technical sign-off and GitHub approval records remain distinct.

### Current PR #110 head correction

The latest #110 head after the empty-inventory test clarification is `b53e4ee4ee7511823653cf802e34625056c8049a`. The earlier recorded head `7b0f84d` is stale. At the time of this audit, no workflow run had yet appeared for `b53e4ee`; do not transfer the previous commit's green CI status to this new head.


## 20. Execution update — after closed-PR audit

- PR #106 was technically accepted and **squash-merged to staging** after exact-head Free quality checks, KDS contract tests, and disposable migration replay all passed. Merge commit: `cf15f33379a731c1952ec22b5d12739595a21a93`. The Vercel status on the PR head had failed specifically with the build-rate-limit context; this was not a source/build diagnostic and did not change the SQL. No migration was replayed against shared staging.
- PR #110 latest head is `b53e4ee4ee7511823653cf802e34625056c8049a`. Exact-head Free quality checks passed and Vercel status succeeded. This supersedes the earlier recorded #110 head `7b0f84d`. The CI is static/contract verification only, not P01–P09 runtime evidence.
- PR #110 is technically ready for the runtime gate, but **must not be merged until the protected staging Environment inputs have been verified by an authorized administrator**. The available GitHub connector has no Environment secret/variable inspection or workflow-dispatch action. Do not infer secret validity from secret names existing or from static CI.
- P01–P09 have not run. The workflow should be triggered from `staging` only after an admin confirms the six required credential/configuration inputs without disclosing values. Required outcome: P01–P09 all executed, all expected outcomes pass, no BLOCKED/SKIPPED, and no supplemental negative test fails.
- The seven #73 audit documents have been restored to this branch with a warning that they are historical snapshots dated 13 November 2026. Their old branch counts and protection/migration findings are not current operational evidence.
- User policy update: a separate reviewer is not an extra prerequisite imposed by this audit. Technical acceptance is based on exact-head source review and all relevant checks. Do not fabricate a second identity or an independent approval. Actual repository rules, if any are active, still govern merge operations.
