# D’Lice FnB OS — Full PR History, Merge Dependency and Staging Reconciliation
**Audit timestamp:** 2026-11-28 (WIB)  
**Repository:** `dlice8888/dlice-landing-page`  
**Staging Supabase project:** `higoadrzxnhzbbwhdbmh`  
**Scope:** first actual PR through latest PR, current merge candidates, source migration lineage, staging schema and release blockers.

## 1. Repository-wide PR totals

GitHub search across the repository returns **152 actual pull requests** (PR numbers 1–154; #34 and #52 are absent):

| Current disposition | Count |
|---|---:|
| Merged | 93 |
| Closed without merge | 32 |
| Open | 27 |
| **Actual PRs** | **152** |

The historical PR #108 audit covered 105 actual PRs through #107 (75 merged, 25 closed-unmerged, 5 open). The current inventory adds 47 actual PRs #108–#154, yielding the counts above. The PR count is a repository-history count, not a feature-completion metric.

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
| #144 | staging | Eight-domain workflow kernel | Superseded by merged #153 dependency tree; close as redundant after confirming all changes are carried forward |
| #145 | #144 head | Eight-domain transactional orchestration | Superseded by merged #153 dependency tree; close as redundant after confirming all changes are carried forward |
| #146 | #145 base | Xendit Payout v3 payroll adapter | Conflicted candidate; provider E2E and payout reconciliation still required |
| #147 | staging | 189-feature evidence matrix refresh | Keep as audit source only after refreshing it from this snapshot; no unsupported score promotion |
| #148 | staging | Disposable PostgreSQL 17 backup/restore drill | Keep; execute and retain restore evidence before staging release acceptance |
| #149 | staging | 150-branch tenant isolation concurrency probe | Keep; execute with 150 real/planned fixtures only where provisioned, and distinguish planned from active branches |
| #150 | #145 base | Food safety, recall and supplier CAPA workflows | Conflicted; rebase and run domain pgTAP + workflow/E2E before merge |
| #151 | #145 base | CRM financial-close SQL syntax correction | Superseded by merged #153; corrected SQL is included in the merged dependency tree |
| #152 | #145 head | Eight-domain official migrations and ACL hardening | Superseded by merged #153; its migration/ACL work is included in the merged dependency tree |
| #154 | staging | Source migration filenames ↔ applied Supabase ledger parity | Current follow-up candidate; filename-only source reconciliation, no DDL; exact 72/72 mapping verified, disposable/quality tests must pass before merge |
| #153 | staging | 39 PRD gaps, Branch Operations persistence and integrations | **Merged** to staging as `2f661ee30f95f09f6d32f0f749189f7ae95ed433`; nine schema migrations subsequently applied |

### Required dependency chain

```
staging
  └─ PR #144 workflow kernel
       └─ PR #145 eight-domain orchestration
            └─ PR #152 eight-domain migrations + ACL
                 └─ PR #153 Branch Operations persistence + adapters (merged)
                      └─ PR #154 migration filename ↔ ledger parity (pending)
```

PR #151's CRM SQL syntax correction is carried through #152 into merged #153. PR #144/#145/#151/#152 remain open but are superseded by merged #153 and should be closed as redundant after #154 parity is accepted. PR #146 and #150 are sibling candidates based on #145 and are not included in #153. PR #143, #123 and #127 are independent staging candidates requiring their own conflict resolution and acceptance. PR #154 is a follow-up that changes source filenames and contract references only; it must not rerun staging DDL.

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

1. Complete source filename ↔ Supabase migration ledger parity PR #154; the current candidate tree has 72 source files / 72 applied versions / zero mismatches / zero orphan files. Complete exact-head quality, CRM, full migration replay and Branch Operations pgTAP before merge. This PR does not execute DDL.
2. Re-run Security and Performance Advisors after the staging migration set. Current Security Advisor: leaked-password protection disabled (WARN). Current Performance Advisor: 168 unindexed-FK INFO findings plus unused-index INFO findings; do not delete indexes based only on zero scans. Add FK indexes only after query-plan/usage review and confirm they are not already covered by composite indexes.
3. Verify Auth Owner through official Supabase Auth Admin and protected allowlist. Current read-only Auth query still returns **zero** users with `raw_app_meta_data.platform_owner` JSON boolean true. No SQL metadata mutation and no allowlist guessing.
4. Run authenticated tenant A/B own-read/write, cross-tenant read/write denial, branch isolation, Storage and background-job probes; require zero BLOCKED/SKIPPED and verify postconditions.
5. Run POS staging E2E only after Owner Auth and allowlist are independently verified. Reconcile sale totals, tender allocations, cash drawer, stock movements, KDS tickets, immutable receipt and audit events.
6. Run Delivery and Payroll provider E2E (signed webhook/idempotency, payout items, settlement and bank reconciliation). Deployment alone is not provider E2E proof.
7. Run Owner Command Center company → region → branch → shift → transaction drill-down; reconcile POS/Finance/Inventory/Delivery/HR/KDS totals and freshness.
8. Execute backup/restore drill and 150-branch concurrency/tenant-isolation probes. The current 150 branches are planned/pending, not operationally active.
9. Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`. No release or Production promotion is authorized by this staging integration.

**Decision:** PR #153 and nine schema migrations are merged/applied to staging, and the three relevant Edge Functions are deployed. Schema/RLS/ACL/Storage checks are passing. Full operational reconciliation is still blocked by the unverified Owner Auth boolean/allowlist and outstanding tenant A/B, POS, provider, backup/restore and scale runtime tests. No feature is promoted to DONE based on migration or deployment alone.
