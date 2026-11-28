# D’Lice FnB OS — Full PR History, Merge Dependency and Staging Reconciliation
**Audit timestamp:** 2026-11-28 (WIB)  
**Repository:** `dlice8888/dlice-landing-page`  
**Staging Supabase project:** `higoadrzxnhzbbwhdbmh`  
**Scope:** first actual PR through latest PR, current merge candidates, source migration lineage, staging schema and release blockers.

## 1. Repository-wide PR totals

GitHub search across the repository returns **151 actual pull requests** (PR numbers 1–153; #34 and #52 are absent):

| Current disposition | Count |
|---|---:|
| Merged | 92 |
| Closed without merge | 32 |
| Open | 27 |
| **Actual PRs** | **151** |

The historical PR #108 audit covered 105 actual PRs through #107 (75 merged, 25 closed-unmerged, 5 open). The current inventory adds 46 actual PRs #108–#153, yielding the counts above. The PR count is a repository-history count, not a feature-completion metric.

## 2. All currently open PRs — disposition and next action

| PR | Base | Current scope | Audit disposition |
|---:|---|---|---|
| #71 | staging | Tenant fixture validation | Stale; compare against #110/#130/#132 dynamic fixture work before retaining; no merge as-is |
| #104 | main | Production dlice-orders CORS source parity | Separate production-only source-control gate; never merge to staging or deploy production as part of this task |
| #107 | staging | Environment-validated frontend Supabase runtime config | Stale candidate; compare exact blobs with current staging before any merge |
| #108 | staging | Historical PR/file-overlap audit | Superseded by this 28-Nov full inventory; close after retaining historical artifacts |
| #109 | staging | Same-tenant stock-transfer boundary | Superseded by merged #138; close as redundant |
| #111 | staging | OIDC tenant session broker | Keep as separate candidate until secret/broker and two-session runtime evidence exists |
| #112 | staging | Owner metadata boolean / service RPC hardening | Superseded by merged #138; close as redundant |
| #113 | main | Remove scheduled staging mutation bypass | Main-branch governance work; retain separate from staging feature integration |
| #114 | staging | Carry forward PR #31 cross-module tenant acceptance cases | Keep; static tests passed historically, but runtime A/B execution remains required |
| #115 | main | staging → main promotion PR | Do not merge wholesale; staging-to-main promotion is not an approved production release path |
| #116 | main | Backup/OIDC stacked branch | Stale/conflicting; superseded by #111 and #148 recovery work; do not merge |
| #117 | main | OIDC broker rebase branch | Stale/conflicting; consolidate into #111 only after runtime proof |
| #118 | staging | Explicit confirmation for staging mutation workflows | Retain as a release-governance gate; verify it is present in current staging source before closing |
| #119 | main | Disable automatic staging mutations and policy audit | Main governance branch; do not use as a staging feature merge |
| #123 | staging | Online checkout idempotency | Relevant, but merge conflict and exact-head replay required; rebase/resolve before merge |
| #127 | staging | Atomic payment-proof submission and retry safety | Relevant; includes superseded #125 work; resolve merge conflicts and rerun payment/receipt tests |
| #143 | staging | POS split tender, hold/resume, immutable receipts | POS disposable replay passed on its historical head; staging E2E was blocked by Owner Auth preflight. Current read-only Auth query still finds zero boolean `platform_owner=true` users, so do not rerun mutation path yet |
| #144 | staging | Eight-domain workflow kernel | Its historical quality run failed the ERP action authorization coverage contract. Treat #145/#152's tested descendant as the consolidation candidate; do not merge stale head separately |
| #145 | #144 head | Eight-domain transactional orchestration | Quality CI passed; initial CRM replay failed on CRM SQL syntax later corrected by #151 and carried in #152. Merge only through tested #152 descendant |
| #146 | #145 base | Xendit Payout v3 payroll adapter | Conflicted candidate; provider E2E and payout reconciliation still required |
| #147 | staging | 189-feature evidence matrix refresh | Keep as audit source only after refreshing it from this snapshot; no unsupported score promotion |
| #148 | staging | Disposable PostgreSQL 17 backup/restore drill | Keep; execute and retain restore evidence before staging release acceptance |
| #149 | staging | 150-branch tenant isolation concurrency probe | Keep; execute with 150 real/planned fixtures only where provisioned, and distinguish planned from active branches |
| #150 | #145 base | Food safety, recall and supplier CAPA workflows | Conflicted; rebase and run domain pgTAP + workflow/E2E before merge |
| #151 | #145 base | CRM financial-close SQL syntax correction | Superseded by the byte-identical corrected CRM draft already present in #152 |
| #152 | #145 head | Eight-domain official migrations and ACL hardening | Quality + full disposable replay passed on head `3dda8d1c6dce3b0a68d4ce95afaae059af3101a0`; retarget to staging only after dependency review and rerun exact-head checks |
| #153 | #152 head | 39 PRD gaps, Branch Operations persistence and integrations | CLI-generated Branch Operations migration is committed to this candidate branch; parent-head quality and full CRM/HR/eight-domain/BranchOps disposable suites passed. Latest workflow-only correction still requires exact-head rerun before merge |

### Required dependency chain

```
staging
  └─ PR #144 workflow kernel
       └─ PR #145 eight-domain orchestration
            └─ PR #152 eight-domain migrations + ACL
                 └─ PR #153 Branch Operations persistence + adapters
```

PR #151's CRM SQL syntax correction is already carried into #152 (the corrected draft file has the same blob SHA on #151 and #152). PR #146 and #150 are sibling candidates based on #145 and are not silently included in #152. PR #143, #123 and #127 are independent staging candidates requiring their own conflict resolution and acceptance.

## 3. Closed-unmerged PRs — complete disposition

The 32 closed-unmerged PR numbers are:

`#1 #2 #3 #9 #21 #22 #31 #38 #43 #62 #63 #64 #73 #74 #76 #77 #79 #80 #82 #83 #85 #86 #87 #93 #95 #101 #122 #124 #125 #126 #139 #140`

Disposition:
- **Already represented in staging ancestry or later merged work:** #1–#3, #9, #21–#22, #38, #62, #73, #80, #82, #83, #85–#87, #93, #95, #101.
- **Superseded by a later accepted implementation:** #43 by guarded schedule/policy work (#113/#119); #64/#109 by #138; #76 by #103; #77 by #105; #122 by rebased #136; #124 by #120; #125 by #127; #126 by later dynamic-fixture and tenant membership work (#128/#130/#132); #139 by #138; #140 by #142.
- **Do not mass-merge:** #74 broad staging snapshot and #79 enterprise snapshot. Both are historical aggregation branches, not safe integration units.
- **Unique acceptance scenarios retained:** #31's historical 21 PASS scenarios are not current runtime proof. A safe subset is carried in #114; remaining Owner-positive, no-permission, inactive-account and two-tenant execution evidence remains required.
- **Production source carry-forward:** #63 is still represented by open #104 against `main`; this is separate from staging and must not be treated as completed production parity.

The earlier row-by-row rationale remains in `docs/audit/CLOSED_UNMERGED_PR_CARRY_FORWARD_20261120.md` and `docs/audit/PR_HISTORY_AND_FILE_OVERLAP_20261120.md`; those documents are historical snapshots and must not override this 28-Nov live inventory.

## 4. Staging database — read-only snapshot

Project `higoadrzxnhzbbwhdbmh`:

| Evidence | Observed result |
|---|---:|
| Applied migration history | 63 versions |
| Latest applied version | `20261124134222_pos_checkout_fk_supporting_indexes` |
| Public tables with RLS enabled | 68 / 68 |
| Branch rows | 155 |
| Active branches | 5 |
| Planned/pending branches | 150 |
| Auth users with `app_metadata.platform_owner` boolean true | **0** |

The following required domain tables were not found in the current staging catalog at this audit: `bi_metric_definitions`, `branch_ops_compliance_checks`, `branch_ops_compliance_snapshots`, `branch_ops_equipment`, `branch_ops_evidence_assets`, `branch_ops_incidents`, `branch_ops_tasks`, `branch_ops_work_orders`, `crm_customers`, `delivery_fulfillment_events`, `franchise_applications`, `hr_payroll_runs`, `procurement_supplier_links`, and `saas_plan_versions`.

The eight-domain migration set and the Branch Operations migration are candidate source changes and are not in the current 63-row staging migration ledger. The Branch Operations private evidence bucket is also not yet present in staging.

### Owner / runtime gate

A read-only query of `auth.users.raw_app_meta_data` returned zero users whose `platform_owner` value is JSON boolean true. This contradicts the earlier report that Owner Auth had been repaired. The Supabase connection available for this audit does not expose an official Auth Admin metadata update or Edge Function secret-read action; do not mutate Auth metadata with SQL and do not guess the protected allowlist value. POS mutation E2E and Owner drill-down remain blocked until the existing Owner account and `DLICE_PLATFORM_OWNER_USER_IDS` allowlist are independently verified through the official admin path.

### Advisor / platform gates

- Supabase Security Advisor still reports leaked-password protection disabled (WARN). Application-layer Pwned Passwords checks do not replace the native Auth control.
- Vercel Preview is currently blocked by the Free build/deployment quota; no latest-head Preview runtime evidence exists.
- 150 planned branches are not 150 operationally active branches or evidence of 150-branch transaction throughput.
- Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.

## 5. Exact-head validation evidence and current candidate

- PR #152 head `3dda8d1c6dce3b0a68d4ce95afaae059af3101a0`: Free quality checks PASS and full CRM/HR/eight-domain disposable migration + pgTAP suite PASS.
- PR #153 parent head `cd16892ba129c15293956e7597f3673065a102e0`: Free quality checks PASS; full CRM/HR/eight-domain disposable suite PASS; Branch Operations CLI-generated migration + complete migration replay + 92 pgTAP assertions PASS; disposable stack stopped and discarded.
- The CLI-generated migration file was committed as `supabase/migrations/20261128024514_branch_operations_persistence.sql`, byte-identical to the reviewed draft (artifact SHA-256 `b83b477f44ae5581a8bf018422024d2f6189c77b015c9093887818379a1519ba`).
- A later workflow-only commit removes duplicate migration generation after the official migration was committed. The first rerun after that change has not yet completed; require fresh exact-head quality, CRM replay and Branch Operations replay before merge.
- No shared staging migration, Edge Function deployment, business data mutation, production change or release flag change has occurred in this audit.

## 6. Merge, migration and staging acceptance order

1. Finish exact-head CI and disposable replay on PR #153 after the workflow-only fix.
2. Reconcile PR #152/#153 dependency chain, retarget the tested top-level migration candidate to `staging`, and merge only with exact expected head SHA.
3. Merge the Branch Operations candidate after its own exact-head test suite is green; do not merge #144/#145/#151 separately if their accepted content is included in the tested descendant.
4. Apply the eight-domain migrations and Branch Operations migration to **staging only**, in source dependency order, one at a time; record the actual Supabase-generated versions and reconcile repository filenames to the live migration ledger.
5. Re-run Security and Performance Advisors; inspect new RLS/ACL/Storage policies, function EXECUTE grants, immutable triggers, and service-role-only boundaries.
6. Verify staging schema and all 17 CRM tables, HR payroll, Delivery, Franchise, Procurement, BI, SaaS and Executive tables/RPCs, plus seven Branch Operations tables and private Storage bucket.
7. Run tenant A/B own-read/write and cross-tenant read/write denial, branch isolation, Storage and background-job probes. Require zero BLOCKED/SKIPPED and verify postconditions.
8. Re-run POS staging E2E only after Owner Auth boolean claim and protected allowlist are verified. Reconcile sale totals, tender allocations, cash drawer, stock movements, KDS tickets, immutable receipt and audit events.
9. Run Delivery and Payroll provider E2E (including signed webhook/idempotency, payout items, settlement and bank reconciliation); no provider success is inferred from adapter contracts.
10. Run Owner Command Center company → region → branch → shift → transaction drill-down; reconcile POS/Finance/Inventory/Delivery/HR/KDS totals and freshness.
11. Execute backup/restore drill and 150-branch concurrency/tenant-isolation probes. Keep planned branch count distinct from active operational acceptance.
12. Only after every gate passes and all reconciliations balance may release flags be considered; no production deployment is authorized by this staging audit.

**Decision:** candidate implementation and disposable database proof have advanced, but shared staging migration/merge and operational acceptance remain gated by the latest exact-head rerun, dependency/PR disposition, and the verified Owner Auth/allowlist blocker. No production action is authorized.
