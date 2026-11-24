# Atomic tenant invitation lifecycle — 21 November 2026

## Scope
The tenant invitation routes in `supabase/functions/dlice-orders/index.ts` previously wrote the invite, membership state and audit trail through separate PostgREST requests. A failure between requests could leave an invitation without its audit record or a membership active while the invite remained pending.

## Change
Migration `20261124121105_atomic_tenant_invite_lifecycle.sql` introduces two service-role-only RPCs:

- `dlice_create_tenant_invite_atomic`: validates the actor's active `tenant_owner`/`tenant_admin` membership, validates email/role/token/expiry, rejects an existing pending invite, and inserts the invite plus audit row in one transaction.
- `dlice_accept_tenant_invite_atomic`: locks the invite row, checks pending status, expiry and exact invited email, creates the active membership, consumes the invite and writes the audit row in one transaction. Concurrent or replayed acceptance cannot consume the same invite twice. Expired invites are marked expired and audited without granting membership.

The Edge Function now calls these RPCs rather than issuing multiple writes. Both issue and accept remain explicitly fail-closed with HTTP 423 until tenant isolation release is authorized. Invite delivery remains manual-copy only; no paid email provider is introduced.

## Validation
- 15 pgTAP assertions cover valid invite creation, authorization denial, email mismatch, acceptance, membership role/status, one-time consumption, replay rejection, expiry persistence and audit records.
- Source-contract tests assert the Edge Function uses the atomic RPCs and does not perform direct multi-write operations.
- Disposable full migration replay and all quality checks must pass on the exact PR head before this change is treated as validated.

## Safety
No shared staging migration, production migration, Edge Function deployment, Auth user mutation, cron activation or release-flag change is part of this PR.
