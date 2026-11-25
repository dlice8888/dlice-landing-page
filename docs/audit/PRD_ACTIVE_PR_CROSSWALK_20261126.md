# PRD 189 Feature ID — Active PR Crosswalk (2026-11-26)

## Scope and counting rules

This is a first-pass crosswalk for all 189 stable feature IDs in `PRD_FEATURE_EVIDENCE_LEDGER_20261126.json`. It reviewed active PRs #123, #127, and #143–#150. Every feature ID appears exactly once in the ledger. A feature touched by multiple PRs retains one feature ID and one denominator count; PR references are many-to-one.

A PR match means implementation/source evidence exists or is being added. It does **not** mean the feature is complete. No status is promoted to DONE and no progress percentage is inferred from PR existence. A final score still requires code/UI (20%), database (20%), authorization (15%), automated tests (15%), E2E (20%), and reconciliation/observability (10%).

## PR inventory and evidence boundary

| PR | Scope | Crosswalk interpretation |
|---|---|---|
| #123 | Online checkout idempotency and order/reservation ledger | Direct to D03-F07 and D17-F05 |
| #127 | Atomic customer payment proof and payment-attempt supersession | Direct to D03-F07 and D17-F05 |
| #143 | POS modifiers, split tender, hold/resume, immutable receipt, offline replay | Direct to D02-F04/F07/F08/F10/F12; staging E2E is separate from browser/device acceptance |
| #144 | Eight-domain workflow kernels and schema drafts | Domain baseline for selected HR and BI feature IDs; pure workflow code/schema drafts are not concrete adapter/runtime evidence |
| #145 | Transactional orchestration across CRM, HR/Finance, Delivery, Franchise, BI, SaaS, Procurement and Executive | Main direct mapping for those workflow IDs; SQL remains draft and adapters/UI/runtime remain partial |
| #146 | Payroll payout v3, webhook/reconciliation, Finance clearing | Direct to HR payroll and Finance/bank clearing features; current-head SQL corrected but replay/pgTAP not yet proven |
| #147 | 189-feature evidence ledger | Audit artifact attached to all 189 IDs; not product implementation evidence |
| #148 | Disposable PostgreSQL backup/restore rehearsal | Direct to D18-F08 only; not managed Supabase PITR/Auth/Storage or production RPO/RTO |
| #149 | Disposable PostgreSQL tenant isolation/concurrency probe | Direct to D18-F10 and supplemental context for D16-F02; not app/API load proof |
| #150 | Food safety, recall, supplier quality and CAPA | Direct to D18-F06/F07 and supplier GRN quality path D07-F07; adapter, Edge, UI, DB replay and staging E2E remain open |

## First-pass crosswalk by domain

- Executive Command Center: D01-F01, D01-F03, D01-F04, D01-F09 → #145.
- POS & Checkout: D02-F04, D02-F07, D02-F08, D02-F10, D02-F12 → #143.
- Order Management: D03-F07 → #123, #127.
- Procurement & Supplier: D07-F07 → #150; D07-F09 → #145.
- Delivery & Fulfillment: D09-F01–F07 → #145.
- CRM, Loyalty & Marketing: D10-F01, F02, F04, F07 → #145.
- Finance & Accounting: D11-F02, F05, F06, F07 → #145, #146.
- HR & Workforce: D12-F01–F07 → #144, #145, #146.
- Franchise & Expansion: D13-F01–F08 → #144, #145.
- BI & Analytics: D14-F01–F06, F08 → #144, #145.
- SaaS Tenant Management: D16-F01, F03–F05, F07 → #145; D16-F02 → #149 (supplemental database concurrency evidence).
- Integrations & Automation: D17-F02, F04–F06 → #123, #127, #145, #146.
- Quality, Compliance & Security: D18-F06/F07 → #150; D18-F08 → #148; D18-F10 → #149.
- Cross-domain process controls: D18-F13 → #143/#145; D18-F14 → #145/#146; D18-F16 → #145/#146.

The ledger records all other IDs as `NO_DIRECT_ACTIVE_PR_MATCH` in this reviewed set. That is not a statement that no code exists anywhere; it means this first-pass active-PR review did not find a defensible direct feature-specific mapping. Older open PRs and the complete PR history still require a second pass before the crosswalk is canonical.

## Payroll disposable replay defect found

Run `45659462961` checked out merge candidate `2731e09` (PR #146 commit `23e4b6c2...` merged into PR #145 base). Replay failed at line 551 of `HR_PAYROLL_PAYMENT_FINANCE_CLEARING_DRAFT.sql`: the immutable-trigger function used mismatched dollar delimiters (`as $` / `end $`). The current PR #146 head `34aa8992631c61abb4d3d7e8cc95779bdffc4ae4` now has the corrected `as $$` / `end $$` delimiters. This is a known fix, not a passing replay; rerun the disposable workflow on the current exact head before marking SQL replay or pgTAP PASS.

## Next crosswalk pass

1. Review remaining active PRs that touch shared files and older feature areas; map only when the patch directly supports a stable feature ID.
2. Resolve duplicate/conflicting feature definitions between the owner-supplied opening matrix, checked-in source matrix and active PR descriptions.
3. Recompute canonical status totals only after all 189 IDs have one resolved source-of-truth row.
4. Score each PARTIAL feature from exact evidence, preserving BLOCKED where an external prerequisite remains.
