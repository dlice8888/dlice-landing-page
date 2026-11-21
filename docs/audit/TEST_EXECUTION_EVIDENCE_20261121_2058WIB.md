# D’Lice test execution evidence — 21 November 2026, 20:58 WIB

Repository: `dlice8888/dlice-landing-page`  
Staging project: `dlice-staging` (`higoadrzxnhzbbwhdbmh`)  
Staging DB status: `ACTIVE_HEALTHY`, PostgreSQL 17  
Acceptance policy: measurable test evidence only; no separate independent PR-review step.

## 1. Existing Supabase Auth fixture inventory

Read-only database queries confirmed four Auth users. Two existing active identities match the required tenant fixtures:

| Fixture | Existing Auth identity | Profile | Tenant membership | Branch |
|---|---|---|---|---|
| Tenant A | `qa_dlice_staging_no_permission` | active `sales_admin` | active `branch_manager`, 6 membership permissions | `QA-DLICE-A` |
| Tenant B | `qa_dlice_staging_branch_a` | active `sales_admin` | active `branch_manager`, 6 membership permissions | `QA-TENANT-B` |

They belong to different tenant IDs and have distinct Auth user IDs. Both emails are confirmed; neither identity is currently banned or deleted. No Auth user, password, metadata, membership, or assignment was changed.

PR #126 contains a passwordless workflow candidate:
- Auth Admin `generate_link(type=magiclink)` for the two existing account emails.
- Verify the one-time token hash using the public key.
- Keep access tokens, token hashes and service-role key out of logs.
- Revoke temporary sessions after probes.
- Remove the missing username/password inputs.

The candidate requires the protected staging Environment secret `STAGING_SUPABASE_SERVICE_ROLE_KEY`. Its presence and the Environment's protection configuration cannot be verified by the current GitHub connector. The connected tools expose no workflow-dispatch action. Therefore P01–P09 are **NOT RUN**, not PASS.

## 2. Exact-head CI and disposable migration results

| Candidate | Exact head | Disposable migration replay | pgTAP files | Assertions | Other required candidate workflows |
|---|---|---:|---:|---:|---|
| PR #120 | `f37b581f43dc250a8ee7ff0eb04ae1b0e80a42f0` | IN PROGRESS at snapshot | — | — | Quality, CORS, KDS, procurement requisition and receiving PASS |
| PR #123 | `9024f2ce6067fe4252f5110942017e27ac1ed7b5` | PASS | 5 | 74 | Quality, CORS, KDS, procurement requisition and receiving PASS |
| PR #126 | `4a6aa8ccf07e25981579a805477dffc65a13a376` | PASS | 7 | 139 | Quality, CORS, KDS, procurement requisition and receiving PASS |
| PR #127 | `e52ea75a218eedecc513ec52311adaee25f241ba` | PASS | 7 | 124 | Quality, CORS, KDS, procurement requisition and receiving PASS |

PR #120's immediately preceding tested head `735e429517655809899a4e942368b39eb96898a5` completed disposable replay with 154 assertions. Do not attribute that PASS to its newer head while the latest replay is still running.

Combined migration candidate:
- Branch: `audit/combined-migration-replay-20261121`
- Commit: `700c2edf2f5f1bee2e5ac4c3afaece7c60efb3e3`
- 60 source migration files applied to a disposable local Supabase database.
- 14 pgTAP files and 270 assertions passed.
- Run: https://github.com/dlice8888/dlice-landing-page/actions/runs/44911080939

These are disposable database and contract-test results. The workflow names containing “staging” do not mean that the shared staging database or live customer workflows were mutated.

## 3. Migration parity and collision reconciliation

Live staging:
- 49 applied migration history entries.
- 52 migration source files on the staging branch.
- Three source-only files remain unapplied: `20261120100000_atomic_owner_and_tenant_bootstrap.sql`, `20261120110000_command_center_summary.sql`, and `20261120120000_atomic_branch_checklist_audit.sql`.

The combined candidate has 60 migration files and replayed successfully on a disposable database. No same-version/different-SQL collision was found.

Identical duplicate source blobs are consolidated as follows:
- `20261121130000_atomic_tenant_invite_lifecycle.sql`: PR #120 and #126 share identical blob `b9dab9b7027e51bd5a4069b854b65a14563df6eb`; the invitation test blob is also identical.
- `20261121140000_order_expiry_payment_lifecycle.sql`: PR #125 and #127 share identical blob `c1d1de05b61055a0003a889d70b5e41a298caffd`.
- PR #124 is closed, unmerged and superseded by #120.
- PR #125 is closed, unmerged and superseded by #127.

The invitation version overlap is not a divergent collision; it is byte-identical source and test content. The expiry migration from #125 is present in #127. No migration has been applied to shared staging.

## 4. Supplemental database authorization checks

A read-only SQL session set the authenticated role and the JWT subject claim to each existing Tenant A/B user. For both users, direct branch-table reads returned zero rows for both own and foreign QA branches (4/4 zero-row outcomes). The subject and role claims were verified by `auth.uid()` and `auth.role()`.

The `branches` table has RLS enabled. This supplemental SQL impersonation is not an actual Supabase Auth login, HTTP Data API call, or Edge Function test and does not replace P01–P09. It indicates direct branch-table rows are not exposed through this tested direct-client path.

The `public.erp_create_stock_transfer` RPC ACL is also verified read-only: EXECUTE is false for `anon` and `authenticated`, true for `service_role`.

## 5. Live acceptance still outstanding

1. Verify staging Environment protection and service-role secret presence without reading or printing secret values.
2. Dispatch the passwordless workflow from trusted `staging`.
3. Execute P01–P09 with the two existing Supabase accounts: 9/9 executed, 9/9 expected results, zero BLOCKED/SKIPPED.
4. Run live positive and negative mutation-path tests for #120 and verify atomic audit rollback on forced audit failure.
5. Run browser/network fault injection for #123 and #127: duplicate checkout, response loss, concurrent submissions, payment proof retry, expiry race, late payment, compensation and supersession.
6. Run the live expiry worker and reconcile the legacy staging orders/reservations/payment attempts. Do not automatically alter the seven legacy orders.
7. Verify full Kitchen, inventory, procurement and finance workflows against persisted staging ledger data only after explicit staging authorization.

## 6. Release state

- `TENANT_ISOLATION_RELEASED=false`
- `PUBLIC_TENANT_ROUTING_RELEASED=false`
- No shared staging migration, Edge Function deployment, cron activation, or production mutation was performed.
- No feature may be marked DONE from disposable replay or contract tests alone.
