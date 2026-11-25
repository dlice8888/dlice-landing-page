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
| CRM | `awardLoyaltyForFinancialClose` | Reconciled source close, customer resolution, idempotent ledger + balance, audit |
| HR / Finance | `persistApprovedPayrollRun` | Approved run, open fiscal period, immutable lines, balanced draft journal, audit |
| Delivery | `ingestSignedDeliveryWebhook` | HMAC verification, event dedupe, dispatch update, audit |
| Franchise | `provisionApprovedFranchise` | Signed effective contract, 10 independently verified gates, territory check, atomic tenant/branch provisioning |
| BI | `ingestReconciledKpiSnapshot` | Published formula, Finance facts, source reconciliation, lineage, immutable snapshot |
| SaaS | `meterCommittedTenantOperation` | Meter only after authoritative operation commit; durable retry remains an adapter responsibility |
| Procurement | `executeApprovedSupplierPayment`, `reconcileApprovedSupplierSettlement` | Payment intent in transaction, provider call outside transaction, persisted result, later settlement reconciliation |
| Executive | `readAuthorizedExecutiveDrilldown` | Authorization at each hierarchy node and Finance-reconciled source transaction read |

## Still required before any domain can be marked DONE

1. Implement concrete Supabase repository adapters and RPCs for every named port.
2. Add database-enforced unique constraints, foreign keys, tenant isolation and RLS
   for the new entities. These are intentionally not applied in this branch.
3. Wire the services into authenticated Edge Function routes and UI workflows.
4. Complete campaign dispatch provider selection, provider receipt webhook,
   unsubscribe persistence, retries and ROI attribution.
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
