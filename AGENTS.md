# D’Lice Engineering Operating Standard

This repository implements the D’Lice FnB Operating System (SaaS + ERP + POS) for a target of 150 branches. Apply the following engineering workflow to all non-trivial changes.

## Required delivery workflow

1. Clarify the business outcome, acceptance criteria, constraints, affected roles, branch/tenant boundaries, and operational impact before implementation. If behavior or scope is ambiguous, write a concise design note and obtain Owner direction before changing behavior.
2. Create a small implementation plan with explicit files, migration dependencies, tests, rollout and rollback considerations.
3. Use test-driven development where practical: add a focused regression, observe it fail, implement the smallest correct fix, then rerun it.
4. For defects, reproduce first and identify the root cause. Do not apply speculative patches or mask failures.
5. Review the complete diff for correctness, authorization, tenant isolation, data integrity, concurrency, idempotency, privacy, accessibility, performance and regressions.
6. Run the relevant static checks, tests, migration replay and runtime acceptance. Report exact commit, commands/workflow runs, pass/fail/blocked/skipped counts and limitations. Never claim a check passed unless the evidence exists for the exact commit.
7. Keep work isolated on a feature branch. Integrate one PR and one migration at a time after dependency and overlap reconciliation.
8. Treat source review, CI success, disposable migration replay, staging runtime acceptance and production release approval as distinct gates.

## D’Lice security and data constraints

- Tenant identity comes from authenticated Supabase Auth identity and active database membership; never trust caller-supplied tenant or branch UUIDs as authorization.
- Enforce tenant and branch access before querying or mutating data. Test both positive own-scope access and negative cross-tenant read/write attempts.
- Keep RLS enabled on every exposed public table. Revoke client EXECUTE from internal/trigger-only RPCs; do not add broad grants to solve permission failures.
- Keep CORS exact-origin and fail-closed. CORS is not authentication.
- Separate order, payment, fulfillment, kitchen and settlement state machines. Order creation is not proof of payment success.
- Preserve idempotency for offline replay, payment callbacks, POS submissions, stock movements and receiving.
- Keep immutable audit evidence for approvals, refunds, stock movement, inventory counts and financial reconciliation.
- Never put secrets, passwords, JWTs, service-role keys, raw user IDs or tenant/branch IDs in source control, artifacts or logs.
- Do not create or mutate Owner identities, Auth metadata, tenant memberships or branch assignments outside authorized administrative workflows.
- Do not apply migrations to shared staging until exact-head CI, disposable replay, dependency review and runtime release gates pass.
- Do not deploy Edge Functions, promote Vercel deployments, alter production aliases, or change production data without explicit release authorization.

## Quality and release expectations

- Validate POS → payment → KDS → recipe consumption → stock ledger → offline replay → shift close → reporting as one reconciled flow.
- Validate procurement PR → approval → PO → GRN/receipt → stock movement → AP reconciliation.
- Validate finance settlement, refund, cash reconciliation and journal controls against source transactions.
- Validate role and tenant boundaries with two real, distinct staging Auth identities. Required probes must execute; zero BLOCKED/SKIPPED is mandatory for acceptance.
- Test backups and restore, observability, load and failure recovery at staged scale through 150 branches.
- Preserve the PRD's 18 domains and 189-feature matrix. A feature is not PASS solely because a route, component, table, migration or static contract exists; require end-to-end evidence appropriate to the feature.
