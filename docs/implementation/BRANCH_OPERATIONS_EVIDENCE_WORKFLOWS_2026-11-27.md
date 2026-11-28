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


## Concrete persistence/API/UI implementation batch — 2026-11-28

Candidate-only artifacts added after the initial orchestration layer:

- `docs/implementation/sql/BRANCH_OPERATIONS_CONCRETE_PERSISTENCE_DRAFT.sql`
  - Tenant/branch-keyed equipment, tasks, evidence metadata, incidents, maintenance work orders, compliance checks and immutable compliance snapshots.
  - Composite tenant/branch foreign keys, idempotency uniqueness, state/weight constraints and RLS enabled on every new public table.
  - Browser roles receive no table privileges. Database mutation RPCs are revoked from PUBLIC/anon/authenticated and granted only to service_role.
  - Private `branch-ops-evidence` bucket with 8 MiB and MIME restrictions. No direct browser Storage policy is added: uploads are accepted only by the authenticated Edge Function after actor, tenant membership and branch assignment checks. The server registers ownership, scope, purpose and 365-day retention metadata.
  - Atomic RPCs: task creation, incident + escalation, maintenance order, evidence registration, compliance check submission, independent compliance review and compliance snapshot publication. Every write appends `admin_audit_logs` within the same SQL transaction.
- `supabase/functions/_shared/branch-operations-repository.ts`: scoped server repository; writes use one atomic RPC each, reads always filter tenant_id and branch_id.
- `supabase/functions/branch-operations/index.ts`: new Edge API; explicit bearer-token `auth.getUser`, active admin profile, active tenant membership, active branch and branch assignment/tenant-admin permission before using service-role persistence. Evidence MIME signatures and 8 MiB cap are checked server-side. Intended deployment setting is `verify_jwt=true`.
- `src/branch-operations-ui.mjs`: ERP workflow UI for tasks, incident capture/evidence, equipment work orders, compliance submissions/reviews and snapshots.
- `erp.html`: UI mount point wired to the Operations view, but `BRANCH_OPS_WORKFLOWS_RELEASED=false` remains enforced until the official migration, Edge deployment and tenant A/B acceptance are approved.
- Contract tests and CI steps added for adapter scope, persistence/RLS/Storage contracts, UI release gate, Node syntax and Deno type checking.

### Important acceptance boundary

This is implementation source, not a completed integration release:
- The SQL is a reviewed candidate draft, not an official Supabase CLI-generated migration. It has **not** been applied to staging or production.
- The new Edge Function has **not** been deployed to staging; the existing `dlice-orders` function was not modified.
- ERP UI remains behind a false release flag.
- No live database adapter call, Storage upload, Auth/ACL negative test, browser/device E2E, or tenant A/B runtime test has been executed against staging.
- The existing `branch_ops_*` tables and RPCs are therefore not present in staging at this checkpoint. The adapter will fail closed until the approved migration exists.
- Contract tests authored in this batch are pending exact-head CI results. Feature scores remain unchanged until the new code is tested and runtime evidence exists.

### Security decisions

The candidate deliberately does not add a Storage RLS policy that queries `tenant_memberships` or `branch_assignments`: staging currently denies direct authenticated reads on both tables, so such a policy would fail closed for legitimate users. The bucket remains private with no direct client Storage policy; the Edge Function performs authorization and uploads using its server-only service client. The service-role key never enters ERP/browser code. The new function is configured for JWT verification at deployment and independently validates the bearer token with Auth.

No staging migration, Edge deployment, merge, production mutation, or release flag change was performed.
