# Branch Operations — Evidence Workflows (2026-11-27)

## Scope started in this batch

Feature IDs:
- D08-F04 — Daily tasks, due dates and escalation.
- D08-F07 — Photo/evidence references.
- D08-F08 — Incidents and corrective actions.
- D08-F09 — Equipment maintenance.
- D08-F10 — Branch audit and compliance score.

## Implemented source boundary

`src/branch-operations-workflows.mjs` adds transactional orchestration for:
1. Branch task creation with active same-branch assignee validation and durable idempotency.
2. Incident capture with mandatory evidence for critical severity and durable escalation tasks for high/critical severity.
3. Preventive/corrective/inspection work orders against a verified non-retired branch asset.
4. Compliance snapshot publication only when all approved checks are complete, evidence references are present, and source reconciliation is passed.

Every write requires:
- a tenant transaction,
- authorization inside that transaction,
- same-tenant/same-branch repository reads,
- durable idempotency,
- append-only audit.

Evidence references are opaque private-storage references. A concrete repository adapter must verify object ownership, MIME/type, retention and branch scope before persistence. The orchestration layer does not accept caller-asserted evidence contents as proof.

## Tests added

`tests/contracts/branch-operations-workflows.test.mjs` covers:
- successful branch task write,
- cross-branch assignee denial,
- idempotent duplicate prevention,
- critical incident evidence and escalation,
- missing critical evidence rejection,
- retired equipment rejection,
- incomplete/unreconciled compliance rejection,
- complete compliance snapshot publication.

## Remaining gaps — not DONE

This batch deliberately does not claim database or runtime acceptance. Still required:
- canonical Supabase migration created through Supabase CLI, with tenant/branch FKs, constraints, RLS, private Storage policy and audit triggers;
- repository adapter implementing every port with server-side identity and same-tenant/branch predicates;
- authenticated Edge Function routes and explicit authorization for each action;
- ERP/mobile UI for task assignment, incident reporting, photo capture, work orders and audit review;
- staging tests with tenant A/B and branch A/B, including cross-tenant and cross-branch read/write denial;
- evidence retention/deletion policy and private Storage verification;
- E2E reconciliation to inventory, HR/maintenance costs and Executive reporting.

No production or staging database was modified. No release flag was changed.
