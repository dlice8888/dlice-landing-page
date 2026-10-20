# D’Lice — Customer ordering + POS/ERP

D’Lice customer website and staging operational workspace. The customer site preserves the existing wine/rose/cream palette and priority brand copy; order creation, payment proof, receipt confirmation, and tracking are handled by the existing authenticated Edge Function.

## Customer menu
- **Es Buah Premium D’Lice — Rp60.000**: 1 liter premium fruit jar; Muscat and autumn grapes, grape jelly, fresh papaya mocktail, sliced nata de coco and D’Lice syrup. Serves 3–4.
- **Cadbury Braid Cheese — Rp70.000**: one whole Cadbury bar wrapped in large strudel-style pastry with cheese topping, cut into portions.
- **Cadbury Kunafa Pistachio — Rp90.000**: one whole Cadbury bar with Kunafa Pistachio filling, wrapped in large strudel-style pastry and cut into portions.

## Operational applications
- `admin.html`: existing customer-order operations, payments, catalog, staff accounts and capacity.
- `erp.html`: staging multi-branch workspace for POS shifts and sales, stock ledger, purchase-order drafts, branch expenses/approvals, branch master and job assignments.
- `docs/POS_ERP_MULTI_BRANCH_OPERATING_MODEL.md`: detailed job descriptions, recommended staffing, permissions, separation of duties, 150-branch rollout model, POS/inventory/finance flows and verification checklist.
- `docs/STAGING_UI_CATALOG_ROLLOUT_2026-10-21.md`: customer-facing responsive UI and catalog rollout notes.

## Environments
- Production: `https://dlice.vercel.app/` and Supabase project `gdjlkrmlsurcdbwnmqgg`.
- Staging: branch `feat/staging-order-receipt-gates` / preview deployment and Supabase project `higoadrzxnhzbbwhdbmh`.
- ERP development branch: `feat/staging-multi-branch-erp-foundation`. Never deploy these changes to production before staging UAT and explicit promotion approval.

## Free-first constraints
No paid POS, ERP, analytics, motion, or UI library is introduced. The current implementation uses static HTML/CSS, the existing Supabase Edge Function/Postgres and Vercel Preview. Check plan quotas before scaling traffic or storage; "free" does not mean unlimited.

## Running locally
Static pages can be served from the repository root. Use the staging Supabase URL/publishable key only for a staging preview. Never put service-role/secret keys in browser code.

## Important rollout limitations
The 150 numbered branches are planning slots, not active real-world locations. Owner must fill address, local timezone, manager, opening date, staffing and operating controls before setting a branch active. Website order routing, recipe/BOM-based ingredient deduction, supplier receiving automation, payroll, taxes, refund/void POS, bank/QRIS settlement and accounting period close are not claimed as complete; each requires approved rules and end-to-end tests before production use.
