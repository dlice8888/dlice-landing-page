# D’Lice test-only PR acceptance policy

**Effective:** 21 November 2026  
**Scope:** All D’Lice pull requests, feature gates, migration candidates and 18-domain regression.

## 1. Acceptance principle

A separate independent PR-review/approval step is not required by the D’Lice project execution policy. Reviewer assignment, reviewer identity and approval count are not feature-completion metrics. A PR advances only when its exact candidate commit passes the measurable test matrix below.

This policy does not disable GitHub branch/deployment protection, staging Environment controls, secret handling, explicit mutation authorization, backup/rollback requirements or production release gates.

## 2. Required measurable test evidence

| Gate | Required evidence | PASS threshold |
|---|---|---|
| Exact-head CI | Build, lint, typecheck, static/security checks, contract suites | 100% required jobs PASS on exact head SHA |
| Changed-code coverage | Line + branch coverage for changed production code | ≥80% overall; ≥90% for auth, tenant, payment and mutation-critical code |
| Database | Empty disposable DB migration replay + pgTAP | 100% migrations and DB assertions PASS; zero version collision; zero unexplained schema drift |
| Authorization | Role × tenant × branch positive/negative matrix | Every expected allow succeeds; every forbidden read/write is denied; no uncovered security branch |
| P01–P09 | Existing Supabase Tenant A/B identities | 9/9 executed, 9/9 expected outcomes, 0 BLOCKED, 0 SKIPPED, 0 inconclusive |
| Mutation atomicity | Business mutation + audit mutation + forced audit failure | Commit together; forced audit failure rolls back business mutation; exactly one expected audit record |
| Business E2E | Checkout, payment, reservation, Kitchen, inventory, procurement, finance | Every applicable scenario executed and passed, with persisted database evidence |
| Fault injection | Timeout, duplicate, concurrency, retry, worker restart, partial Storage/DB failure | Idempotent result; no duplicate business record; compensation and recovery invariants pass |
| Reconciliation | Order/payment/reservation, stock, recipe, procurement/AP, cash/finance | Exact invariant match; zero unexplained variance |
| Reliability/performance | p50/p95/p99, error rate, throughput, recovery | Measurements recorded against approved workload baseline; missing measurement is NOT VERIFIED |

## 3. Tenant isolation acceptance

P01–P09 must use the two existing Supabase Auth accounts. Do not create users or reset passwords to satisfy the tests. Test:
- Tenant A and Tenant B authenticate as distinct identities.
- Each reads/writes only its own authorized tenant/branch data.
- Each cross-tenant read and write is denied.
- API/Edge Function, direct database/RLS, Storage, cache and background-job boundaries are included where applicable.
- The test artifact records actor, tenant, branch, request correlation ID, expected result, actual result and execution status.
- Never log passwords, service-role keys, magic-link tokens or session tokens.

## 4. PR state transitions

- **NOT VERIFIED → PARTIAL:** implementation has started and a concrete artifact exists, but one or more applicable test dimensions are not yet proven.
- **PARTIAL → DONE / 100%:** every applicable gate above passes on the exact candidate SHA, persisted data reconciles, and no BLOCKED/SKIPPED/NOT RUN acceptance case remains.
- **BLOCKED:** a required capability or safe test path is unavailable. Do not convert BLOCKED to PASS by treating a skipped test as success.
- **Regression:** any previously passing gate that fails returns the affected feature to PARTIAL or BLOCKED until repaired and rerun.

## 5. Separate release controls

The following remain mandatory and are not PR-review steps:
- Verify protected GitHub Environment and secret availability without exposing secret values.
- Use authorized workflow dispatch for shared staging mutations.
- Complete disposable replay, backup/restore and rollback planning before staging migration.
- Obtain explicit staging mutation authorization before applying a migration or deploying an Edge Function.
- Keep tenant-isolation/public-routing release flags false until their runtime acceptance gates pass.
- No production mutation or release without the designated release authorization.

## 6. Evidence format

Every test result must record:
1. Repository, PR, branch and exact commit SHA.
2. Test suite/scenario ID and test environment.
3. Fixture identity/tenant/branch identifiers (non-secret).
4. Setup and action.
5. Expected and actual result.
6. PASS/FAIL/BLOCKED/SKIPPED/NOT RUN status.
7. Persisted database assertion or trace/correlation reference.
8. Start/end timestamp and runtime measurements where applicable.

A summary status without raw test evidence is not sufficient to mark a feature DONE.
