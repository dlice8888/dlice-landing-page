# D’Lice FnB OS — Full PR History, Merge Dependency and Staging Reconciliation
**Audit timestamp:** 2026-11-28 (WIB)  
**Repository:** `dlice8888/dlice-landing-page`  
**Staging Supabase project:** `higoadrzxnhzbbwhdbmh`  
**Scope:** first actual PR through latest PR, current merge candidates, source migration lineage, staging schema and release blockers.

## 1. Repository-wide PR totals

GitHub search across the repository returns **152 actual pull requests** (PR numbers 1–154; #34 and #45 are absent):

| Current disposition | Count |
|---|---:|
| Merged | 94 |
| Closed without merge | 38 |
| Open | 20 |
| **Actual PRs** | **152** |

The historical PR #108 audit covered 105 actual PRs through #107 (75 merged, 25 closed-unmerged, 5 open). The current inventory adds 47 actual PRs #108–#154, yielding 152 actual PRs overall. PR #52 exists and is merged; the two missing numbers are #34 and #45. The PR count is a repository-history count, not a feature-completion metric.

Merged PR numbers (94): `#4 #5 #6 #7 #8 #10–#20 #23–#30 #32 #33 #35–#37 #39–#44 #46–#70 #72 #75 #78 #81 #84 #88–#92 #94 #96–#100 #102 #103 #105 #106 #110 #120 #121 #128–#138 #141 #142 #153 #154`.

## 2. All currently open PRs — disposition and next action

| PR | Base | Current scope | Audit disposition |
|---:|---|---|---|
| #71 | staging | Tenant fixture validation | Stale; compare against #110/#130/#132 dynamic fixture work before retaining; no merge as-is |
| #104 | main | Production dlice-orders CORS source parity | Separate production-only source-control gate; never merge to staging or deploy production as part of this task |
| #107 | staging | Environment-validated frontend Supabase runtime config | Stale candidate; compare exact blobs with current staging before any merge |
| #108 | staging | Historical PR/file-overlap audit | Retain as the source for the detailed 20-Nov row-by-row historical archive; do not merge wholesale until its archive is copied/preserved in staging docs |
| #111 | staging | OIDC tenant session broker | Keep as separate candidate until secret/broker and two-session runtime evidence exists |
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
| #146 | #145 base | Xendit Payout v3 payroll adapter | Conflicted candidate; provider E2E and payout reconciliation still required |
| #147 | staging | 189-feature evidence matrix refresh | Keep as audit source only after refreshing it from this snapshot; no unsupported score promotion |
| #148 | staging | Disposable PostgreSQL 17 backup/restore drill | Keep; execute and retain restore evidence before staging release acceptance |
| #149 | staging | 150-branch tenant isolation concurrency probe | Keep; execute with 150 real/planned fixtures only where provisioned, and distinguish planned from active branches |
| #150 | #145 base | Food safety, recall and supplier CAPA workflows | Conflicted; rebase and run domain pgTAP + workflow/E2E before merge |

### Required dependency chain

```
staging
  └─ PR #144 workflow kernel
       └─ PR #145 eight-domain orchestration
            └─ PR #152 eight-domain migrations + ACL
                 └─ PR #153 Branch Operations persistence + adapters (merged)
                      └─ PR #154 migration filename ↔ ledger parity (pending)
```

PR #153 is merged (commit `2f661ee30f95f09f6d32f0f749189f7ae95ed433`) and carries the accepted #144 → #145 → #152 dependency chain, including #151's CRM SQL correction. PR #144/#145/#151/#152 and #109/#112 have been closed as superseded; their accepted changes are represented by #138/#153. PR #146 and #150 are sibling candidates based on #145 and are not included in #153. PR #143, #123 and #127 are independent staging candidates requiring their own conflict resolution and acceptance. PR #154 is a follow-up that changes source filenames and contract references only; it must not rerun staging DDL.

## 3. Closed-unmerged PRs — complete disposition

The 38 closed-unmerged PR numbers are:

`#1 #2 #3 #9 #21 #22 #31 #38 #43 #62 #63 #64 #73 #74 #76 #77 #79 #80 #82 #83 #85 #86 #87 #93 #95 #101 #109 #112 #122 #124 #125 #126 #139 #140 #144 #145 #151 #152`

Disposition:
- **Already represented in staging ancestry or later merged work:** #1–#3, #9, #21–#22, #38, #62, #73, #80, #82, #83, #85–#87, #93, #95, #101.
- **Superseded by a later accepted implementation:** #43 by guarded schedule/policy work (#113/#119); #64/#109/#112 by #138; #76 by #103; #77 by #105; #122 by rebased #136; #124 by #120; #125 by #127; #126 by later dynamic-fixture and tenant membership work (#128/#130/#132); #139 by #138; #140 by #142; #144/#145/#151/#152 by merged #153.
- **Do not mass-merge:** #74 broad staging snapshot and #79 enterprise snapshot. Both are historical aggregation branches, not safe integration units.
- **Unique acceptance scenarios retained:** #31's historical 21 PASS scenarios are not current runtime proof. A safe subset is carried in #114; remaining Owner-positive, no-permission, inactive-account and two-tenant execution evidence remains required.
- **Production source carry-forward:** #63 is still represented by open #104 against `main`; this is separate from staging and must not be treated as completed production parity.

The detailed 20-Nov row-by-row historical archive remains on the still-open PR #108 branch and has not been copied into `staging`; this 28-Nov document is the current source of truth for disposition and merge decisions. Keep #108 open until its historical archive is preserved or intentionally retired.

## 4. Staging database — post-merge migration snapshot

Project `dlice-staging` / `higoadrzxnhzbbwhdbmh` is `ACTIVE_HEALTHY` (PostgreSQL 17.11, ap-southeast-1).

| Evidence | Before integration | After integration |
|---|---:|---:|
| Applied migration history | 63 | **72** |
| Public tables with RLS enabled | 68 / 68 | **146 / 146** |
| Branch rows | 155 | 155 |
| Active branches | 5 | 5 |
| Planned/pending branches | 150 | 150 |
| Branch Operations tables | 0 | **7** |
| Private `branch-ops-evidence` bucket | absent | **present** |

Nine migrations were applied to staging, one at a time, through the Supabase migration tool, after the candidate PR #153 was merged:
- `20261128025950` — CRM/Loyalty financial close
- `20261128030011` — HR workforce/payroll/Finance
- `20261128030020` — Delivery fulfillment/provider
- `20261128030021` — Franchise expansion
- `20261128030024` — Procurement supplier
- `20261128030026` — BI analytics
- `20261128030028` — SaaS tenant billing
- `20261128030031` — Executive Command Center
- `20261128030033` — Branch Operations persistence

All nine apply operations returned success. Staging schema checks confirm all 17 CRM tables, HR payroll tables, canonical Delivery tables (`delivery_dispatches`, `delivery_provider_events`, `delivery_outbox`, etc.), Franchise, BI, SaaS, Procurement (`procurement_supplier_invoices`, `procurement_approval_events`, etc.) and all seven Branch Operations tables exist. Earlier probes used two noncanonical table-name guesses (`delivery_fulfillment_events`, `procurement_supplier_links`); their absence is not a migration failure because the actual schema uses the canonical names above.

Branch Operations security checks on staging:
- All seven Branch Operations tables have RLS enabled.
- `anon` and `authenticated` cannot SELECT those tables; `service_role` can.
- All 14 Branch Operations functions (including internal guards and immutable trigger) deny EXECUTE to `anon` and `authenticated`; `service_role` has EXECUTE.
- Evidence bucket is private, limited to 8 MiB and JPEG/PNG/PDF.
- Query of public functions found no function with EXECUTE granted to `anon` or `authenticated`.
- Overall public table RLS is 146/146.

The Supabase apply tool generated actual version numbers different from the candidate filenames. This PR reconciles all ten source filenames (nine new migrations plus the earlier POS lifecycle source) to the exact staging migration ledger versions/names. Do not reapply any of these migrations; this is source-history reconciliation only.

### Owner / runtime gate

A read-only query of `auth.users.raw_app_meta_data` returned zero users whose `platform_owner` value is JSON boolean true. This contradicts the earlier report that Owner Auth had been repaired. The Supabase connection available for this audit does not expose an official Auth Admin metadata update or Edge Function secret-read action; do not mutate Auth metadata with SQL and do not guess the protected allowlist value. POS mutation E2E and Owner drill-down remain blocked until the existing Owner account and `DLICE_PLATFORM_OWNER_USER_IDS` allowlist are independently verified through the official admin path.

### Advisor / platform gates

- Supabase Security Advisor still reports leaked-password protection disabled (WARN). Application-layer Pwned Passwords checks do not replace the native Auth control.
- Vercel Preview is currently blocked by the Free build/deployment quota; no latest-head Preview runtime evidence exists.
- 150 planned branches are not 150 operationally active branches or evidence of 150-branch transaction throughput.
- Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`.

## 5. Exact-head validation and staging deployment evidence

- PR #153 was squash-merged to `staging` as commit `2f661ee30f95f09f6d32f0f749189f7ae95ed433`.
- Exact pre-merge head `b107f20b1629b8b20e7359da0e644c9da99809fb`: quality checks, full CRM/HR/eight-domain disposable replay and Branch Operations disposable replay all PASS.
- The CLI-generated Branch Operations migration was committed and its 92 pgTAP assertions passed in disposable replay.
- After the merge and nine staging migrations, three Edge Functions were deployed to the staging project:
  - `branch-operations` v1, `verify_jwt=true`.
  - `hr-payroll-provider-webhook` v1, `verify_jwt=false` (HMAC/provider signature is the function's auth boundary).
  - `dlice-orders` v74, `verify_jwt=false` (preserves the existing setting; function code performs its own authenticated actor/tenant authorization).
- No Production function or database was changed.
- Vercel Preview remains blocked by the Free build/deployment quota; no Preview success is claimed.

## 6. Remaining staging acceptance and release gates

1. Source filename ↔ Supabase migration ledger parity PR #154 is merged as `5893589d22cce9a891ad065c808867db2f6a7e37`; the staging tree has 72 source files / 72 applied versions / zero mismatches / zero orphan files. Exact-head quality, CRM/HR/eight-domain replay, full migration replay and Branch Operations pgTAP passed. PR #154 did not execute DDL.
2. Re-run Security and Performance Advisors after the staging migration set. Current Security Advisor: leaked-password protection disabled (WARN). Current Performance Advisor: 168 unindexed-FK INFO findings and 132 unused-index INFO findings; do not delete indexes based only on zero scans. Add FK indexes only after query-plan/usage review and confirm they are not already covered by composite indexes.
3. Verify Auth Owner through official Supabase Auth Admin and protected allowlist. Current read-only Auth query still returns **zero** users with `raw_app_meta_data.platform_owner` JSON boolean true. No SQL metadata mutation and no allowlist guessing.
4. Tenant A/B P01–P09 acceptance on staging commit `2f661ee30f95f09f6d32f0f749189f7ae95ed433` **PASS**: both existing identities authenticated via passwordless magic link; own-branch reads passed; cross-tenant reads and writes denied; zero DB side effects verified; RLS direct-client reads exposed no branch rows; direct mutation RPC denied; 9/9 PASS, 0 failed, 0 blocked, 0 skipped. The separate legacy negative-probe workflow remains BLOCKED because it expects obsolete username/password and branch-ID secrets; do not treat that as an authorization failure or bypass the gate.
5. POS data reconciliation is **NOT BALANCED** on current staging data: 6 historical paid sales (25–26 Oct) total IDR 600; 0 tender rows, 0 receipt rows, 0 cash reconciliation rows, 0 Finance journal entries; 6 KDS tickets; 26 stock movements; 273 admin audit logs. Each of the six sales has no matching tender allocation and no immutable receipt (6/6 exceptions). Do not invent tenders/receipts or alter historical data; trace whether these are incomplete legacy/test fixtures before remediation. Run POS mutation E2E only after Owner Auth and allowlist are independently verified.
6. Run Delivery and Payroll provider E2E (signed webhook/idempotency, payout items, settlement and bank reconciliation). Deployment alone is not provider E2E proof.
7. Run Owner Command Center company → region → branch → shift → transaction drill-down; reconcile POS/Finance/Inventory/Delivery/HR/KDS totals and freshness.
8. Execute backup/restore drill and 150-branch concurrency/tenant-isolation probes. The current 150 branches are planned/pending, not operationally active.
9. Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`. No release or Production promotion is authorized by this staging integration.

**Decision:** PR #153 and PR #154 are merged; nine migrations are applied; all 72 migration filenames map 1:1 to the 72 Supabase ledger versions on `staging`. Staging A/B P01–P09 passed. Quality CI, CRM/HR/eight-domain replay and full disposable migration replay pass on PR #154's current candidate head; Branch Operations dedicated replay is the remaining required automated check before PR #154 merge. Three staging Edge Functions are deployed. Full operational reconciliation remains incomplete: Owner Auth boolean is still absent (0 accounts), POS 6/6 sales lack tenders and receipts, cash/Finance reconciliation tables are empty, and Delivery/Payroll provider E2E, Owner drilldown, backup/restore and 150-branch scale tests remain outstanding. No feature is promoted to DONE based on migration or deployment alone.
