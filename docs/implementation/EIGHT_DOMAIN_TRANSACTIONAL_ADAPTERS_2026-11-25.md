# Eight-domain transactional workflow adapters

This branch adds application orchestration boundaries on top of the pure domain
kernels in the parent workflow-kernel branch. It deliberately does not claim
that a domain is production-ready or that a staging database migration has run.

## Required adapter contract

Every database-backed operation must provide:

- `withTenantTransaction(scope, callback)`: one database transaction; callback
  must receive a transaction-bound repository context and commit only if it
  resolves successfully.
- `authorize(tx, actorScope)`: server-side authorization executed inside that
  transaction, not a client-provided role check.
- `appendAudit(tx, event)`: append-only audit event in the same transaction.
- Tenant/branch-scoped reads with row locks for mutable aggregates.
- Unique database constraints for each idempotency key; application-level
  lookup alone is not sufficient under concurrency.
- Repository writes that either commit all state changes or roll them all back.

A missing adapter fails closed. Never replace a missing adapter with an in-memory
store, a client-side authorization check, or a best-effort write.

## Implemented orchestration boundaries in this branch

| Domain | Service | Transaction boundary |
|---|---|---|
| CRM | `awardLoyaltyForFinancialClose`, `dispatchApprovedCampaignMessage`, `ingestSignedCampaignReceipt`, `ingestSignedCampaignUnsubscribe`, `calculateReconciledCampaignRoi` | Reconciled source close, idempotent ledger + balance, consent-gated provider outbox, signed receipt and unsubscribe persistence, tenant/provider-scoped event dedupe, and reconciled ROI |
| HR / Finance | `persistApprovedPayrollRun`, `executeApprovedPayrollPayment`, `reconcileApprovedPayrollPayment` | Approved run, open fiscal period, immutable lines, balanced draft journal, payment intent and settlement reconciliation |
| Delivery | `ingestSignedDeliveryWebhook` | HMAC verification, event dedupe, dispatch update, audit |
| Franchise | `provisionApprovedFranchise` | Signed effective contract, 10 independently verified gates, territory check, atomic tenant/branch provisioning |
| BI | `ingestReconciledKpiSnapshot` | Published formula, Finance facts, source reconciliation, lineage, immutable snapshot |
| SaaS | `meterCommittedTenantOperation` | Meter only after authoritative operation commit; durable retry remains an adapter responsibility |
| Procurement | `executeApprovedSupplierPayment`, `reconcileApprovedSupplierSettlement` | Payment intent in transaction, provider call outside transaction, persisted result, later settlement reconciliation |
| Executive | `readAuthorizedExecutiveDrilldown` | Authorization at each hierarchy node and Finance-reconciled source transaction read |

### CRM campaign unsubscribe workflow increment

Added `ingestSignedCampaignUnsubscribe`. It requires a provider-specific raw-body
signature verifier, resolves the customer and consent from trusted server-side
provider context, rejects provider-event ID collisions, appends the consent
withdrawal, suppresses queued recipients and persists the provider event in one
tenant transaction. Provider-event lookup is explicitly scoped by provider and
tenant. No live provider is configured and no unsubscribe webhook is deployed.

### CRM reconciled-close award and persistence extension

Added the companion draft
`docs/implementation/sql/CRM_LOYALTY_ADAPTERS_EXTENSION_DRAFT.sql` after
reconnaissance confirmed the current staging schema has POS sales, orders,
shifts, cash reconciliations, payment settlements, refunds and journal entries,
but does not expose a complete settlement-reconciliation or Finance-source-
reconciliation entity. The extension defines the missing durable CRM contracts:
versioned earning rules, immutable close projections, campaign outbox,
provider-event dedupe, Finance-backed campaign attribution and campaign costs.

The new `crm_award_loyalty_for_reconciled_close` RPC is fail-closed. It requires
an existing reconciled close projection, approved shift reconciliation,
reconciled settlement evidence, posted/reconciled Finance journal plus source
reconciliation, complete processed-refund evidence, a tenant-scoped customer
link and an approved earning rule. It calculates eligible net sales after
discounts and refunds and writes one idempotent ledger award plus audit event.

The extension also adds database triggers for paid online orders and paid
POS sales. When a branch and valid Indonesian/international phone identity are
present, the trigger resolves or creates the tenant customer and records the
source link through `crm_link_transaction_customer`. Missing/invalid identity
is left unlinked for manual verification; it does not block checkout. These
triggers do not award points.

The Edge Function action `erp-crm-award-reconciled-close` now routes to this
RPC and remains Platform Owner-only while tenant isolation is unreleased.
**The projection builder is not yet wired to source Finance/settlement records**:
the current staging schema lacks the full source-reconciliation entities needed
to prove that projection. The draft SQL has not been applied, and no points were
awarded in staging. This is a code/schema contract increment, not runtime proof.

### CRM POS/order identity adapter increment

The existing `erp-crm-link-paid-transaction` action in
`supabase/functions/dlice-orders/index.ts` previously performed customer
lookup/create, transaction-link insert, customer promotion and audit as
separate REST writes. It now delegates those related writes to the single
`crm_link_transaction_customer` database RPC contract in the CRM schema draft.
The RPC validates tenant/branch ownership, resolves or locks the customer,
enforces a single customer link per source transaction, handles duplicate
requests idempotently, promotes prospects and writes the link audit record in
one transaction. The Edge Function still verifies the source order/POS sale,
branch ownership and phone identity before calling it.

This closes the non-atomic identity-link adapter boundary for both
`online_order` and `pos_sale`. It does **not** automatically award points:
the financial-close projection still requires approved shift close, reconciled
settlement, posted/reconciled Finance source batch and complete processed
refund evidence. The action remains Platform Owner-only while the tenant
isolation release gate is closed. The SQL remains a design draft and has not
been applied; therefore runtime integration is not yet verified.

## Still required before any domain can be marked DONE

1. Implement concrete Supabase repository adapters and RPCs for every named port.
2. Add database-enforced unique constraints, foreign keys, tenant isolation and RLS
   for the new entities. These are intentionally not applied in this branch.
3. Wire the services into authenticated Edge Function routes and UI workflows.
4. Complete campaign dispatch provider selection, provider receipt webhook,
   durable unsubscribe RPC/adapter wiring, retries and ROI attribution.
5. Complete payroll payment-provider execution, payroll reversal and bank
   settlement reconciliation.
6. Complete delivery quote/booking adapters, approved provider contract,
   private Storage upload policy/UI, retry/compensation, COD and actual-cost
   reconciliation.
7. Complete franchise due-diligence evidence, contract signature verification,
   renewal/closure and royalty payment settlement.
8. Complete BI scheduled ingestion, freshness alerting and KPI formula review.
9. Complete SaaS invoice/payment settlement, API-wide entitlement enforcement,
   suspend/reactivate, export/retention and deletion evidence.
10. Complete Procurement invoice intake, return/credit-note lifecycle and AP
    balanced posting before payment.
11. Complete Executive 150-branch ranking, target-vs-actual and alert workflow
    on top of verified Finance facts.
12. Run static checks, unit/contract tests, disposable migration replay, pgTAP,
    Edge Function type checks, staging P01-P09 and E2E only in the final
    validation batch, as requested.

## Operational guardrails

- No production database, credentials, deployment or data changes.
- No migration execution, PR merge, release flag changes or protection changes.
- Keep `TENANT_ISOLATION_RELEASED=false` and
  `PUBLIC_TENANT_ROUTING_RELEASED=false`.
- Never claim provider acceptance, payment execution, delivery, reconciliation,
  provisioning or usage metering without persisted authoritative evidence.


The existing `erp-crm-link-paid-transaction` action in
`supabase/functions/dlice-orders/index.ts` previously performed customer
lookup/create, transaction-link insert, customer promotion and audit as
separate REST writes. It now delegates those related writes to the single
`crm_link_transaction_customer` database RPC contract in the CRM schema draft.
The RPC validates tenant/branch ownership, resolves or locks the customer,
enforces a single customer link per source transaction, handles duplicate
requests idempotently, promotes prospects and writes the link audit record in
one transaction. The Edge Function still verifies the source order/POS sale,
branch ownership and phone identity before calling it.

This closes the non-atomic identity-link adapter boundary for both
`online_order` and `pos_sale`. It does **not** automatically award points:
the financial-close projection still requires approved shift close, reconciled
settlement, posted/reconciled Finance source batch and complete processed
refund evidence. The action remains Platform Owner-only while the tenant
isolation release gate is closed. The SQL remains a design draft and has not
been applied; therefore runtime integration is not yet verified.

## Still required before any domain can be marked DONE

1. Implement concrete Supabase repository adapters and RPCs for every named port.
2. Add database-enforced unique constraints, foreign keys, tenant isolation and RLS
   for the new entities. These are intentionally not applied in this branch.
3. Wire the services into authenticated Edge Function routes and UI workflows.
4. Complete campaign dispatch provider selection, provider receipt webhook,
   durable unsubscribe RPC/adapter wiring, retries and ROI attribution.
5. Complete payroll payment-provider execution, payroll reversal and bank
   settlement reconciliation.
6. Complete delivery quote/booking adapters, approved provider contract,
   private Storage upload policy/UI, retry/compensation, COD and actual-cost
   reconciliation.
7. Complete franchise due-diligence evidence, contract signature verification,
   renewal/closure and royalty payment settlement.
8. Complete BI scheduled ingestion, freshness alerting and KPI formula review.
9. Complete SaaS invoice/payment settlement, API-wide entitlement enforcement,
   suspend/reactivate, export/retention and deletion evidence.
10. Complete Procurement invoice intake, return/credit-note lifecycle and AP
    balanced posting before payment.
11. Complete Executive 150-branch ranking, target-vs-actual and alert workflow
    on top of verified Finance facts.
12. Run static checks, unit/contract tests, disposable migration replay, pgTAP,
    Edge Function type checks, staging P01-P09 and E2E only in the final
    validation batch, as requested.

## Operational guardrails

- No production database, credentials, deployment or data changes.
- No migration execution, PR merge, release flag changes or protection changes.
- Keep `TENANT_ISOLATION_RELEASED=false` and
  `PUBLIC_TENANT_ROUTING_RELEASED=false`.
- Never claim provider acceptance, payment execution, delivery, reconciliation,
  provisioning or usage metering without persisted authoritative evidence.


## HR/Finance persistence schema increment

Read-only inspection of staging found no `hr_*` payroll tables and no
multi-line Finance journal batch/line model. The existing
`finance_journal_entries` table is a legacy single-row debit/credit record and
is not sufficient to persist the immutable payroll journal produced by the
domain kernel.

Added `docs/implementation/sql/HR_PAYROLL_FINANCE_SCHEMA_DRAFT.sql` with
tenant/branch-scoped employee and effective payroll profiles, immutable
payroll run lines, Finance journal batches/lines, payment batches/items and
Finance source reconciliation records. The new
`hr_persist_approved_payroll_run` RPC validates an approved run, an open fiscal
period, immutable line totals and balanced debit/credit lines, then persists a
draft Finance batch and audit record atomically. It does not post or pay payroll.
The draft has not been applied; payroll calculation inputs, journal approval/
posting, payment provider execution and settlement reconciliation still need
their concrete adapters and lifecycle routes.


## Delivery persistence schema increment

Added `docs/implementation/sql/DELIVERY_PROVIDER_STORAGE_SCHEMA_DRAFT.sql`.
It defines tenant/branch-scoped provider quotes, dispatch bookings, signed
provider-event dedupe, private Storage evidence metadata, COD/courier-cost
reconciliation and a retryable delivery outbox. The draft expects a private
`delivery-private` Storage bucket and server-side uploads only; it grants no
client upload path. Provider quote/booking execution, webhook route wiring,
Storage bucket provisioning and actual COD/Finance settlement adapters remain
outstanding. No provider credentials were configured and no Storage bucket or
database schema was changed in staging.


## 2026-11-25 implementation continuation

The branch now adds the following fail-closed orchestration entry points on top
of the domain kernels:

- CRM: `buildCrmFinancialCloseProjection` loads POS/order, processed refunds,
  approved shift close, reconciled settlement and posted Finance evidence through
  server adapters before creating an immutable projection.
- HR: `calculateAndPersistPayrollRun` calculates immutable payroll lines only
  from active scoped employees, approved time, effective approved compensation
  and explicit payroll components.
- Delivery: `requestDeliveryQuotes` and `bookDeliveryDispatch` require approved
  provider adapters, persist quote/booking intent before claiming completion,
  and leave ambiguous provider responses pending reconciliation.
- Franchise: `createReconciledFranchiseRoyaltyStatement` requires an effective
  signed agreement and reconciled net-sales/Finance close.
- BI: `runScheduledBiKpiIngestion` executes governed KPI definitions and
  persists per-metric failures; it does not silently omit failed sources.
- SaaS: `enforceSaasTenantEntitlement` checks active subscription, plan
  entitlement and committed usage in a tenant transaction;
  `issueSaasSubscriptionInvoice` requires an approved tax decision, including
  an explicit zero-tax decision.
- Procurement: `postMatchedSupplierInvoiceToApJournal` creates only a balanced
  AP journal draft after independent invoice approval and an open fiscal period.
- Executive: `publishExecutiveBranchRanking` requires the complete authorized
  active branch set (1–150) and Finance-reconciled snapshots plus approved targets.

The delivery schema extension was reconciled with the existing baseline draft:
it no longer attempts to recreate the already-defined
`delivery_dispatches` or `delivery_provider_events` tables. It extends the
existing dispatch lifecycle, adds tenant/branch-scoped provider configuration
and quotes, hashed private Storage evidence metadata, cost reconciliation and
retry outbox. Manual booking now requires an active, independently approved
provider configuration. Provider API credentials are referenced by environment
secret name only; secret values are never stored in the database or returned.

The delivery proof upload route now hashes uploaded bytes, persists metadata
against the dispatch, and removes the uploaded object if metadata or audit
persistence fails. The bucket contract remains private
(`delivery-proof`); no client upload policy is granted.

Static source review also corrected PostgreSQL dollar-quote delimiters in the
CRM, HR, Delivery, Franchise, BI, SaaS, Procurement and Executive SQL drafts,
and corrected the BI publication watermark comparison to use the actual
`max_source_updated_at` column.

### Remaining integration gates

These increments are source-level implementations and adapter contracts, not
end-to-end completion. The following still need concrete Supabase adapters,
authenticated UI/API wiring where noted, and provider-specific contracts:

1. Wire the new CRM close-projection builder to actual staging source records
   and reconcile the SQL projection columns with the Finance/settlement source
   model.
2. Wire payroll calculation inputs, approval/posting and payroll provider
   execution/webhook settlement.
3. Configure and approve a real delivery provider before API quote/booking or
   signed webhook execution; add the signed provider event RPC/endpoint and COD
   Finance reconciliation. No provider is claimed configured.
4. Complete franchise agreement signature/version lifecycle, tenant/branch
   provisioning adapter and royalty invoice/payment settlement.
5. Implement BI source ingestion workers, approved metric formulas and target
   aggregation adapters; current runner is orchestration only.
6. Implement SaaS invoice payment provider execution, signed receipt processing,
   renewal/grace-period enforcement and route-wide entitlement checks.
7. Complete Procurement supplier invoice intake/attachment, credit-note/return
   lifecycle, Finance posting adapter and payment provider settlement.
8. Wire Executive ranking persistence, target-vs-actual views, KPI aggregation,
   hierarchy drill-down routes and alert escalation.
9. Wire provider quote selection, booking status and tracking into the Delivery UI;
   add operational screens for the newly added workflow operations beyond the
   provider-configuration request/approval controls.

No tests, migration replay, pgTAP, Edge type-check, staging data writes,
Production changes or merges were performed. These remain reserved for the
final validation batch. Keep both release flags false.


### CRM campaign outbox increment

Added a provider configuration registry scoped by tenant and channel. The
configuration stores only an environment secret reference, starts in
`pending`, and can become active only after an independent approver confirms
it. The Edge Function exposes Platform Owner-only list/request/approve routes.
The ERP workspace now exposes provider configuration, independent approval,
and a campaign action to materialize the outbox after consent-aware audience
preparation.

Added database worker primitives:

- `crm_queue_campaign_outbox` materializes durable provider-neutral payloads
  from prepared recipients and requires an active provider configuration.
- `crm_claim_campaign_outbox` atomically claims due work with
  `FOR UPDATE SKIP LOCKED`.
- `crm_finalize_campaign_outbox` records provider acceptance or failure,
  schedules bounded exponential retries, and dead-letters exhausted attempts.
- `crm_apply_campaign_provider_receipt` atomically deduplicates signed
  provider receipt events and updates outbox/recipient delivery state. Its
  caller must verify provider signatures over raw bytes before invoking it.

The actual send adapter and provider-specific signed webhook route are still
blocked on an approved, known provider contract and its staging credentials.
The new UI explicitly states that queuing is not sending.

### HR/Finance canonical model reconciliation

Resolved at source level: `HR_PAYROLL_FINANCE_SCHEMA_DRAFT.sql` now explicitly
extends the canonical `hr_payroll_runs` and `hr_payroll_lines` definitions.
The shadow `hr_payroll_run_lines` / `finance_journal_batches` design was
removed. The legacy `hr_payroll_finance_outbox` and its queue RPC were also
removed from the HR workforce draft so there is one authoritative posting
lifecycle: approved payroll → `hr_payroll_finance_postings` draft →
`finance_journal_entries` posted → server-computed reconciliation hash.

The Edge Function and ERP payroll screen now expose independent account
mapping approval, Finance draft preparation against an open fiscal period,
journal posting and reconciliation. Reconciliation computes SHA-256 from the
actual posted journal rows in PostgreSQL; the client cannot supply the hash.
Payroll calculation currently uses approved timesheets and effective approved
hourly rates. Allowance, overtime premium, tax/benefit and statutory deduction
policies are not inferred or invented; those components need approved policy
inputs before being represented in payroll.

No SQL draft has been applied to staging and no payroll posting has been run.


### Franchise agreement lifecycle increment

Added an append-only agreement event timeline and server-only lifecycle RPCs
for creating a draft agreement after the six due-diligence checks and site
approval, independent submission for signature, recording the signed-document
reference, and activating only after a tenant/branch pair is verified. The
signature-recording step is deliberately separate from tenant/branch
activation so that legal signing can precede operational provisioning. The
signature reference is evidence metadata; no e-signature cryptographic
verification provider is claimed.

The Franchise Edge Function now exposes Owner-only agreement list/create/
independent term approval/submit/signature-record/activate actions. Agreement
term approval is separate from draft creation and signature submission; the
creator cannot approve their own version. The ERP workspace now has controls
for agreement terms, independent approval, signature evidence, and tenant/branch
activation. Actual
tenant and branch provisioning, e-sign provider verification, amendment/
renewal/termination, opening gate execution and royalty invoice/payment
settlement remain outstanding.


### Executive ranking increment

Added tenant-scoped immutable ranking headers/items and
`executive_publish_branch_ranking`. The RPC accepts only 1–150 active
branches and refuses publication unless every active branch has a published
BI snapshot for the requested metric/period and an active approved branch
target. It stores the exact snapshot lineage, rank, target and variance.
The Edge Function exposes Platform Owner-only publish/read routes and the ERP
workspace now provides a ranking publication form and persisted ranking view.

The ranking contract uses the repository's existing branch status
(`status='active'`) and BI dimension key (`branch_id`), rather than inventing
alternate schema names. It does not yet provide target authoring/approval UI,
automated alert generation, region/company rollups, or the full hierarchy
drill-down. A complete 150-branch ranking cannot be claimed until source
snapshots and approved targets exist for all branches.


### CRM financial close source adapter increment

The CRM projection builder now derives its evidence directly from the current
staging source model rather than trusting caller-provided totals or evidence
JSON. It reads:

- `pos_sales` / `orders` and their paid status, branch, amounts and tender;
- `payment_records` for paid online-order amounts;
- `payment_settlement_items` + `payment_settlements`, requiring matched
  settlement batches and received/net amount parity for electronic tender;
- `cash_reconciliations`, requiring approved shift cash reconciliation for
  POS cash sales;
- `refund_records`, including processed refund amounts and blocking open
  requested/approved refunds;
- `finance_journal_entries`, requiring posted source journals matching the
  source gross and a posted journal matching each processed refund.

Cash POS uses approved shift cash evidence instead of provider settlement.
POS split tender is deliberately rejected until the source model has an explicit
cash/provider allocation. The adapter hashes a canonical source snapshot,
persists an immutable `crm_financial_close_projections` row, and exposes
Platform Owner-only `erp-crm-build-financial-close`. Loyalty award then reads
that projection and requires the customer transaction link and an approved
earning rule. No points are awarded by the projection builder itself.

This is still a source-level draft: the CRM schema/RPC has not been applied to
staging, and no staging transaction has been mutated or used to claim a runtime
pass. The source Finance journal mapping is fail-closed: a source without exact
posted journal parity cannot earn points.

### Current execution boundary

Payroll HR/Finance model unification and CRM source adapters are now
implemented in PR #145 source, but are not runtime-complete until the final
migration replay and integration batch. Payroll payment remains intentionally
deferred until the new Finance posting is reconciled and an approved provider
contract is available. Tests, migrations, E2E, P01–P09 and merge remain deferred
to the final batch per instruction.
