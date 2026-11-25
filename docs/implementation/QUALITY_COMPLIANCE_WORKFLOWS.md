# Food Safety, Recall and Supplier Quality Workflow — Design Draft

## Scope
This increment starts two previously unproven Quality, Compliance & Security workflows:
1. Food safety inspection with approved tenant/branch policy, temperature range, allergen declaration, immutable inspection evidence and automatic lot quarantine on policy failure.
2. Food recall with lot traceability to affected branches and orders, durable recall record and quarantine.
3. Supplier receipt quality inspection with approved supplier-specific policy, quantity quarantine on major/critical findings, corrective action (CAPA), independent verification and controlled quarantine release.

## Safety invariants
- No universal temperature limit or allergen policy is hard-coded. Every evaluation requires an approved effective policy for the tenant/branch/product class.
- Missing, draft, expired or cross-tenant policies fail closed.
- Quarantine, recall, CAPA and audit writes must share the same tenant transaction.
- Supplier CAPA creator/submitter cannot verify their own action.
- Quarantined stock is not released by client assertion; independent CAPA verification and an explicit repository release confirmation are required.
- Recall impact (branches/orders) is derived server-side from lot movement/consumption lineage, not supplied by the caller.
- All write paths use idempotency and immutable evidence.

## Workflow
Food safety: receive/produce/branch-check → load approved policy → capture temperature/allergen declarations → accepted OR quarantined → audit.
Recall: identify lot → resolve affected branches/orders → initiate recall → quarantine lot → trace follow-up.
Supplier quality: GRN received → inspect against approved supplier policy → accepted-with-observation OR quarantine → CAPA opened → supplier submits correction/evidence → independent verification → release quarantine only after verified decision.

## Implementation status
The source orchestration and dependency-free contract tests are present in this PR. The SQL schema is a design draft and remains unapplied. Concrete Supabase repository RPC adapters, authenticated Edge Function routes, private Storage evidence lifecycle, ERP/mobile UI, policy authoring/approval UI, and staging E2E remain required before either feature can be marked DONE.
