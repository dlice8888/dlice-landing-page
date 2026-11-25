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
