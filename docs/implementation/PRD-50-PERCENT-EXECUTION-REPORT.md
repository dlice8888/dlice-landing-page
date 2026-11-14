# D’Lice PRD implementation progress — 2026-11-14

## Result

The requested 50% average is **not verified or achieved by this execution**. No percentage has been raised based on file presence or test compilation. The user-supplied starting percentages total 515 points, or **28.61%** across 18 equally weighted domains. The supplied target percentages total 840 points, or **46.67%** (not 46.9%); a 50% average requires at least 900 points.

Those starting percentages have not been independently rescored against feature-level acceptance evidence. Therefore the current verified 18-domain average is **not calculable**. The baseline values below are retained only as user-provided reference values.

## Increment delivered

| Domain | User baseline | Target | Evidence in this increment | Staging evidence / remaining gap |
| --- | ---: | ---: | --- | --- |
| Executive Command Center | 15% | 35% | `erp.html` now renders date and branch filters, paid POS sales, transaction count/AOV, per-branch performance, current shift/stock/order/KDS/procurement/expense queues. Edge Function validates dates and branch selection; SQL aggregates actual tables by branch-local calendar day. Static contracts and disposable database tests passed. | Not verified in staging. No region column or drill-down hierarchy in current schema/API. Access remains Platform-Owner-only. |
| POS & Checkout | 55% | 65% | No feature change in this increment. | Not reassessed; no new staging evidence. |
| Order Management | 45% | 55% | Pending online orders are counted by branch and date in the Command Center. No lifecycle changes. | Not reassessed; no new staging evidence or workflow E2E. |
| Kitchen & Production | 45% | 55% | Current KDS backlog count is included per branch. No preparation or production workflow changes. | Not reassessed; no new staging evidence. |
| Menu & Recipe | 35% | 55% | No feature change in this increment. | Not reassessed; no new staging evidence. |
| Inventory & Warehouse | 50% | 65% | Current branch-level low-stock and out-of-stock item counts are included. | Not reassessed; no new staging evidence; FIFO/FEFO and full transfer acceptance remain separate work. |
| Procurement & Supplier | 35% | 55% | Submitted requisitions and open purchase orders are counted per branch. No procurement lifecycle changes. | Not reassessed; no new staging evidence. |
| Branch Operations | 30% | 50% | Open shifts are counted per branch. No checklist or incident workflow changes. | Not reassessed; no new staging evidence. |
| Delivery & Fulfillment | 10% | 30% | No feature change in this increment. | Not reassessed; provider credentials and end-to-end delivery remain unverified. |
| CRM & Loyalty | 5% | 30% | No feature change in this increment. | Not reassessed; no new staging evidence. |
| Finance & Accounting | 20% | 40% | Pending branch expenses are counted. No journal/accounting workflow changes. | Not reassessed; no new staging evidence. |
| HR & Workforce | 15% | 35% | No feature change in this increment. | Not reassessed; no new staging evidence. |
| Franchise & Expansion | 5% | 25% | No feature change in this increment. | Not reassessed; no new staging evidence. |
| BI & Analytics | 10% | 35% | Date-filtered paid POS sales, transaction count, AOV, and current branch-operational indicators are displayed from database-backed aggregates. | Not verified in staging. No export, margin, region, or tenant-member aggregation certification. |
| Admin & Access Control | 50% | 65% | Existing server-side Platform Owner identity check is retained; the summary RPC is not executable by `anon` or `authenticated`. No permission expansion. | Tenant membership access remains closed under the release gate; not newly certified. |
| SaaS Tenant Management | 40% | 55% | No feature change in this increment. | Not reassessed; no new staging evidence. |
| Integrations & Automation | 15% | 35% | No feature change in this increment. | Not reassessed; no new staging evidence. |
| Quality, Compliance & Security | 35% | 55% | Added SQL/API/UI contracts and pgTAP coverage for server-only execution, branch-scope behavior, reporting-period limits, and a seeded branch. `TENANT_ISOLATION_RELEASED` remains `false`. | No live tenant A/B probe passed in this increment; no staging deployment, browser E2E, backup restore, or production verification. |

## Verification evidence

- `node scripts/quality-checks.mjs` — PASS (HTML and inline JavaScript syntax, repository quality markers).
- `node scripts/staging-release-contract-tests.mjs` — PASS (release contracts; explicitly not browser E2E).
- `node --test tests/contracts/command-center-contract.test.mjs tests/contracts/tenant-refund-scope-contract.test.mjs tests/contracts/staging-secret-workflow-contract.test.mjs` — PASS, 9 tests.
- Supabase CLI `2.122.0`, disposable local Supabase: all 46 repository migrations replayed successfully; `supabase test db` — PASS, 6 database tests. This is local disposable evidence, not staging evidence.
- `git diff --check` — PASS.

## Release and environment status

- Work is on `feat/erp-command-center-foundation`, based on staging commit `aed2733f62506ed87a5040a48f479753fdafe1b1`.
- PR #64 remains Draft and has a dirty merge state; its runtime tenant gate is failing. Its migration was not included or applied.
- PR #75 remains Draft. Its existing checks do not certify tenant isolation.
- The latest observed staging tenant-boundary negative-probe workflow failed. This increment did not run authenticated staging probes.
- GitHub API access to staging Environment secret and variable metadata returned HTTP 403, so presence of the six tenant-gate secrets and `STAGING_ALLOWED_ORIGIN` could not be verified. No secret values were requested or read.
- Supabase staging migration state, Vercel staging deployment, and Figma/browser acceptance were not accessed or verified in this increment.
- No migration was applied to Supabase staging or production. No staging or production deployment was initiated.
- Production remains protected; no merge or release was performed.

## Blockers to a defensible 50% score

1. Establish a repeatable, evidence-backed scoring rubric for every feature in all 18 domains and reassess the existing implementation against it.
2. Resolve and pass the live two-tenant authentication, membership, branch mapping, cross-tenant read/write denial, and required independent review gates before certifying tenant-scoped features.
3. Obtain owner access to staging-only credentials and remote status checks (GitHub Environment metadata currently returns HTTP 403), apply the reviewed migration only after the release gate, and run browser/integration E2E against staging.
4. Implement and verify additional domain workflows; this increment advances a Command Center/BI foundation only and is not sufficient to reach 50%.


## Live staging snapshot — verified 2026-11-14 (read-only)

The following measurements were queried directly from Supabase project `higoadrzxnhzbbwhdbmh` after this report's original draft. They are staging measurements, not estimates:

| Measurement | Live staging result |
| --- | ---: |
| Supabase project health | ACTIVE_HEALTHY |
| PostgreSQL | 17.11 |
| Public tables | 64 |
| Tenant records | 2 |
| Branch records | 155 |
| Tenant memberships | 3 |
| Products | 4 |
| Recipes / recipe ingredients | 1 / 2 |
| POS sales / shifts | 6 / 7 |
| Orders / kitchen tickets | 7 / 6 |
| Branch inventory / stock movements | 4 / 26 |
| Stock transfers / stock counts | 0 / 0 |
| Purchase requisitions / purchase orders / receipts | 0 / 0 / 0 |
| Production batches / consumptions | 0 / 0 |
| Finance journal entries / cash reconciliations | 0 / 0 |
| Branch operation checklist runs | 1 |
| Integration connections / outbox events | 0 / 0 |
| Backup/restore runs | 0 |
| Applied migration records | 43; latest `20261027140145` |

A read-only SQL count attempt initially referenced a nonexistent legacy relation name `branch_checklist_runs`; the query was corrected to the actual `branch_operation_checklist_runs` table before the counts above were recorded. No staging data was changed.

### Live Supabase advisor findings

- Security advisor: leaked-password protection is disabled (1 warning).
- Performance advisor: 26 foreign keys without covering indexes and 49 indexes currently reported unused. Unused-index findings are informational and must not be handled by dropping indexes without workload evidence.
- Health advisor: no lints returned in this query.

### PR #76 and preview status

- PR #76 `feat(erp): add owner command-center summary` remains Draft, open, and has no submitted independent review.
- Head: `d18757efbfa564d75d05384acfbc34b69b76d0c8`; base: `staging`.
- GitHub Actions associated with the head show success for Free quality checks, disposable local migration replay, CORS probes, Kitchen KDS offline contract, Procurement requisition contract, and Procurement receiving contract.
- Vercel preview: `https://dlice-landing-page-mzizcnmb3-dlice8888-7332.vercel.app`, state READY. This is a PR preview, not proof of the staging branch deployment or authenticated browser acceptance.
- PR #76 migration `20261114110000_command_center_summary.sql` is not in the live staging migration history and has not been applied.

### Merge and migration decision

- PR #76: do not merge or apply its migration yet. It is Draft, has zero submitted reviews, and its own acceptance report explicitly says no staging verification or browser E2E. Review the SECURITY DEFINER RPC, UI/API authorization path, and staging runtime behavior first.
- PR #75: keep Draft; the nine authenticated tenant-isolation probes have not passed.
- PR #64: keep Draft and its migration untouched.
- PR #62: do not merge. It is non-mergeable, its base/head state is not clean, and the submitted review record is only COMMENTED. The reported ACL migration is already present in staging through migration `20261027140145`; merging its PR is not needed to reapply it.
- No PR or migration was merged/applied by this audit. Production was not changed.

### Scoring consequence

The 28.61% figure remains the arithmetic average of the user-provided baseline estimates, not an independently verified implementation score. PR #76 adds code and CI evidence for an Executive Command Center foundation, but because it is not merged into staging and not verified in the staging browser, it does not justify increasing the live-staging progress score. A defensible verified average across all 18 domains remains not calculable until feature-level acceptance evidence is collected consistently.


### Additional staging controls — read-only query

- RLS is enabled on all 64 of 64 public tables.
- Of 155 branch records, 5 are `active` and 150 are `planned`.
- All 3 tenant membership records are currently `active`.
- RLS being enabled is a baseline control only; it does not prove the policies correctly deny cross-tenant or cross-branch access. Runtime JWT probes remain required.


## Reconciliation update — 2026-11-15 (live read-only verification)

This section supersedes conflicting environment counts and status statements in the 2026-11-14 snapshot above. It does not retroactively convert Preview or disposable-test evidence into staging acceptance.

### Current Supabase staging measurements

Queried directly from project `higoadrzxnhzbbwhdbmh`:

| Measurement | Verified 2026-11-15 |
| --- | ---: |
| Public base tables | 64 |
| Public base tables with RLS enabled | 64 / 64 |
| Applied migration records | 46; latest `20261027140145` |
| Tenant records | 2 |
| Branch records | 155 |
| Active branches | 5 |
| Planned branches | 150 |
| Active tenant memberships | 3 |
| Inventory balance rows | 4 |
| Tenant A `dlice-default` / `QA-DLICE-A` inventory rows | 2; on-hand total 1,240 |
| Tenant B `dlice-qa-isolation-b` / `QA-TENANT-B` inventory rows | 2; on-hand total 800 |
| Purchase orders | 0 |
| Purchase receipts | 0 |
| Production batches | 0 |
| Finance journal entries | 0 |

The Tenant B inventory fixture is now present (two balance rows, total on-hand 800). This corrects the older PR #71 narrative that Tenant B had zero inventory. This is read-only fixture evidence only; it does not prove Tenant A/B JWT login or cross-tenant read/write denial.

The only deployed Supabase Edge Function listed is `dlice-orders`, ACTIVE at version 66 with `verify_jwt=false`. Its handler must therefore enforce authentication/authorization itself on every protected action; CORS is not an authorization control.

### Current Supabase advisors

- Security: one warning — leaked-password protection disabled. Remediation: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- Performance: 26 foreign keys lack covering indexes; 49 indexes are reported unused. The unused-index list is informational; do not drop indexes without workload/EXPLAIN evidence. Remediate missing FK indexes in a reviewed, measured migration rather than applying blanket changes.
- Health: no advisor findings.

### GitHub PR gate — live status 2026-11-15

| PR | Scope | State | Review evidence | Decision |
| --- | --- | --- | --- | --- |
| #75 | Tenant-scoped permissions and A/B runtime probes | Open, Draft, mergeable | 0 submitted reviews | HOLD until nine authenticated runtime probes pass and independent review is recorded |
| #76 | Executive Command Center summary | Open, Draft, mergeable | 0 submitted reviews | HOLD; review SECURITY DEFINER/RPC authorization and validate staging UI/API before merge |
| #77 | Atomic branch checklist + audit | Open, Draft, mergeable | 0 submitted reviews | HOLD; no authenticated branch-role staging acceptance |
| #78 | Atomic owner/tenant bootstrap | Open, Draft, mergeable | 0 submitted reviews | HOLD; review service-role RPC/owner identity and run staging acceptance |
| #64 | Legacy tenant isolation transfer migration | Open, Draft, not mergeable | no qualifying independent approval | Keep untouched; migration must not be applied |

The PR #75 description now reports two distinct active Auth identities and matching A/B branch membership fixtures. Its nine live runtime probes remain unexecuted/unpassed; a successful CORS-only run is not tenant isolation evidence. PR #76–78 disposable migration replay and contract tests are not staging migration evidence.

### Staging workflow data is not yet end-to-end

The presence of schema and fixture rows is not proof of a completed operating workflow. Current staging has zero purchase orders, receipts, production batches, and finance journal entries. Therefore Procure-to-Pay, Forecast-to-Production, and Record-to-Report have no positive-path reconciliation evidence. Order-to-Cash still needs authenticated payment-to-fulfillment-to-stock-to-settlement reconciliation.

### Updated release boundary

- `TENANT_ISOLATION_RELEASED=false`; `PUBLIC_TENANT_ROUTING_RELEASED=false` remain unchanged.
- No PR was merged and no migration was applied during this reconciliation.
- No Edge Function was deployed.
- No production deployment, migration, or setting was changed.
- RLS enabled on 64/64 tables is a control baseline, not proof that tenant and branch policies are correct under live JWTs.

### PRD scoring integrity

The previously listed domain percentages are user-supplied historical baselines, not a fresh feature-level audit. The arithmetic mean of those inputs is 28.61%; it must not be presented as actual verified completion. A defensible current 18-domain percentage remains **not calculable** until each feature has a traceable implementation check, staging runtime acceptance, and a defined weighting rubric. The 50% target is not verified.


### Command Center RPC security hardening — 2026-11-15

A source-level security correction was committed to PR #76:
- `dlice_get_command_center_summary` now uses `SECURITY INVOKER`, not `SECURITY DEFINER`.
- EXECUTE remains revoked from `PUBLIC`, `anon`, and `authenticated`, and granted only to `service_role`.
- Removed the deprecated `auth.role()` authorization branch; access is enforced by PostgreSQL function privileges and the Edge Function's authenticated Platform Owner gate.
- Updated pgTAP to assert that both `anon` and `authenticated` lack EXECUTE, and updated the source contract to prohibit SECURITY DEFINER and auth.role() in this RPC.

Commit: `586e122e267a8a1656158b639325d3ae500db8b6`.
Vercel Preview for this head: READY at https://dlice-landing-page-mkr4ujxrc-dlice8888-7332.vercel.app.
The Preview is not staging acceptance. No GitHub Actions run for this exact head was returned at the time of this update; CI and disposable migration replay for the revised SQL/test suite remain pending. No staging/production migration or deployment was performed.
