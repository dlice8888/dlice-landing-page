# D’Lice POS/ERP — multi-branch staging foundation

## Scope and deployment guardrail
- Work is limited to branch `feat/staging-multi-branch-erp-foundation`, staging Supabase project `higoadrzxnhzbbwhdbmh`, and its Vercel Preview.
- Production branch `main`, production Supabase `gdjlkrmlsurcdbwnmqgg`, and `https://dlice.vercel.app/` must not be changed before staging sign-off.
- New ERP tables have RLS enabled and direct `anon` / `authenticated` table grants revoked. All access must pass through the authenticated Edge Function and server-side validation.

## 150-branch model
The migration creates Head Office (`DLC-HQ`) and 150 **planned slots** (`DLC-B001`…`DLC-B150`). Slots are not falsely represented as operating branches; Owner must set location, status, timezone and opening date before launch. Existing customer orders remain global and unchanged in this foundation. Branch-level order routing must be introduced as a separate reviewed migration after the customer-order service has branch selection and fulfillment rules.

## Job descriptions and lean staffing recommendation
| Job position | Primary duties | Recommended headcount |
|---|---|---:|
| Owner / Director | Strategy, policy, approvals, cross-branch KPIs and risk | 1 overall |
| Head of Operations | SOP, SLA, quality, capacity, escalation across 150 branches | 1–2 HQ |
| Area Manager | 5–10 branches per manager, audits and coaching | 15–30 HQ |
| Branch Manager | Branch performance, shifts, local approval and reconciliation | 1 per active branch |
| Shift Leader | Shift handover, readiness, quality and service | 1 per operating shift |
| Cashier / POS | POS sale, receipt, cash discipline, shift close | 2–3 per branch, schedule-dependent |
| Kitchen / Production Lead | Batch planning, recipe standards, waste and priorities | 1 per branch |
| Kitchen / Production Crew | Prep, food safety, output and waste logging | 2–4 per branch |
| Inventory Controller | Receiving, stock count, expiry and discrepancies | 0.5–1 per branch (can be shared at low volume) |
| Procurement / Purchasing | Vendor, purchase orders and receipt matching | 3–5 HQ, scale with volume |
| Finance Controller | Bank/cash reconciliation, exceptions and reporting | 2–4 HQ |
| Finance Admin | Payment evidence, expense docs and close prep | 3–6 HQ |
| Customer Service | Customer inquiries, complaints and follow-up | 1–2 per branch or pooled centrally |
| Delivery Coordinator | Dispatch, proof of handoff and failed delivery | 0.5–1 per branch or shared |
| Marketing & CRM | Campaigns, catalog and conversion analytics | 2–4 HQ |
| HR / People Operations | Hiring, onboarding, training and workforce plans | 3–5 HQ |
| Internal Auditor | Independent read-only checks of cash, stock and access | 2–4 HQ |

These are planning ranges, not fixed staffing orders. Start with demand-based scheduling and cross-train where lawful and safe. Finance and audit approvals should be separated from transaction entry.

## Permissions and separation of duties
- `owner`: all permissions; protected owner bootstrap remains unchanged.
- `branches`: branch setup and assignments; Owner only for write operations.
- `pos`: cashiers and shift leaders; open/close shifts and create POS sales.
- `inventory`: receiving, stock movement, stock count and low-stock review.
- `procurement`: suppliers and purchase orders; PO approval should be separate from creation as volume grows.
- `finance`: expense review, settlement and reconciliation; submitter should not approve their own expense.
- `reports`: read-only operational/financial summaries.
- `audit`: read-only audit log access.
- `hr`: staffing structure and job assignments.
- Do not use client-side navigation hiding as an authorization boundary. Every Edge Function action must validate the bearer token, active profile, permission, branch assignment and server-computed amount.

## POS flow
1. Cashier opens a shift for an active branch with opening cash.
2. POS selects active products and quantities; server re-reads current product prices and computes totals.
3. A sale is tied to a branch and open shift, with immutable product-name/price snapshots.
4. Cashier records the actual payment method; server updates expected cash only for cash sales.
5. Cashier closes the shift with counted cash; variance is calculated and sent for manager review.
6. Refunds/voids require a separate permission and immutable audit trail; do not delete sales.

## Inventory and purchasing flow
1. Inventory item/SKU is created by authorized staff.
2. Receiving, issue, waste, transfer and adjustment create a stock-movement ledger row and update branch balance atomically.
3. Purchase order is created against a branch and supplier; approval and receiving should be recorded separately.
4. Stock minimum alerts are calculated from on-hand versus minimum. Recipe-based consumption is not auto-deducted until approved recipe/BOM and yield data are configured.

## Finance and approvals
- Expenses are created as `pending_approval`; no self-approval. The approval endpoint must enforce reviewer != creator and branch scope.
- Daily reconciliation compares POS cash expected vs counted, QRIS/bank settlements, approved expenses and deposits.
- Do not claim accounting/ERP parity with a full ERP suite until invoice numbering, tax treatment, refunds, procurement receiving, inventory valuation, and period closing have passed acceptance tests.

## Verification checklist
- Migration history and 150 planned slots are present in staging only.
- RLS is enabled and direct client grants are revoked on every ERP table.
- Test positive/negative authorization for Owner, cashier, inventory, finance and cross-branch access.
- Test two concurrent cashiers, price changes during checkout, shift close variance, duplicate requests and stock ledger atomicity.
- Verify the Vercel Preview and Figma responsive handoff on Android, iOS, tablet and desktop.
- Keep production unchanged until all E2E tests, leaked-password protection, and business acceptance sign-off pass.
