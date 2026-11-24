# POS checkout lifecycle — implementation slice

**Target:** staging only  
**Branch:** `feat/pos-checkout-lifecycle-20261124`  
**Scope:** split tender, held-order resume, immutable digital receipt snapshot, and modifier-to-sale/KDS snapshot acceptance.

## Implemented in this candidate

- Split tender RPC records two to five positive cash/bank-transfer/QRIS allocations, requires at least two distinct methods, and refuses settlement unless the allocations equal the final sale total exactly.
- Split checkout uses a separate actor/branch/idempotency fingerprint and advisory lock, then delegates item pricing, modifiers, recipe consumption, KDS creation and stock deduction to the existing atomic POS sale routine. The full transaction rolls back if tender validation fails.
- The cashier UI supports split tender and persists the operation in the IndexedDB offline queue. The sync endpoint routes split operations through the same atomic RPC and records an offline receipt, allowing safe retry after a lost response.
- Sales reconciliation now returns tender allocations, allocated total, cash portion and non-cash portion; the POS report aggregates cash/non-cash from tender rows rather than treating the entire split sale as one method.
- The ERP POS workspace now renders active modifier selectors, a hold/resume list, Owner-only discount entry, split tender fields and a print-receipt action.
- Cash tender allocation alone increases the shift's expected cash drawer amount. Non-cash allocations do not inflate cash.
- Held orders are persisted by branch, cashier, shift and client hold key; a changed payload with the same key is rejected. Resume is actor-scoped, one-way, returns a stable sale idempotency key and rejects expired holds.
- Digital receipts are generated from the committed sale and line snapshots, including modifier/substitution snapshots and tender allocations. A unique sale constraint makes repeat retrieval reuse the original immutable receipt.
- All four new tables have RLS enabled and explicit deny policies for anon/authenticated. All new RPCs are SECURITY INVOKER, pin search_path, verify the service-role JWT claim and grant EXECUTE only to service_role.
- Staging E2E candidate now covers modifier pricing/snapshot, receipt replay, hold/resume replay and split tender allocation/idempotency. It remains manual-dispatch only and was not run by this PR.

## Explicitly not complete in this slice

- Discount/coupon rules and non-owner approval/delegation are not implemented. Existing POS discounts remain Owner-only.
- Partial tender / unpaid balance collection is not enabled; split tender requires full settlement in one atomic checkout.
- Physical printer/browser-device acceptance and customer-facing receipt delivery are not proven; this slice persists a digital receipt snapshot only.
- A real browser offline queue and network fault-injection run remain separate acceptance work; existing offline replay API contract is not treated as proof of a fully offline POS client.
- Cashier workspace now exposes modifier selection, Owner-only discount entry, split tender, hold/resume, offline queue replay and receipt printing controls. Browser/device acceptance is still required before any feature is marked DONE.

## Acceptance gates

1. Exact-head static/API contracts pass.
2. Disposable Supabase replay applies all repository migrations and all pgTAP tests pass.
3. Runtime staging E2E runs only after PR review/merge and explicit staging mutation authorization.
4. Reconcile sale total, tender sum, cash drawer delta, stock movements, KDS ticket, receipt snapshot and audit events.
5. Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`. No production deployment or data changes.
