# CRM/Loyalty ↔ POS, Order, Refund, Settlement & Finance — 2026-11-28

## Candidate implementation

The existing CRM migration already defines customer identity linking, transaction links, financial-close projections, loyalty rules/ledger and point allocations. This batch closes two important integration gaps.

### Source-to-ledger flow

1. Paid POS sales and paid online orders are linked to CRM customer identity through the existing paid-source trigger and `crm_transaction_links`.
2. `crm_build_financial_close_projection` reads the paid source, processed refunds, settlement items, approved shift cash reconciliation and posted Finance journal evidence.
3. POS split tender is now reconciled by method:
   - total `pos_sale_tenders` must equal the sale total;
   - cash allocation must reconcile to the approved shift cash drawer;
   - bank-transfer/QRIS allocations must match provider settlement items by method and amount;
   - every referenced provider settlement must be matched and its received net amount must equal the settlement net.
4. `crm_reconcile_financial_close_projection` independently rechecks provider settlements and cash drawer evidence, including both dimensions for split-tender sales, then checks Finance journal state and refund evidence.
5. `crm_award_loyalty_for_reconciled_close` awards points only from reconciled net sales (subtotal minus discount minus processed refunds).
6. When a later processed refund reduces eligible net sales, the award RPC writes an immutable negative adjustment, reverses unspent points from the original earn lot, and records debt for points already spent. It retains the original earning-rule version so a later rule change does not recalculate an old sale under a new rule.

## Files changed

- `supabase/migrations/20261126192455_crm_loyalty_financial_close.sql`
- `supabase/tests/crm_loyalty.test.sql`
- `erp.html` (clarifies split-tender reconciliation outcome)
- `supabase/functions/dlice-orders/index.ts` (maps tender reconciliation failures to conflict responses)

## Acceptance boundary

- These are candidate migration/source changes only. No migration was applied to staging or production.
- pgTAP assertions now check split-tender source evidence, independent cash/settlement rechecks, earning-rule provenance and refund adjustment logic. They still require disposable replay to execute.
- The existing Edge Function source has explicit Platform Owner and tenant/branch authorization gates; current staging runtime version has not been deployed with this candidate.
- Customer LTV snapshots remain a separate open integration item; they are not claimed complete by the financial-close work.
- No feature score is increased until exact-head tests and staging E2E/reconciliation prove the workflow.
