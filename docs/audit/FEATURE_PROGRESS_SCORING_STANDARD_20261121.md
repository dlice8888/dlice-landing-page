# D’Lice feature progress scoring standard — 21 November 2026

## Why percentages are not copied from the old estimates

A feature marked PARTIAL only means that some implementation evidence exists. It does not mean that the feature is 50%, 70%, or any other fixed percentage complete. Historical domain estimates in the original PRD register are not current acceptance scores.

## Weighted evidence model

| Acceptance dimension | Weight |
|---|---:|
| Code and UI implementation | 20% |
| Database integrity and migrations | 20% |
| Authorization and tenant/branch scope | 15% |
| Automated contract and unit tests | 15% |
| End-to-end browser or API workflow | 20% |
| Operational reconciliation and observability | 10% |
| **Total** | **100%** |

For each feature, each dimension is split into explicit pass/fail acceptance criteria. A dimension earns its weight only when a current evidence artifact (commit/PR, migration/test, CI run, runtime trace, screenshot, or reconciled database query) demonstrates that criterion. A BLOCKED or SKIPPED test earns zero for that criterion.

## Status transitions

- NOT VERIFIED → PARTIAL: a concrete implementation task/PR has started and evidence is linked; this is not acceptance.
- PARTIAL → DONE: 100% weighted score, every required workflow passes, code and database checks pass, no BLOCKED/SKIPPED, and independent review/release gates pass where required.
- BLOCKED remains visible while an external prerequisite prevents execution. Track its work status separately (e.g. IN_PROGRESS or EXTERNAL_ACTION_REQUIRED).

## Current snapshot — live audit 21 November 2026

- 189 PRD features across 18 domains.
- **89 PARTIAL, 91 NOT VERIFIED, 9 BLOCKED.** The 18 domain rows supplied in the latest request originally sum to 82/98/9; the total-row value 93 NOT VERIFIED is incorrect. Two SaaS features began concrete implementation in PR #126, and five more features were reclassified after live schema/function evidence confirmed existing foundations. Current count is 89/91/9.
- Tenant/member isolation = **38%** (3 code/UI + 15 database + 5 authorization + 15 automated tests; 0 browser/API E2E; 0 operational reconciliation).
- Tenant directory/onboarding = **30%** (5 code/UI + 10 database + 5 authorization + 10 automated tests; 0 browser/API E2E; 0 operational reconciliation).
- The other **87 PARTIAL features are not yet assigned a defensible numeric score**. Their foundations are evidenced, but each must be decomposed into the six weighted dimensions above before percentages are published. Do not substitute a domain-level estimate or invent 0%/50%/100%.
- PR #126 exact-head disposable migration replay and quality suite pass; invitation lifecycle adds 15 pgTAP assertions. Real Tenant A/B runtime remains unproven.
- PR #120 is under remediation: the ERP authorization coverage contract now passes; the migration replay then exposed orphaned SQL fragments after `COMMIT` in `20261121160000_atomic_admin_profile_mutation_audit.sql`. Those 22,067 trailing characters were removed, and 11 pgTAP assertions were added for audited invitation issuance. Exact-head quality and disposable replay are queued on `29d6d808`; do not accept until both pass.
- PR #124 application-layer breached-password guard passes CI, but native Supabase leaked-password protection remains disabled and direct Auth bypass remains unresolved.
- Two staging positive-path E2E workflows (Procurement and KDS/POS/Stock/Offline) are BLOCKED at credential preflight; missing Owner username/password and Branch A username prevented business steps from executing.

## Non-negotiable reporting rule

Never count a code artifact, schema/table, green build, preview deployment, negative-only authorization test, or an unexecuted/blocked/skipped workflow as feature completion. Every DONE claim must point to the passing evidence for all required dimensions.
