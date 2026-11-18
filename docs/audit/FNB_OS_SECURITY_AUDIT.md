# FnB OS Security Audit

**Snapshot:** 18 November 2026  
**Supabase target:** staging `higoadrzxnhzbbwhdbmh`  
**Production:** excluded

## Auth and tenant identity

- Two worker memberships are present in separate tenants. Both have role `branch_manager` and identical permission arrays: `orders, branches, inventory, pos, procurement, reports`.
- Memberships are active and worker identities are distinct in the staging inventory.
- Worker A has two active branch assignments in its own tenant; Worker B has one. No cross-tenant assignment rows were found. The exact-one-branch P03 fixture assertion therefore fails for A until the extra assignment is reconciled through the authorized admin path.
- One active Owner profile is linked to an Auth user, but the Auth user lacks `app_metadata.platform_owner=true` as a boolean. Read-only count of Auth users with that boolean true: 0.
- GitHub Environment variables/secrets and `DLICE_PLATFORM_OWNER_USER_IDS` could not be read through the connected integration. Their values were not queried or printed.

## Authorization source references

| Control | Source |
|---|---|
| Tenant release flag false | `supabase/functions/dlice-orders/index.ts:52` |
| Owner UUID allowlist | `supabase/functions/dlice-orders/index.ts:55-57` |
| Owner authorization conjunction | `supabase/functions/dlice-orders/index.ts:92-100` |
| Uncertified action denylist | `supabase/functions/dlice-orders/index.ts:60-89` |
| Public tenant routing flag false | `supabase/functions/dlice-orders/index.ts:135-144` |
| Active membership permission intersection | `supabase/functions/dlice-orders/tenant-permissions.ts` |

## Database security inventory

- 64 public base tables; all 64 have RLS enabled.
- 64 public policies; policy semantics and each table/action pairing still require per-policy tests.
- 29 public functions; 5 SECURITY DEFINER functions.
- The five SECURITY DEFINER stock functions (`erp_create_stock_count`, `erp_create_stock_transfer`, `erp_post_stock_count`, `erp_transition_stock_transfer`, `erp_update_stock_count_item`) currently show EXECUTE denied to `anon` and `authenticated`, granted to `service_role`.
- Direct table grants to `anon` and `authenticated` are limited to SELECT on `public.products`.
- No public views were returned by the read-only inventory query.
- Do not infer policy correctness from RLS enabled state alone.

## Advisor findings

- Security: leaked-password protection disabled (WARN).
- Performance: 26 unindexed foreign-key findings; 49 unused-index suggestions. Do not drop unused indexes without workload/query-plan review.
- No database DDL or Auth configuration was changed during this audit.

## P0 evidence status

| Test | Status | Reason |
|---|---|---|
| P01 Tenant A login | BLOCKED | Protected credential availability cannot be verified; no trusted run |
| P02 Tenant B login | BLOCKED | Protected credential availability cannot be verified; no trusted run |
| P03 distinct identity/membership/exact branch | BLOCKED | No runtime run; Worker A has 2 active assignments but expected exactly 1 |
| P04 A own-branch inventory read | BLOCKED | No authenticated runtime read |
| P05 A cross-tenant read denied | BLOCKED | No authenticated runtime negative test |
| P06 B own-branch inventory read | BLOCKED | No authenticated runtime read |
| P07 B cross-tenant read denied | BLOCKED | No authenticated runtime negative test |
| P08 A cross-tenant write denied | BLOCKED | No authenticated runtime negative test |
| P09 B cross-tenant write denied | BLOCKED | No authenticated runtime negative test |

Latest known staging runtime attempt `44208204366` was blocked at preflight before network access. Static quality run `44303062590` is not tenant runtime evidence.

## Required secure remediation

1. Reconcile Worker A extra branch assignment through the authorized HR/branch assignment workflow; preserve all unrelated assignment history.
2. Verify canonical two-worker credentials and six fixture variables by presence/availability only in GitHub Environment `staging`.
3. Verify Owner Auth metadata through official Supabase Auth Admin, preserving other metadata, and independently verify UUID allowlist.
4. Run P01–P09 and supplemental direct REST/RPC tests on trusted staging; no SKIPPED or false PASS.
5. Keep both release flags false and PR #64 Draft/HOLD until independent security review and runtime evidence pass.
