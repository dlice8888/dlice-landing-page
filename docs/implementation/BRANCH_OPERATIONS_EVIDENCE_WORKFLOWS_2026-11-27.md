# Branch Operations — Concrete Persistence, Storage, UI & Workflows (2026-11-28)

## Candidate implementation delivered

Feature IDs: D08-F04, D08-F07, D08-F08, D08-F09, D08-F10.

### 1. Persistence and server adapter

- `docs/implementation/sql/BRANCH_OPERATIONS_CONCRETE_PERSISTENCE_DRAFT.sql` defines seven tenant/branch-scoped tables: equipment, tasks, evidence assets, incidents, maintenance work orders, compliance checks and compliance snapshots.
- All tables use composite `(tenant_id, branch_id)` foreign keys to `branches(tenant_id,id)`, scoped indexes, constraints and RLS.
- Direct `anon`/`authenticated` access is denied; service-role-only policies are used. The draft does not create a public bucket or browser Storage policy.
- RPCs enforce active tenant membership/branch assignment, approver separation, idempotency, valid state transitions and append-only audit records.
- Evidence metadata and published compliance snapshots have immutable update/delete triggers.
- Compliance source revision is derived server-side from the ordered approved check/evidence rows; an optional client-supplied revision is rejected if it does not match.

Server-only adapters:
- `src/branch-operations-supabase-repository.mjs`
- `supabase/functions/_shared/branch-operations-repository.ts`

Every mutation calls an atomic SQL RPC with server-derived tenant, branch and actor scope. Reads are tenant/branch scoped.

### 2. Private Storage verification

- Bucket: `branch-ops-evidence`, `public=false`, max 8 MB, MIME allowlist JPEG/PNG/PDF.
- Upload occurs only after bearer-token Auth validation, active tenant membership, active branch validation and branch assignment/tenant-admin authorization.
- The Edge Function checks file MIME and magic bytes, then writes to a server-generated path `tenant/branch/actor/uuid.ext`.
- SQL registration verifies private bucket state, object existence, path scope, MIME/size allowlist, owner and retention metadata.
- Incident, maintenance and compliance workflows validate evidence IDs against tenant, branch, owner, purpose and retention.
- Signed download URLs expire after 60 seconds and are created only after tenant/branch-scoped evidence metadata lookup.
- If metadata registration fails after upload, the Edge Function checks for an ambiguous committed row before deleting the object. It compensates an unregistered upload and reports a specific failure if cleanup itself fails.
- Evidence retention metadata defaults to 365 days. Automated expiry/purge scheduling remains a final operational task.

### 3. UI and authenticated Edge API

- UI: `src/branch-operations-ui.mjs`, imported by `erp.html`.
- Edge API: `supabase/functions/branch-operations/index.ts`.
- UI covers task assignment/status, incident reporting/evidence, equipment registration, maintenance work orders/evidence, compliance check submission/review, snapshot publication and evidence access.
- Edge API uses `auth.getUser(token)`, checks active `admin_profiles`, tenant membership, branch status and assignment/tenant-admin authorization before using its server-side service client.
- No service-role key is passed to or stored in browser code.
- The ERP mount is intentionally gated by `BRANCH_OPS_WORKFLOWS_RELEASED=false`. It remains disabled until the official migration, Edge deployment and tenant A/B acceptance are approved.

### 4. Workflow rules

- High/critical incidents create an escalation task; critical incidents require evidence.
- Task and maintenance transitions are restricted to the assignee or an approver.
- Incident status and compliance review require an approver; compliance review cannot be performed by the submitter.
- Maintenance evidence is verified and persisted with the work order.
- Compliance snapshots require all period checks to be approved and evidenced; the snapshot stores a deterministic source revision derived from the approved source rows.

## Tests and validation artifacts

- `tests/contracts/branch-operations-workflows.test.mjs`
- `tests/contracts/branch-operations-supabase-repository.test.mjs`
- `tests/contracts/branch-operations-persistence-sql-contract.test.mjs`

These cover RPC scope binding, evidence ownership, maintenance evidence, idempotency, immutable records, state transitions, private upload compensation, UI wiring and the release gate.

## Remaining acceptance gaps — not DONE

1. Generate the official migration with Supabase CLI from the reviewed draft and run disposable replay/pgTAP. The draft is not in `supabase/migrations`.
2. Deploy the Edge Function to staging only after approval; configure `DLICE_ALLOWED_ORIGINS` and verify its JWT gateway setting.
3. Create/verify the private bucket and Storage policies in staging; run authenticated upload, signed-download, expiry and orphan-compensation tests.
4. Run tenant A/B and branch A/B read/write denial tests against the actual staging function and database.
5. Run browser/tablet/device E2E for task, incident, maintenance and compliance flows.
6. Add automated evidence retention/purge operations and reconcile maintenance cost/work orders with Inventory, HR and Finance.
7. Compliance snapshot source revision currently fingerprints approved Branch Operations check/evidence rows. Cross-domain operational reconciliation (POS/Inventory/HR/Finance) still requires its own verified source adapters.

No staging or production database, Auth metadata, Storage bucket, Edge deployment, release flag, merge or release was changed in this candidate batch.


## Cross-domain maintenance cost close — candidate adapter

Added `src/branch-operations-costing-integration.mjs` and contract coverage in
`tests/contracts/branch-operations-costing-integration.test.mjs`.

- Cost close derives IDR values from persisted inventory issues, historically valued
  against approved GRNs/transfers/opening balances, approved HR labour entries and
  approved external costs on the work order. Client-supplied totals are not accepted.
- All source records must match tenant and branch; inventory, procurement and labour
  evidence must be reconciled/approved before a close can proceed.
- The close is idempotent and requires one tenant transaction for source reads,
  cost-close persistence, Finance journal posting, independent balanced-journal
  verification and audit append.
- The Finance adapter must post both sides and return an independently verified
  posted/balanced journal; a missing or unbalanced journal aborts the transaction.

**Not yet runtime accepted:** the repository-specific adapters that bind these
contracts to the canonical Inventory, Procurement, HR and Finance tables/RPCs
must be implemented and reviewed against their actual schemas. No new migration,
staging mutation, provider call or release was performed. This adapter is
candidate code and does not move D08 feature scores or mark Branch Operations DONE.
