# D’Lice — PR history, branch and file-overlap inventory

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
- Code-owner review and last-push approval flags are enabled, but no independent approval count is required.
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
- `20261017183537_seed_dlice_catalog`: stored migration-history statement contains literal backslash-n separators while current source uses real line breaks. The three product rows exist with creation timestamps near the migration time and were updated by a later catalog migration; the original seed execution provenance still needs confirmation. Do not re-seed blindly.
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
| #1 | CLOSED—UNMERGED | `main` | `feat/supabase-ordering-backend` | ? | ? | +0/-0 | feat: integrate Supabase ordering backend and admin panel |
| #2 | CLOSED—UNMERGED | `feat/supabase-ordering-backend` | `feat/supabase-product-catalog` | ? | ? | +0/-0 | Draft: Supabase-backed D’Lice product catalog |
| #3 | CLOSED—UNMERGED | `feat/supabase-product-catalog` | `feat/indonesian-operations-ui` | ? | ? | +0/-0 | Gunakan bahasa Indonesia untuk operasional D’Lice |
| #4 | MERGED | `feat/staging-order-receipt-gates` | `feat/free-hardening-optimizations` | ? | ? | +0/-0 | Staging: free hardening, security, and release gates |
| #5 | MERGED | `feat/staging-order-receipt-gates` | `fix/rls-advisor-service-role-policies` | ? | ? | +0/-0 | Staging: lock internal tables to service_role |
| #6 | MERGED | `feat/staging-order-receipt-gates` | `docs/23-item-staging-readiness` | ? | ? | +0/-0 | Docs: track 23-item staging readiness and production blockers |
| #7 | MERGED | `feat/staging-order-receipt-gates` | `test/staging-release-contract-gates` | ? | ? | +0/-0 | Test: add staging order release contract gates |
| #8 | MERGED | `feat/staging-order-receipt-gates` | `main` | ? | ? | +0/-0 | Docs: integrate production-branch PRD updates into staging |
| #9 | CLOSED—UNMERGED | `feat/staging-order-receipt-gates` | `feat/free-hardening-optimizations` | ? | ? | +0/-0 | Integration audit: reconcile free hardening branch with staging |
| #10 | MERGED | `feat/staging-order-receipt-gates` | `fix/staging-payment-proof-signature-validation` | ? | ? | +0/-0 | Fix: validate payment proof file signatures on staging |
| #11 | MERGED | `feat/staging-order-receipt-gates` | `feat/staging-safe-retention-rpc-audit` | ? | ? | +0/-0 | Staging: add safe operational retention and tighten RPC ACLs |
| #12 | MERGED | `feat/staging-order-receipt-gates` | `fix/staging-migration-version-parity` | ? | ? | +0/-0 | Fix staging migration version parity |
| #13 | MERGED | `feat/staging-order-receipt-gates` | `docs/2026-10-21-staging-audit` | ? | ? | +0/-0 | docs: record staging-only implementation audit |
| #14 | MERGED | `feat/staging-order-receipt-gates` | `feat/staging-elegant-responsive-motion` | ? | ? | +0/-0 | feat: elegant responsive D’lice staging experience |
| #15 | MERGED | `feat/staging-order-receipt-gates` | `fix/staging-product-copy-migration-version` | ? | ? | +0/-0 | fix: align catalog migration history with staging |
| #16 | MERGED | `feat/staging-order-receipt-gates` | `feat/staging-multi-branch-erp-foundation` | ? | ? | +0/-0 | feat: add multi-branch POS ERP workspace for staging |
| #17 | MERGED | `feat/staging-order-receipt-gates` | `fix/staging-erp-migration-version` | ? | ? | +0/-0 | fix: align ERP migration history with staging |
| #18 | MERGED | `feat/staging-order-receipt-gates` | `fix/erp-branch-scope-and-role-permissions` | ? | ? | +0/-0 | fix: enforce ERP branch isolation and job-based permissions |
| #19 | MERGED | `feat/staging-order-receipt-gates` | `perf/staging-erp-foreign-key-indexes` | ? | ? | +0/-0 | perf: index ERP foreign-key lookup columns |
| #20 | MERGED | `feat/staging-order-receipt-gates` | `fix/staging-erp-index-migration-version` | ? | ? | +0/-0 | fix: align ERP index migration version with staging |
| #21 | CLOSED—UNMERGED | `feat/staging-order-receipt-gates` | `feat/staging-order-fulfillment-finance-production` | ? | ? | +0/-0 | feat: add staged order fulfillment, production and finance controls |
| #22 | CLOSED—UNMERGED | `feat/staging-order-receipt-gates` | `feat/staging-erp-workflows-api` | ? | ? | +0/-0 | feat: wire order fulfillment, production and finance workflows |
| #23 | MERGED | `feat/staging-erp-workflows-api` | `feat/staging-ux-cx-final-reconcile-20261021` | ? | ? | +0/-0 | feat: reconcile staging responsive UX and motion |
| #24 | MERGED | `feat/staging-ux-cx-final-reconcile-20261021` | `fix/staging-security-timezone-20261021` | ? | ? | +0/-0 | fix: harden staging CORS and branch timezone handling |
| #25 | MERGED | `fix/staging-security-timezone-20261021` | `feat/fnb-os-staging-implementation-20261021` | ? | ? | +0/-0 | docs: audit FnB OS staging capability and track implementation |
| #26 | MERGED | `feat/fnb-os-staging-implementation-20261021` | `feat/fnb-os-branch-ops-checklists-20261022` | ? | ? | +0/-0 | feat: add branch opening and closing checklists |
| #27 | MERGED | `feat/fnb-os-branch-ops-checklists-20261022` | `feat/p1-stock-transfer-count-20261022` | ? | ? | +0/-0 | P1: Add branch stock transfer and cycle count workflows |
| #28 | MERGED | `feat/p1-stock-transfer-count-20261022` | `feat/p0-cors-origin-hardening-20261022` | ? | ? | +0/-0 | P0: Harden CORS responses for staging origin allowlist |
| #29 | MERGED | `main` | `chore/integrate-superpowers` | ? | ? | +0/-0 | chore: pin Superpowers submodule and engineering workflow |
| #30 | MERGED | `staging` | `feat/p1-stock-transfer-count-20261022` | ? | ? | +0/-0 | feat(staging): integrate P0 security and P1 stock workflows |
| #31 | CLOSED—UNMERGED | `staging` | `feat/staging-next-workflow-acceptance-20261023` | ? | ? | +0/-0 | test(staging): add next FnB OS workflow acceptance gate |
| #32 | MERGED | `staging` | `fix/staging-cors-secret-only-20261023` | ? | ? | +0/-0 | fix(staging): make CORS depend only on exact origin secret |
| #33 | MERGED | `staging` | `docs/fnb-os-prd-traceability-superpowers-20261023` | ? | ? | +0/-0 | docs: map all 18 FnB OS domains to verified staging evidence |
| #35 | MERGED | `staging` | `fix/staging-procurement-receipt-item-ids-20261023` | ? | ? | +0/-0 | fix(staging): restore PO receiving line IDs and add positive E2E gate |
| #36 | MERGED | `staging` | `feat/staging-purchase-requisitions-20261023` | ? | ? | +0/-0 | feat(staging): add purchase requisition workflow |
| #37 | MERGED | `staging` | `ci/staging-cors-runtime-gate-20261023` | ? | ? | +0/-0 | ci(staging): gate Edge Function changes on runtime CORS |
| #38 | CLOSED—UNMERGED | `staging` | `test/staging-purchase-requisition-e2e-contract` | ? | ? | +0/-0 | test(staging): verify requisition-to-stock E2E harness |
| #39 | MERGED | `staging` | `test/staging-procurement-e2e-contract-v2` | ? | ? | +0/-0 | test(staging): verify updated requisition-to-stock harness |
| #40 | MERGED | `staging` | `feat/staging-kds-offline-tenant-20261024` | ? | ? | +0/-0 | [DRAFT] Kitchen/KDS, offline POS and SaaS branch platform foundation |
| #41 | MERGED | `main` | `chore/default-branch-staging-e2e-entrypoints` | ? | ? | +0/-0 | Expose guarded staging E2E workflows on the default branch |
| #42 | MERGED | `staging` | `fix/staging-explicit-deny-policies-20261025` | ? | ? | +0/-0 | [DRAFT] P0: make server-only table denial explicit |
| #43 | CLOSED—UNMERGED | `staging` | `ci/staging-e2e-auto-schedule-20261025` | ? | ? | +0/-0 | ci: automate guarded staging procurement E2E |
| #44 | MERGED | `main` | `fix/staging-e2e-schedule-main-20261025` | ? | ? | +0/-0 | ci: run guarded staging E2E schedules from main |
| #46 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `feat/staging-pos-kds-stock-reconciliation-owner-e2e` | ? | ? | +0/-0 | test(staging): unblock POS to KDS to stock E2E without Branch A login |
| #47 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/kds-e2e-owner-auth-contract` | ? | ? | +0/-0 | test(staging): align KDS E2E contract with Owner-only auth |
| #48 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/auto-run-staging-pos-kds-e2e` | ? | ? | +0/-0 | ci(staging): remove manual dispatch gate for POS/KDS/stock E2E |
| #49 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/staging-owner-profile-e2e` | ? | ? | +0/-0 | fix(staging): restore Owner operational profile for POS E2E |
| #50 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/owner-only-pos-e2e-scope` | ? | ? | +0/-0 | test(staging): scope positive E2E to POS/KDS/stock/report vertical slice |
| #51 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/pos-idempotency-digest-schema` | ? | ? | +0/-0 | fix(db): qualify pgcrypto digest in POS idempotency |
| #52 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `fix/qa-recipe-repeatable-e2e` | ? | ? | +0/-0 | test(staging): keep QA recipe reusable between E2E runs |
| #53 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `test/strict-pos-kds-stock-report-slice-v2` | ? | ? | +0/-0 | test(staging): isolate required POS to report acceptance slice |
| #54 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `test/contracts-match-vertical-slice` | ? | ? | +0/-0 | test(contract): align staging E2E contract with automated vertical slice |
| #55 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `chore/align-applied-migration-version` | ? | ? | +0/-0 | chore(db): align migration file with applied staging version |
| #56 | MERGED | `feat/staging-kds-offline-tenant-20261024` | `ci/trigger-staging-pos-e2e-on-push` | ? | ? | +0/-0 | ci(staging): run POS/KDS E2E after staging branch updates |
| #57 | MERGED | `staging` | `fix/staging-owner-preflight-wording` | ? | ? | +0/-0 | fix(staging): clarify Owner credential preflight |
| #58 | MERGED | `staging` | `fix/refund-tenant-scope-guard-20261027` | ? | ? | +0/-0 | fix(security): fail closed for unscoped refund processing |
| #59 | MERGED | `staging` | `fix/staging-migration-history-align-20261027` | ? | ? | +0/-0 | chore(staging): align deny-policy migration history |
| #60 | MERGED | `staging` | `audit/staging-migration-drift-denial-evidence-20261027` | ? | ? | +0/-0 | docs(staging): migration drift and denied-access no-mutation evidence |
| #61 | MERGED | `staging` | `audit/migration-reconciliation-runtime-tests-20261027` | ? | ? | +0/-0 | audit(staging): reconcile migration provenance and add runtime deny probes |
| #62 | CLOSED—UNMERGED | `staging` | `security/revoke-trigger-rpc-execute-20261027` | ? | ? | +0/-0 | Security: revoke client RPC access to trigger-only functions |
| #63 | CLOSED—UNMERGED | `main` | `security/production-cors-fail-closed-20261027` | ? | ? | +0/-0 | Security: fail closed on production order-function CORS |
| #64 | OPEN | `staging` | `audit/tenant-isolation-inventory-20261028` | ? | ? | +0/-0 | docs(security): staging tenant isolation audit and release gates |
| #65 | MERGED | `staging` | `fix/staff-password-minimum-8-20261029` | ? | ? | +0/-0 | fix(auth): set staff password minimum to 8 characters |
| #66 | MERGED | `staging` | `fix/staging-public-p0-independent-20261030` | ? | ? | +0/-0 | test: run public staging P0 checks independently of Owner login |
| #67 | MERGED | `staging` | `staging-acl-source-sync-20261102` | ? | ? | +0/-0 | chore(db): sync applied staging ACL migration source |
| #68 | MERGED | `staging` | `staging-runtime-tenant-gate-20261102` | ? | ? | +0/-0 | ci(security): stage trusted two-tenant runtime isolation gate |
| #69 | MERGED | `staging` | `fix-staging-tenant-secret-map-20261102` | ? | ? | +0/-0 | fix(ci): align runtime gate with current staging tenant secrets |
| #70 | MERGED | `staging` | `fix-staging-tenant-auth-fallback-20261102` | ? | ? | +0/-0 | fix(ci): support per-tenant staging login and JWT fallback |
| #71 | OPEN | `staging` | `fix/staging-tenant-fixtures-20261103` | ? | ? | +0/-0 | ci(security): externalize and validate staging tenant fixtures |
| #72 | MERGED | `staging` | `audit/staging-completion-20261113` | ? | ? | +0/-0 | security(ci): restrict staging auth probes to trusted pushes |
| #73 | CLOSED—UNMERGED | `main` | `audit/branch-cleanup-20261113` | ? | ? | +0/-0 | Audit/branch cleanup 20261113 |
| #74 | CLOSED—UNMERGED | `main` | `staging` | ? | ? | +0/-0 | Staging |
| #75 | MERGED | `staging` | `fix/tenant-scoped-permissions-qa` | ? | ? | +0/-0 | fix(authz): resolve tenant-scoped permissions and staging isolation probes |
| #76 | CLOSED—UNMERGED | `staging` | `feat/erp-command-center-foundation` | ? | ? | +0/-0 | feat(erp): add owner command-center summary |
| #77 | CLOSED—UNMERGED | `staging` | `fix/branch-checklist-audit-atomicity-20261114` | ? | ? | +0/-0 | fix(branch-ops): make checklist audits atomic |
| #78 | MERGED | `staging` | `fix/atomic-tenant-bootstrap-staging-20261114` | ? | ? | +0/-0 | fix(authz): bootstrap tenant membership atomically |
| #79 | CLOSED—UNMERGED | `main` | `feat/enterprise-fnb-os-integration` | ? | ? | +0/-0 | Feat/enterprise fnb os integration |
| #80 | CLOSED—UNMERGED | `staging` | `docs/staging-execution-baseline-20261117` | ? | ? | +0/-0 | docs(release): record verified staging execution baseline |
| #81 | MERGED | `staging` | `fix/staging-tenant-negative-probes-canonical-fixtures-20261118` | ? | ? | +0/-0 | fix(staging): align tenant negative probes with canonical fixtures |
| #82 | CLOSED—UNMERGED | `staging` | `docs/reconcile-tenant-evidence-20261118` | ? | ? | +0/-0 | docs(release): normalize staging evidence whitespace |
| #83 | CLOSED—UNMERGED | `staging` | `fix/p0-tenant-isolation-preflight-20261118` | ? | ? | +0/-0 | fix(security): fail closed on missing tenant probe inputs |
| #84 | MERGED | `staging` | `audit/fnb-os-continuation-20261118` | ? | ? | +0/-0 | docs(audit): reconcile FnB OS implementation and release evidence |
| #85 | CLOSED—UNMERGED | `staging` | `fix/tenant-scoped-inventory-read-20261118` | ? | ? | +0/-0 | fix(security): scope inventory reads to authorized branch |
| #86 | CLOSED—UNMERGED | `staging` | `fix/tenant-worker-profile-role-20261118` | ? | ? | +0/-0 | fix(authz): distinguish branch workers from admin profiles |
| #87 | CLOSED—UNMERGED | `staging` | `test/tenant-p03-worker-identity-evidence-20261118` | ? | ? | +0/-0 | test(security): verify ordinary worker identity and masked P03 evidence |
| #88 | MERGED | `staging` | `fix/recover-migration-source-20261022140302-20261118` | ? | ? | +0/-0 | fix(db): restore missing applied migration source |
| #89 | MERGED | `staging` | `fix/staging-tenant-probe-scope-20261118` | ? | ? | +0/-0 | Fix staging tenant-isolation probe scope |
| #90 | MERGED | `staging` | `feat/staging-worker-identity-acceptance-20261118` | ? | ? | +0/-0 | Add ordinary worker identity and P03 tenant acceptance |
| #91 | MERGED | `staging` | `fix/staging-auth-negative-preflight-20261118` | ? | ? | +0/-0 | Fix authenticated staging negative-probe preflight |
| #92 | MERGED | `staging` | `fix/kds-staging-env-secret-scope-20261118` | ? | ? | +0/-0 | Use staging Environment secrets in KDS/POS/Stock E2E |
| #93 | CLOSED—UNMERGED | `staging` | `fix/staging-module-inline-contract-20261118` | ? | ? | +0/-0 | fix(ci): validate inline ES modules without rejecting top-level await |
| #94 | MERGED | `staging` | `security/staging-stock-workflow-rpc-acl-20261118` | ? | ? | +0/-0 | fix(security): revoke public execute on stock workflow RPCs |
| #95 | CLOSED—UNMERGED | `staging` | `fix/staging-tenant-p03-role-and-env-reconciliation-20261119` | ? | ? | +0/-0 | fix(staging): align tenant isolation roles and E2E config |
| #96 | MERGED | `main` | `fix/enable-staging-tenant-isolation-dispatch-main-20261119` | ? | ? | +0/-0 | ci(staging): enable P01-P09 manual dispatch from main |
| #97 | MERGED | `staging` | `reconcile/staging-ci-and-tenant-fixtures-20261119` | ? | ? | +0/-0 | fix(staging): reconcile CI parser and tenant E2E fixtures |
| #98 | MERGED | `staging` | `chore/reconcile-applied-branch-worker-migration-20261119` | ? | ? | +0/-0 | chore(db): reconcile applied branch worker migration source |
| #99 | MERGED | `staging` | `security/revoke-default-public-function-execute-20261119` | ? | ? | +0/-0 | security(db): revoke default client EXECUTE on future public RPCs |
| #100 | MERGED | `staging` | `reconcile/staging-ci-and-tenant-fixtures-20261119` | ? | ? | +0/-0 | fix(staging): consolidate validated tenant and CI contract fixes |
| #101 | CLOSED—UNMERGED | `staging` | `reconcile/recovered-migration-source-20261022140302-20261120` | ? | ? | +0/-0 | fix(db): restore exact applied FK index migration source |
| #102 | MERGED | `staging` | `fix/migration-order-owner-bootstrap-20261120` | ? | ? | +0/-0 | fix(db): preserve monotonic staging migration order for Owner bootstrap |
| #103 | MERGED | `staging` | `feat/command-center-summary-staging-20261120` | ? | ? | +0/-0 | feat(erp): add Owner Command Center summary |
| #104 | OPEN | `main` | `security/production-cors-contract-main-20261120` | ? | ? | +0/-0 | security(cors): track production Edge Function source and fail-closed contract |
| #105 | MERGED | `staging` | `feat/branch-ops-atomic-checklist-staging-20261120` | ? | ? | +0/-0 | feat(branch-ops): make branch checklist mutations atomic |
| #106 | OPEN | `staging` | `reconcile/migration-version-rpc-acl-20261120` | ? | ? | +0/-0 | fix(db): align RPC ACL migration source with staging history |
| #107 | OPEN | `staging` | `feat/staging-runtime-config-smoke-20261118` | ? | ? | +0/-0 | feat(frontend): use environment-validated Supabase runtime config |


### Audit artifact provenance
This document records the 105-PR / 104-branch snapshot taken immediately before this audit document was submitted. The documentation PR that carries this file is excluded from that historical count to avoid self-reference.

### CI state at snapshot
- PR #106 latest head `c256de028f1728bcc00255718a66c9f84307721f`: Free quality checks, KDS contract and disposable migration replay all PASS. It remains Draft and requires independent review.
- PR #107 latest Preview CORS probes and Procurement receiving contract PASS; Free quality and requisition contract checks were still running. Runtime-config smoke against the exact Preview URL has not yet been executed.
