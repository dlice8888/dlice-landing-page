# PRD 189 Feature ID — Open PR Crosswalk (2026-11-26)

## Scope
All **24 open pull requests** visible in the repository listing were inventoried and their patch/file scope reviewed. The ledger carries one row for each of the 189 stable feature IDs and attaches all directly relevant PR references without duplicating the feature denominator.

PR presence is not completion. No feature is promoted to DONE and no progress score is inferred from a PR title, commit, preview, or test-only change. Completion still requires exact-head code/UI, database, authorization, automated tests, E2E workflow, and transaction reconciliation evidence.

## Open PR inventory
| PR | Scope reviewed | Feature crosswalk |
|---|---|---|
| #150 | Food safety, recall, supplier quality and CAPA workflows | D18-F06/F07; D07-F07 |
| #149 | Disposable PostgreSQL tenant isolation/concurrency probe | D16-F02 (supplemental); D18-F10 |
| #148 | Disposable PostgreSQL backup/restore rehearsal | D18-F08 only; managed Supabase recovery remains open |
| #147 | PRD evidence ledger and audit reconciliation | Audit artifact attached to all 189 IDs; not product implementation |
| #146 | Xendit payroll payout adapter, webhook and Finance clearing | D11-F02/F05/F06/F07; D12-F06/F07; D17-F02/F04/F05 |
| #145 | Transactional orchestration for eight domains | CRM, HR, Delivery, Franchise, BI, SaaS, Procurement and Executive feature mappings recorded in JSON ledger |
| #144 | Eight-domain workflow kernels and schema drafts | HR and BI domain baseline mappings recorded in JSON ledger |
| #143 | POS split tender, hold/resume, immutable receipt and offline replay | D02-F04/F07/F08/F10/F12 |
| #127 | Atomic customer payment proof and payment-attempt supersession | D03-F07; D17-F05 |
| #123 | Online checkout idempotency and order/reservation ledger | D03-F07; D17-F05 |
| #119 | Disable automatic staging mutations / scheduled policy audit | Safety/CI policy; no direct PRD feature ID |
| #118 | Require explicit confirmation for staging mutation workflows | Safety/CI policy; no direct PRD feature ID |
| #117 | OIDC session broker rebase | Baseline/security infrastructure; no direct feature-level increment assigned |
| #116 | Backup/OIDC stacked before rebase | Baseline/security infrastructure; no direct feature-level increment assigned |
| #115 | Staging baseline branch | Broad baseline snapshot, not counted as a feature increment |
| #114 | Cross-module tenant boundary acceptance tests | D16-F02; D18-F01/F02/F04/F18 (test evidence only) |
| #113 | Prevent scheduled staging E2E mutation bypass | Safety/CI policy; no direct PRD feature ID |
| #112 | Boolean platform_owner metadata hardening | D18-F04 (security/auth test and migration evidence) |
| #111 | GitHub OIDC staging tenant session broker | D16-F02; D18-F18 (test/security evidence) |
| #109 | Same-tenant stock transfer enforcement | D06-F08; D18-F17 |
| #108 | PR history and file-overlap inventory | Audit documentation; no product feature increment |
| #107 | Environment-validated Supabase runtime configuration | Runtime/config infrastructure; no direct feature ID assigned |
| #104 | Production CORS source and fail-closed contract | D18-F03 |
| #71 | Staging tenant fixtures and tenant isolation | D16-F02; D18-F18 |

## Domain mapping details
- POS & Checkout: D02-F04, D02-F07, D02-F08, D02-F10, D02-F12 → #143.
- Order Management / Integrations: D03-F07 and D17-F05 → #123/#127.
- Inventory & Quality: D06-F08 and D18-F17 → #109; D07-F07 and D18-F06/F07 → #150.
- CRM: D10-F01/F02/F04/F07 → #145.
- Finance and HR: D11-F02/F05/F06/F07 and D12-F01–F07 → #144/#145/#146.
- Delivery: D09-F01–F07 → #145.
- Franchise: D13-F01–F08 → #145.
- BI: D14-F01–F06/F08 → #144/#145.
- SaaS: D16-F01/F03/F04/F05/F07 → #145; D16-F02 → #71/#111/#114/#149.
- Executive: D01-F01/F03/F04/F09 → #145.
- Security: D18-F01/F02/F03/F04/F18 → #71/#104/#111/#112/#114.
- Quality recovery and scale: D18-F08 → #148; D18-F10 → #149.

The machine-readable ledger contains the full row-by-row mapping, including evidence kind and limitation. IDs with no direct mapping in this open-PR set remain explicitly unmatched; they must be reviewed against historical PRs, commits and the source register before the crosswalk is canonical.

## Payroll disposable replay — defect and correction
Run `45659462961` checked out merge candidate `2731e09` (PR #146 commit `23e4b6c2...` merged into PR #145 base). It failed at line 551 of `HR_PAYROLL_PAYMENT_FINANCE_CLEARING_DRAFT.sql` because the immutable-trigger function had mismatched dollar delimiters (`as $` / `end $`). The current PR #146 head `34aa8992631c61abb4d3d7e8cc95779bdffc4ae4` has the corrected `as $$` / `end $$` delimiters. This is a source correction only; disposable replay and pgTAP remain NOT VERIFIED until a new exact-head run passes.

## Next work
1. Review historical PRs/commits for the 123 IDs without a direct match in the open-PR set.
2. Reconcile competing opening matrices and source register definitions before publishing canonical totals.
3. Implement the next CRM and HR database adapters using one atomic RPC per business transaction; avoid multi-request pseudo-transactions.
4. Add Quality RPC adapter and pgTAP contracts, then rerun payroll disposable replay at the corrected head.
5. Keep each feature PARTIAL until its own weighted evidence is attached; keep DONE at zero until the full acceptance gate passes.
