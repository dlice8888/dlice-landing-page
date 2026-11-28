# Branch Operations schema readiness gate — 2026-11-28

## Scope

This change makes the authenticated Branch Operations Edge Function fail closed until all seven persistence tables are deployed. The server-side repository checks table availability before dispatching any workflow action. A missing table or PostgREST RPC is surfaced as an explicit deployment error; the Edge Function returns HTTP 503 rather than treating a missing schema contract as a business validation error.

## Canonical tables required

- `branch_ops_equipment`
- `branch_ops_tasks`
- `branch_ops_evidence_assets`
- `branch_ops_incidents`
- `branch_ops_work_orders`
- `branch_ops_compliance_checks`
- `branch_ops_compliance_snapshots`

## RPC parity review

The current SQL draft contains only these business RPC definitions:

- `branch_ops_create_task`
- `branch_ops_record_incident`

It also defines helper functions `branch_ops_assert_actor`, `branch_ops_assert_approver`, and the immutable-record trigger function.

The repository/Edge Function currently calls additional lifecycle, evidence-registration, and compliance RPCs (including `branch_ops_register_equipment`, `branch_ops_update_task_status`, `branch_ops_update_incident_status`, `branch_ops_update_work_order_status`, `branch_ops_create_maintenance_order`, `branch_ops_register_evidence_asset`, `branch_ops_submit_compliance_check`, `branch_ops_review_compliance_check`, and `branch_ops_publish_compliance_snapshot`). Those definitions are not present in the current draft. Therefore the draft is **not migration-ready** and must not be copied into `supabase/migrations` or applied to staging.

## Acceptance before official migration

1. Implement each missing RPC with exact parameter/return signatures matching the server adapter.
2. Validate referenced tables/columns and composite tenant/branch foreign keys against the current schema.
3. Validate Storage bucket privacy, MIME/size constraints, owner-scoped paths, retention and compensation behavior.
4. Validate RLS, grants and explicit function EXECUTE ACL for `anon`, `authenticated`, and `service_role`.
5. Add pgTAP coverage for state transitions, idempotency, cross-tenant and cross-branch rejection, approver separation, immutable evidence/snapshots and audit writes.
6. Generate the official timestamped migration using Supabase CLI on a disposable local stack, replay all repository migrations, and run the complete pgTAP suite.
7. Only after those checks pass may the migration be considered for staging approval. No staging or production mutation is authorized by this candidate.

## Runtime behavior

The Edge Function authenticates the bearer token and checks active tenant membership and branch assignment before it constructs the service-role repository. It now calls `assertReady()` before processing any action. Missing schema returns HTTP 503. No browser-side service-role access is introduced.

## Evidence boundary

The preflight and contract tests are source-level safeguards. They do not prove that the migration exists in staging, that Storage policies work, or that tenant A/B runtime isolation passes. Those remain open acceptance gates.
