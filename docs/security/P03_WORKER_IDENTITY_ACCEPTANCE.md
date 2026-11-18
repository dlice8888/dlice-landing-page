# P03 Worker Identity Probe — Acceptance Rules

**Status:** Candidate test refinement; not runtime evidence.

- Two distinct Auth users must match the configured canonical user IDs.
- Each user must have an active membership in its own configured tenant and no membership in the other test tenant.
- Both tenant membership roles must be `branch_manager`.
- Both linked global profile classifications must be `branch_worker`; `sales_admin` and `owner` do not satisfy the ordinary-worker fixture.
- Both active tenant permission arrays must be non-empty and equal after sorting.
- The configured QA branch must be visible and actively assigned to each user. Additional same-tenant branches are allowed; the other tenant's configured branch must not be visible.
- Cross-tenant assignment anomalies are separately checked from the authoritative staging assignment inventory.
- Runtime evidence masks user, tenant, and branch identifiers. It records HTTP status, timestamp, permission counts, workflow run ID and commit SHA. Tokens, passwords, full UUIDs and raw response bodies are never logged.

The previous exact-one-visible-branch assertion was too strict: the acceptance requirement is an active valid assignment and no unnecessary cross-tenant assignment, not exactly one same-tenant branch.
