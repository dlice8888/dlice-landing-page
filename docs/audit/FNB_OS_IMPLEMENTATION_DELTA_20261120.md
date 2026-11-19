# D’Lice FnB OS — current implementation and release delta

**Snapshot:** 20 November 2026 (WIB)  
**Repository:** dlice8888/dlice-landing-page  
**Target branch:** staging  
**Baseline SHA:** 4a13e70ce29e3fe117b6b6e7705089fa4241298a  
**Decision:** NO-GO for production; tenant isolation and operational runtime acceptance remain blocked.

This delta supersedes the 18 November status fields in the historical audit documents. The detailed feature register and evidence-by-file matrix remain in FNB_OS_IMPLEMENTATION_MATRIX.json; its embedded snapshot is historical and must not be mistaken for a 20 November runtime result.

## Changes integrated into staging since the 18 November audit

| PR | Change | Integration result |
|---:|---|---|
| #96 | Add staging-only P01–P09 manual workflow to default branch | Merged to main; workflow is guarded to run only against staging |
| #94 | Track applied stock-workflow RPC ACL migration source | Merged to staging |
| #99 | Revoke default client EXECUTE on public RPCs; add pgTAP ACL coverage | Merged to staging; migration source pending application |
| #100 | Consolidate P03 role model, canonical Tenant A secret mapping, and E2E workflow dispatch controls | Merged to staging |
| #78 | Atomic Owner/tenant bootstrap RPC and Edge Function path | Merged to staging; migration timestamp normalized by #102 |
| #102 | Normalize Owner bootstrap migration order after applied history | Merged to staging |
| #103 | Owner Command Center summary RPC, API, UI filters, and tests | Merged to staging |
| #105 | Atomic Branch Operations checklist RPC, Edge Function checks, and tests | Merged to staging |

The Command Center is a foundation, not the full 150-branch Owner Command Center: regional rollups, branch rankings, margin/COGS reconciliation, and complete hierarchy drill-down are not yet evidenced. Branch checklist implementation is code/schema foundation; authenticated branch-role browser acceptance remains outstanding.

## Current migration reconciliation

| Check | Result |
|---|---:|
| Migration source files on staging | 52 |
| Applied migration-history rows in Supabase staging | 48 |
| Pending source migrations | 4 |
| Applied DB versions missing source | 0 |
| Duplicate source versions | 0 |

Pending migrations, in order:
1. 20261119160000_revoke_default_public_function_execute.sql
2. 20261120100000_atomic_owner_and_tenant_bootstrap.sql
3. 20261120110000_command_center_summary.sql
4. 20261120120000_atomic_branch_checklist_audit.sql

Migration 20261022140302_add_missing_fk_supporting_indexes.sql is present in staging source. Its SQL matches the statements stored in the live staging migration-history row exactly after trimming surrounding whitespace. It must not be replayed against shared staging; it is already recorded as applied.

No shared Supabase staging migration has been applied as part of this integration. The 4 pending migrations were tested only on disposable local Supabase.

## Current CI and test evidence

Latest staging commit: 4a13e70ce29e3fe117b6b6e7705089fa4241298a.

| Check | Latest result | Evidence |
|---|---|---|
| Free quality checks | PASS | Run 44579674385 |
| Disposable migration replay | PASS | Run 44579674275; all 52 migration files replayed |
| Database pgTAP contracts | PASS | 4 files, 67 tests, zero failures |
| KDS offline contract | PASS | Run 44579674589 |
| Procurement receiving contract | PASS | Run 44579674180 |
| Staging runtime CORS probes | PASS | Run 44579674771 |
| Browser smoke | PASS | Run 44579674396 |
| P01–P09 tenant isolation | BLOCKED | Run 44579674471; PASS 0, FAIL 0, BLOCKED 9, SKIPPED 0 |
| Authenticated tenant negative probes | BLOCKED | Run 44579674333; preflight failed before any request |
| POS/KDS/Stock positive E2E | BLOCKED | Run 44579674219; Owner credential preflight failed; business flow did not run |
| P0 HTTP security bootstrap | BLOCKED | Run 44579674185; Owner credentials empty; no test account provisioned |
| Backup/restore | NOT RUN | No restore rehearsal evidence |
| 150-branch load test | NOT RUN | No load-test evidence |

The P01–P09 workflow did not test authorization in this run. All nine probes were BLOCKED with executed=false because the runner resolved the following inputs as empty: Tenant A/B usernames and passwords, tenant IDs, branch IDs, and user IDs. The result is not an authorization failure and not a pass. It is a configuration preflight blocker. No probe request was made.

The separate negative-probe workflow also stopped before sending a request because canonical Tenant A credentials and the Tenant B branch fixture were empty. The KDS/POS/Stock and P0 HTTP workflows stopped before business mutations because Owner username/password inputs were empty.

## Current 18-domain implementation assessment

| # | PRD domain | Status | Evidence and remaining gap |
|---:|---|---|---|
| 1 | Executive Command Center | PARTIAL | #103 adds Owner-only summary, date/branch filters, and operational KPIs; no region rollups, branch rankings, margin/COGS reconciliation, or full hierarchy drill-down |
| 2 | POS & Checkout | PARTIAL | POS/checkout foundations exist; positive E2E did not execute because Owner preflight failed |
| 3 | Order Management | PARTIAL | Order/fulfillment workflows exist in staging; full channel-to-branch exception and escalation E2E not proven |
| 4 | Kitchen & Production | PARTIAL | KDS/offline contract passes; POS→payment→KDS→recipe consumption reconciliation E2E is blocked |
| 5 | Menu & Recipe | PARTIAL | Recipe/BOM/version activation code and migrations exist; measured consumption/yield/waste E2E not proven |
| 6 | Inventory | PARTIAL | Stock ledger/transfers/counts and RPC ACL controls exist; own-branch/cross-tenant runtime probes P04–P09 are blocked |
| 7 | Procurement | PARTIAL | PR/PO/receiving contracts pass; authenticated positive procurement E2E has not run |
| 8 | Branch Operations | PARTIAL | #105 adds atomic checklist/audit workflow; 27 branch checklist pgTAP assertions pass; role-based browser acceptance not run |
| 9 | Delivery | NOT VERIFIED | Biteship/provider integration and end-to-end delivery lifecycle not verified |
| 10 | CRM & Loyalty | NOT VERIFIED | No current runtime evidence for customer profiles, points, rewards, or redemption |
| 11 | Finance | PARTIAL | Refund, settlement, cash reconciliation, and period guards exist; full finance reconciliation E2E not run |
| 12 | HR | NOT VERIFIED | Staff/profile administration exists; scheduling, attendance, payroll, and HR lifecycle acceptance not evidenced |
| 13 | Franchise | NOT VERIFIED | Franchise onboarding, royalty, compliance, and franchisee reporting not evidenced |
| 14 | BI & Analytics | PARTIAL | Command Center summary foundation exists; authoritative consolidated finance, regional comparisons, and drill-down remain incomplete |
| 15 | Admin & Access | PARTIAL | Tenant permission unit tests pass; existing Owner Auth metadata and runtime authorization remain blocked |
| 16 | SaaS Tenant Management | PARTIAL | Two distinct tenants and memberships exist; P01–P09 runtime isolation remains blocked; bootstrap migration is pending |
| 17 | Integrations | NOT VERIFIED | Marketplace, WhatsApp, payment-provider, and delivery-provider lifecycle acceptance not evidenced |
| 18 | Quality & Security | PARTIAL | Static CI, CORS, migration replay, and pgTAP pass; runtime tenant isolation, backup/restore, load, and release protection remain outstanding |

## Current P0 blockers

1. **Owner authorization:** one active Owner profile is linked to an Auth user, but the linked Auth identity still lacks boolean app_metadata.platform_owner=true. The server-side DLICE_PLATFORM_OWNER_USER_IDS allowlist is not independently verified. Do not update auth.users via SQL; use the authorized Supabase Auth Admin path.
2. **GitHub staging inputs:** the runner sees empty canonical Tenant A/B credentials and six tenant/branch/user fixture variables. Values were not printed. The connector cannot write Environment secrets/variables.
3. **Runtime tenant isolation:** P01–P09 must all execute with zero BLOCKED and zero SKIPPED; cross-tenant reads and writes must be denied using two real Auth identities.
4. **Business E2E:** POS/KDS/Stock and Procurement E2E must complete with reconciliation artifacts; current runs stop before business mutations.
5. **Migration application:** four pending migrations require final SQL/security review, backup confirmation, and explicit staging approval before application.
6. **Branch protection and deployment protection:** repository rulesets/required checks and staging protection have not been independently verified/configured through the available GitHub integration.
7. **Backup/restore and scale:** restore rehearsal and 150-branch load test remain unexecuted.

## Main / production boundary

Vercel Git integration confirms that branch main is the production deployment branch. PR #104 carries production CORS source and static contract/type-check coverage; its checks pass, but it remains Draft. It must not be merged before all release gates pass because merging to main triggers production deployment. Production Supabase, production Edge Functions, and production deployment were not changed by this integration.

## Release flags

- TENANT_ISOLATION_RELEASED=false
- PUBLIC_TENANT_ROUTING_RELEASED=false

**Decision remains NO-GO.** Staging code and disposable database tests have progressed, but no shared staging migration application, staging Edge Function deployment, production deployment, or release-flag change is authorized by this report.
