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
- PARTIAL → DONE: 100% weighted score, every required workflow passes, code and database checks pass, no BLOCKED/SKIPPED, and all defined automated and runtime test gates pass and deployment authorization gates are satisfied.
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


## Current scoring evidence delta — 21 November 2026, 19:42 WIB

- Feature counts remain 189 total: 89 PARTIAL, 91 NOT VERIFIED, 9 BLOCKED, 0 DONE.
- Tenant/member isolation remains 38%; Tenant directory/onboarding remains 30%. The exact-head PR #126 disposable replay and invitation suite PASS, but live P01–P09 and invitation browser/API E2E have not run, so no additional E2E or reconciliation weight is earned.
- PR #120 permission mutation contract and disposable replay PASS, but live positive/negative mutation-path tests are absent. Password reset's Auth update and audit insert remain separate; do not mark permission/security features DONE.
- PR #123/#125/#127 exact-head contract and disposable replay PASS. Browser fault-injection, concurrent retry, expiry worker, Storage compensation, payment reconciliation and order/payment/reservation E2E are NOT RUN; no completion weight is earned for those dimensions.
- PR #124's five password-guard artifacts are identical to PR #120's and the guard is included in #120's Edge Function. Do not double-count #124 as separate implementation progress.
- No numeric score is added for the other 87 PARTIAL features; their criteria still need evidence decomposition. BLOCKED/SKIPPED/NOT RUN remain zero for the affected acceptance dimension.


## Test-only acceptance policy — effective 21 November 2026

Feature acceptance is based only on reproducible, machine-verifiable evidence:

1. **Build and static checks:** every required workflow for the exact head SHA completes successfully; lint, typecheck, formatting, security/static analysis and build have zero failures.
2. **Changed-code coverage:** line and branch coverage is at least 80% for changed production code and at least 90% for changed authorization, tenant-boundary, payment and mutation-critical code. Any uncovered security decision branch must have an explicit negative/positive test or remains NOT VERIFIED.
3. **Database:** replay all candidate migrations from an empty disposable database; every migration and pgTAP test passes; schema/RPC grants, RLS and indexes match expected state; zero migration-version collisions and zero applied/source drift in the candidate set.
4. **Authorization:** run positive and negative tests for each role and tenant. Every cross-tenant read/write attempt must be rejected; every permitted same-tenant action must succeed; audit mutation and business mutation must commit or roll back atomically.
5. **P01–P09:** execute all nine probes against the two existing Supabase Auth identities. Required result is 9/9 executed, 9/9 expected outcomes, 0 BLOCKED, 0 SKIPPED, 0 inconclusive. Capture status, actor, tenant, branch, request correlation ID and assertion result; never log secrets or magic-link tokens.
6. **Business E2E:** execute the exact scenario matrix for checkout retries/concurrency, pending and late payment, expiry, proof upload/retry, compensation, supersession, reservation lifecycle, KDS, recipe consumption, stock movement/transfer/opname and procurement PR→PO→GRN. Each scenario records setup, action, expected result, actual result and persisted DB evidence.
7. **Reconciliation:** verify order/payment/reservation, stock ledger/on-hand, recipe consumption, procurement/GRN/AP, shift/cash and finance totals. Invariants must match exactly; unexplained variance is a failure.
8. **Reliability and performance:** inject timeout, duplicate delivery, retry, concurrent requests and worker restart where applicable. Record p50/p95/p99, error rate and recovery behavior against the approved workload baseline; missing measurements remain NOT VERIFIED.
9. **Completion rule:** all applicable checks PASS on the exact candidate SHA; no BLOCKED/SKIPPED/NOT RUN acceptance cases; database and runtime state reconciles; evidence links and timestamps are stored. Only then may a feature become DONE/100%.

**Release controls are separate from PR review:** protected staging Environment, secret handling, authorized workflow dispatch, backup/rollback and explicit staging/production mutation authorization remain mandatory. This policy does not disable those controls, weaken branch/deployment protection, or authorize automatic merge/deploy.
