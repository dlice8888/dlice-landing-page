# Finance & Accounting — Branch Budgets and Consolidated Statements (2026-11-27)

## Feature IDs started
- D11-F09 — Budgets and branch P&L.
- D11-F10 — Consolidated financial statements.

## Implemented
`src/finance-budget-consolidation-workflows.mjs` adds:
- branch budget versus actual variance by account/period, requiring approved budgets and posted reconciled GL actuals;
- consolidated statement construction across closed branches, requiring every journal balanced and every source entry posted/reconciled;
- intercompany elimination only when elimination groups span multiple branches and balance;
- persisted statement publication with source revision and audit contract.

Contract tests cover variance, unapproved budget, unreconciled actual, branch close completeness, journal balance, intercompany elimination and publication.

## Remaining acceptance
- Canonical budget versions, account mappings, branch P&L dimensions and consolidation policy tables with RLS.
- Concrete Supabase adapters and authenticated Finance RPC/Edge routes.
- Map POS, Procurement/AP, Payroll, Inventory valuation, settlement and bank statement sources to canonical GL account balances.
- Validate fiscal period close, FX/currency translation, tax, intercompany matching and elimination rules with Finance owner.
- Build budget approval, forecast revision, variance explanation and consolidated statement review UI.
- Reconcile consolidated trial balance, P&L and balance sheet to every branch close and external accounting export.
- Staging E2E across the full tenant branch hierarchy; no Finance feature DONE from arithmetic-only contract tests.
