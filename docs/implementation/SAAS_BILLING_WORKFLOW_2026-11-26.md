# SaaS subscription, metering and billing workflow — 2026-11-26

Status: implementation increment in PR #145. SQL remains a design draft.

## Atomic lifecycle and billing

- Trial creation, cancellation, offboarding request/approval/completion and invoice issuance now use service-role-only RPCs rather than multi-request browser writes.
- Entitlement checks enforce active periods, trial expiry, past-due grace expiry and plan quota. Usage ingestion accepts only committed source events, locks per tenant and is idempotent across retries.
- Invoice issuance is idempotent per tenant and billing period. Expired trials/periods advance to a paid period and a seven-day grace window. Payment RPC supports pending-to-succeeded/failed provider callbacks, partial settlement, overpayment rejection and subscription reactivation only after the invoice is fully paid.
- Offboarding approval requires an independent reviewer. Without legal hold it suspends live subscriptions; legal hold blocks completion. Completion requires expired retention, no legal hold, a different actor from requester/approver and evidence. It does not delete tenant data.
- Every lifecycle, usage, invoice and payment mutation writes audit evidence in the same database transaction.

## Code and UI

- Supabase RPC adapter and worker for committed usage events and invoice issuance.
- Edge actions use atomic RPCs for trial, cancel, offboarding and invoice issuance; invoice reads are tenant scoped.
- ERP UI displays subscriptions, invoices/payment evidence and offboarding retention/completion state.

## Not yet proven or intentionally not enabled

- No payment provider signature/webhook adapter or provider credentials/fixture; payment settlement RPC is not exposed as a manual UI action.
- Entitlement enforcement is not yet wrapped around every protected API/Edge action.
- Dunning, scheduled grace expiry/suspension, proration, plan upgrades/downgrades and tax compliance remain unimplemented.
- No export/deletion executor. Offboarding completion records policy evidence only.
- No scheduled worker invocation, exact-head CI, disposable SQL replay, pgTAP or staging E2E has been observed.
