# Menu & Recipe — Nested BOM and Unit Economics (2026-11-27)

## Feature IDs started
- D05-F05 — Nested BOM, unit conversions, yield and prep loss.
- D05-F07 — Cost per serving and contribution margin.

## Implemented
`src/recipe-bom-unit-economics.mjs` provides deterministic pure-domain logic:
- recursively expands approved effective sub-recipes;
- rejects cycles and cross-tenant recipe/ingredient references;
- converts only compatible mass, volume and count units;
- grosses ingredient requirements for prep loss and recipe yield loss;
- consolidates repeated ingredient lines;
- calculates integer-IDR ingredient cost, cost per serving and contribution margin.

`tests/contracts/recipe-bom-unit-economics.test.mjs` covers nested recipes, unit conversion, prep loss, cycles, cross-tenant inputs, incompatible units, unapproved recipe versions and unit economics.

## Remaining acceptance gaps
- Persist immutable recipe versions and effective dates in Supabase.
- Add ingredient/UOM conversion master data with tenant governance and precision/rounding policy.
- Add canonical migration, RLS, FKs, constraints and immutable audit triggers.
- Load prices only from approved supplier price contracts and inventory valuation; no UI/client-provided cost is authoritative.
- Add authenticated RPC/Edge Function adapter and recipe approval workflow.
- Integrate POS modifiers/substitutions, KDS production and inventory consumption.
- Reconcile theoretical recipe usage and cost against actual stock movements and Finance.
- Add staging E2E for nested recipes, yield/prep-loss changes and historical transaction reproducibility.

This is implementation-start evidence only. No database was mutated and no feature is DONE.
