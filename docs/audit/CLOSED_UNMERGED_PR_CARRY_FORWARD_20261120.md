# Closed-unmerged PR carry-forward audit — 20 November 2026

Repository: dlice8888/dlice-landing-page  
Snapshot: GitHub PR listing re-read on 20-Nov-2026  
Purpose: prove that closed-without-merge does not mean discarded, and identify every useful artifact that must remain in the final D’Lice system.

## Executive conclusion

The repository currently has 111 actual PRs: 77 merged, 26 closed without merge, and 8 open. The eighth open PR is #113, a security fix that removes scheduled staging mutation paths. The 26 closed PRs do not represent 26 missing implementations. Their dispositions fall into four groups: already integrated, superseded, historical evidence/governance, and unique acceptance scenarios or source-control/security gaps that still need carry-forward.

This is a per-PR disposition, not a claim that all associated product behavior has passed runtime acceptance.

## Per-PR disposition

| Closed PR | Scope | Why closed without merge | Current carry-forward evidence / disposition | Remaining action |
|---:|---|---|---|---|
| #101 | Recover applied FK-index migration source 20261022140302 | Recovery completed as separate source reconciliation | Exact migration file and migration-source-recovery-contract.test.mjs exist on staging; history contains this version | Keep source byte-for-byte aligned with recorded SQL; never replay an already-applied version |
| #95 | Correct P03 role model and externalize staging workflow config | Replaced by dynamic A/B fixture and acceptance workflow work | Current P03 uses global sales_admin and tenant membership branch_manager; #110 discovers A/B fixtures and sources A/B credentials from protected environment | Verify KDS/procurement workflow URLs/keys are secret-backed; do not restore old fixture assumptions |
| #93 | Parse inline JS modules with top-level await correctly | Later staging source includes module-aware parser correction | Current staging-release-contract-tests.mjs checks inline modules through temporary .mjs files and Node --check; classic scripts still use vm.Script | Retain behavior and add regression coverage if parser changes |
| #87 | P03 ordinary branch_worker identity assertion | branch_worker expectation contradicted actual role model and was corrected by #95 | Current acceptance distinguishes global admin_profiles.role=sales_admin from tenant_memberships.role=branch_manager | Do not reinstate branch_worker as P03 prerequisite; preserve masked/no-secret evidence |
| #86 | Add branch_worker profile class, Owner role-management action/UI, migration | Role model later reconciled and migration represented by applied branch-worker migration | Current staging has admin-set-profile-role Edge action and migration version 20261119155309 in history | Verify UI remains surfaced and Owner-only/anti-downgrade rules; P03 uses actual A/B identities |
| #85 | Enable branch-scoped inventory list for authorized workers | Later staging handler evolved the implementation | Current staging has erp-list-inventory; branch authorization and tenant-boundary probes are represented in current runtime suite | P04/P06 own-branch success and P05/P07 cross-tenant denial still need actual staging execution |
| #83 | Fail-closed staging preflight and remove literal public-key value | Replaced by newer fixture-discovery/preflight implementation | #110 discovers user, tenant and branch fixtures from staging responses and requires A/B credentials before probes | Run workflow from staging; static checks are not runtime proof |
| #82 | Normalize whitespace in release evidence docs | Documentation-only formatting change | No unique semantic behavior or migration; current audit carries current release decision | No code port required; retain NO-GO and false release flags |
| #80 | Historical staging execution baseline and Owner/config evidence | Snapshot superseded by later live re-audits | Tenant/membership/branch inventory, Owner Auth metadata, GitHub protection and migration parity are refreshed in current audit/matrix | Treat original counts/SHAs as historical only |
| #79 | Broad Enterprise FnB OS integration snapshot | Large branch was not a safe atomic integration unit; head is ancestor of staging with substantial divergence | Feature and documentation content is represented across staging history; diff is inventory source, not merge candidate | No wholesale merge; reconcile any individual missing feature by file/migration/test and PRD row |
| #77 | Atomic branch checklist audit transaction | Replaced by monotonic migration/source PR #105 | #105 carries 20261120120000_atomic_branch_checklist_audit.sql, API guard and pgTAP rollback/version tests; #112 hardens role claims | Apply only after release gates; do not apply old 20261114120000 migration separately |
| #76 | Owner Command Center summary | Replaced by monotonic migration/source PR #103 | #103 carries 20261120110000_command_center_summary.sql, UI/API route and contracts | Do not apply old 20261114110000 migration; full 150-branch margin/anomaly/target/alert/drill-down acceptance remains |
| #74 | Broad staging snapshot / mass integration branch | Snapshot merge would overwrite newer staging protections and mix unrelated changes | Useful features split across staging PR history; #108 records per-PR overlap and dependencies | Never use #74 as mass merge path |
| #73 | Branch cleanup, inventory and repository protection audit documents | Historical cleanup PR closed; evidence snapshot stale | Seven governance/audit documents recovered into #108 audit branch with explicit 13-Nov historical warnings | Refresh branch SHA, branch count, protection/ruleset and migration claims before operational use |
| #64 | Tenant isolation audit and initial same-tenant stock-transfer migration | Initial migration/test proposal superseded by stronger #109 | Finding carried by #109 endpoint trigger, API guard, row locks and two-session reassignment race test; #110 owns current P01–P09 harness | Do not apply old 20261028120000 migration separately; preserve negative cases and require real P01–P09 |
| #63 | Production dlice-orders source and fail-closed CORS | Superseded by narrower production CORS source/contract PR #104, not yet merged | #104 carries identical Edge Function source blob plus production CORS contract/workflow | Still outstanding: main lacks source file until #104 or equivalent reviewed change integrates; production CORS runtime validation required |
| #62 | Trigger-only RPC ACL, E2E harnesses and Superpowers governance | ACL applied/reconciled separately; broad branch not merged as a unit | Trigger-only ACL migration applied; project-specific method preserved in #108 local AGENTS.md and engineering note; staging has later E2E harness versions | Keep governance standard; reconcile main-only submodule/workflow differences; do not copy workflows bypassing mutation confirmation |
| #43 | Scheduled procurement positive E2E | Duplicate/superseded by #44 after default-branch assumption corrected | Main already has scheduled procurement workflow; staging has guarded manual workflow | Security follow-up: inspect/disable schedules that can write staging without explicit confirmation; do not port old schedule condition unchanged |
| #38 | Procurement requisition contract assertions | Closed after staging E2E harness changed | Current staging procurement-requisition-contract.mjs contains reconcile action and created/converted audit event assertions | Retain assertions; they are not proof of live procurement runtime |
| #31 | Cross-role P2P, O2C, stock and Finance negative acceptance scenarios | Workflow used legacy credentials and hard-coded Branch B UUID; unsuitable for direct merge | Historical run reported 21 PASS / 0 FAIL, but this is not current runtime evidence. Unique scenarios are absent at original path in current staging | Port required: adapt Owner/branch-manager, no-permission and inactive cases to protected fixtures; dynamic branch discovery, impossible IDs, masked evidence and no-SKIPPED |
| #22 | Order routing, online checkout capacity, fulfillment, production/finance UI and migrations | Head already in staging ancestry | Current staging source/migration history contains feature foundation; #103 extends Command Center summary | Preserve functionality; audit each workflow against PRD and live E2E rather than treating old PR as current pass |
| #21 | Branch-aware fulfillment, purchasing receipt, recipe/BOM production consumption and finance schema | Head already in staging ancestry; later PRs hardened/reconciled it | Relevant staging migrations and API/UI code present; later PRs add ACL, atomicity and contract hardening | Preserve foundation; live PO/receipt/production/settlement/refund/cash/finance reconciliation remains unproven where staging has zero rows |
| #9 | Free hardening and integration audit | 13 of 14 files matched staging; only old CI workflow differed | Code/security/migration content represented in staging; newer staging CI intentionally retained | Do not merge historical branch or restore old workflow |
| #3 | Indonesian operations UI | Head is ancestor of staging | Language/UI change already in staging history | No separate port; verify UX/localization in current product audit |
| #2 | Supabase-backed product catalog | Head is ancestor of staging | Catalog implementation and migration history in staging ancestry | No separate port; verify current CRUD, media, pricing and availability |
| #1 | Initial Supabase ordering backend and admin panel | Superseded by staging integration; no unique commits absent from staging history | Ordering/backend foundation in staging ancestry | No separate port; validate checkout/payment/notification security against current PRD |

## Explicit carry-forward register

1. P2P/O2C/Finance negative acceptance from #31. Historical 21/21 is not a current pass. Port scenarios to the current dynamic-fixture framework and execute with real staging identities.
2. Production CORS/source reproducibility from #63. #104 is still open against main; do not assume production source parity.
3. Scheduled workflow mutation safety from #43/#62. A schedule must not bypass explicit, protected staging-mutation confirmation.
4. Owner role-management behavior from #86. Migration and API action exist in staging source; verify UI and authorization/anti-downgrade tests.
5. Tenant isolation from #64/#85/#87/#95/#110. Preserve branch-scoped inventory, correct role model, fixture masking, and all nine real runtime probes.
6. Migration lineage from #101/#76/#77/#102/#103/#105/#109/#112. Keep recovered/applied source exact; never replay an already-applied migration under a new version.
7. Superpowers/engineering governance from #62/#73/#80. Keep local D’Lice operating standard and provenance; refresh stale evidence.

## Release decision

- Do not reopen or merge a closed PR wholesale merely to improve PR counts.
- No feature is complete solely because a closed PR reported CI success.
- Unique #31 scenarios and #63 production source parity are explicit carry-forward work, not silently discarded.
- This audit authorizes no production mutation, shared-staging migration replay, Auth metadata change, Edge Function deployment or release-flag change.
- Keep TENANT_ISOLATION_RELEASED=false and PUBLIC_TENANT_ROUTING_RELEASED=false.
