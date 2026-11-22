# Current PR inventory and release-gate snapshot — 20 November 2026

Repository: dlice8888/dlice-landing-page  
Staging Supabase: higoadrzxnhzbbwhdbmh  
Audit scope: complete actual PR inventory, closed-unmerged carry-forward, live release-gate recheck.

## Current actual PR totals

**112 actual PRs = 77 merged + 26 closed without merge + 9 open.**

Open PRs at this read:
| PR | Base | Purpose | Current state |
|---:|---|---|---|
| #71 | staging | Staging tenant fixture validation | Draft; fixture/runtime acceptance pending |
| #104 | main | Production Edge Function source and CORS contract | Draft; source parity/runtime proof pending |
| #107 | staging | Environment-validated Supabase frontend config | Draft; integration and exact-head validation pending |
| #108 | staging | Full PR history, overlap and PRD audit | Draft; documentation/audit branch |
| #109 | staging | Same-tenant stock-transfer enforcement | Ready for Review; relevant CI passed; independent review pending |
| #111 | staging (rebased on #110) | OIDC staging session broker | Draft; exact-head quality, KDS and disposable replay passed; broker secrets/deployment/runtime validation pending |
| #112 | staging | Owner metadata boolean and service-role RPC hardening | Draft; exact-head quality, KDS and disposable replay passed; not applied to shared staging |
| #113 | main | Remove scheduled staging E2E mutation bypass | Draft; exact-head safety contract passed |
| #114 | staging | Carry forward closed #31 cross-module negative scenarios | Draft; exact-head quality checks passed; runtime not dispatched |

PR #106 and #110 are merged to staging, consistent with the user's decision that they did not need a separate independent reviewer.

## Closed-unmerged audit

All 26 closed-unmerged PRs are individually classified in CLOSED_UNMERGED_PR_CARRY_FORWARD_20261120.md. No PR was assumed unimportant merely because it closed. The classifications distinguish:
- already integrated through staging ancestry, identical file blobs or applied migration history;
- superseded by narrower monotonic migrations or safer dynamic-fixture tests;
- historical evidence/governance recovered into the audit;
- unique work that remains to be carried forward.

Two concrete carry-forwards were implemented as reviewable Draft PRs:
- #113 carries forward the schedule-safety finding from #43. Both positive-path staging mutation workflows no longer have schedule triggers and require workflow_dispatch plus confirm_staging_mutations=true. Exact-head contract run 44748052132 SUCCESS.
- #114 carries forward a safe subset of #31: P2P and O2C branch-scoped list success/foreign-branch denial for dynamic A/B identities; Finance least-privilege denials; impossible-ID no-op probes for PO receipt, fulfillment update, stock transfer and stock count. Exact-head quality runs 44748825658 and 44748790764 SUCCESS. Runtime has not run. Owner-positive, no-permission and inactive-account cases remain outstanding because the required verified identities are not currently available.

The production source/CORS gap from #63 remains open through #104; do not treat the source as present in main until reviewed integration and production runtime verification are complete.

## Current staging evidence

- Supabase migration history: 49 applied versions; latest 20261119182606.
- Public tables: 64/64 RLS enabled; policy correctness still requires table-by-table and role/tenant runtime validation.
- Public functions: 29; direct EXECUTE for anon/authenticated is 0; service_role has 29.
- Active tenant memberships: 3 across 3 identities; two active branch_manager memberships with orders, branches, inventory, POS, procurement and reports permissions; no Finance permission.
- One Owner profile exists, but auth.users.raw_app_meta_data.platform_owner is absent. It is not boolean true. No Auth mutation was performed.
- No 20261120 migration has been applied to shared staging.
- TENANT_ISOLATION_RELEASED=false and PUBLIC_TENANT_ROUTING_RELEASED=false.

## GitHub release protection — newly verified, not adequate

GitHub returns one active repository ruleset, ID 27559290, with a ref condition matching all branches. Its current effective configuration is insufficient:
- required approving review count: 0;
- required status checks: empty;
- required deployment environments/reviewers: empty;
- bypass actors include several repository roles/integrations with bypass_mode=always;
- current_user_can_bypass=always.
- Direct branch-protection reads for main and staging return HTTP 403 from the connected integration, so branch-specific effective protection cannot be independently confirmed.

The ruleset's existence must not be reported as successful release protection. It does not enforce the requested independent human approval, required CI, or staging deployment reviewers.

## Environment secrets and runtime acceptance

The staging workflow source references Tenant A/B username/password secrets and branch-code inputs. This only proves that names are referenced in YAML. The connected GitHub integration cannot read Environment secret metadata/values and does not expose a workflow_dispatch action. Therefore:
- A/B secret validity: NOT VERIFIED;
- staging workflow dispatch: NOT EXECUTED;
- P01–P09: NOT RUN;
- no claim of zero BLOCKED/SKIPPED runtime probes is allowed.

Do not paste secrets into chat or logs. An authorized repository maintainer must validate the Environment configuration and dispatch the workflow from the trusted staging branch.

## Next sequence

1. Authorized admin corrects ruleset: require at least one approval from someone other than the PR author, require the exact quality/security checks, remove inappropriate bypasses, and configure staging deployment reviewers.
2. Authorized GitHub maintainer verifies A/B Environment secret/fixture inputs without revealing values and dispatches Staging Tenant Isolation Acceptance from staging.
3. Authorized Supabase Auth Admin updates the existing Owner identity so app_metadata.platform_owner is boolean true, preserving other metadata, then reconciles the protected DLICE_PLATFORM_OWNER_USER_IDS allowlist.
4. Execute P01–P09 and the #114 supplemental probes. Require every probe to execute, zero BLOCKED/SKIPPED, and expected authorization outcomes.
5. Only then consider integration of #109/#111/#112 migrations in dependency order, one at a time, with backup/restore and disposable replay evidence.
6. Preserve #104 production CORS/source parity work as a separate main release gate.

No production mutation, shared-staging migration application, Auth metadata change, Edge Function deployment, or release-flag change was performed by this audit.
