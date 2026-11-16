# PRs #76–#78 migration acceptance

**Overall result: BLOCKED for staging acceptance.** All three PRs were Open and
Draft with no independent reviews. Their disposable local migration replay
checks passed, but no staging migration, live schema comparison, or staging
runtime acceptance was performed.

| PR | Migration | Existing disposable replay | Staging/review state |
|---|---|---|---|
| #76 | `20261114110000_command_center_summary.sql` | PASS — [run 43622512657](https://github.com/dlice8888/dlice-landing-page/actions/runs/43622512657) | Draft; no independent approval; NOT applied to staging |
| #77 | `20261114120000_atomic_branch_checklist_audit.sql` | PASS — [run 43570024409](https://github.com/dlice8888/dlice-landing-page/actions/runs/43570024409) | Draft; no independent approval; NOT applied to staging |
| #78 | `20261114150000_atomic_owner_and_tenant_bootstrap.sql` | PASS — [run 43573222955](https://github.com/dlice8888/dlice-landing-page/actions/runs/43573222955) | Draft; no independent approval; NOT applied to staging |

## Static migration observations

- **#76:** Adds a service-role-only summary RPC with a fixed empty search path,
  bounded date range and branch count, supported-timezone checks, and
  disposable pgTAP coverage. Its Edge Function caller must remain restricted
  to the platform Owner and must pass only authorized branch scopes. No live
  data reconciliation or query-plan/performance validation was available.
- **#77:** Adds an optional `updated_by` reference and a service-role-only
  checklist RPC. It locks checklist rows, applies version checks, and writes
  audit rows in the same transaction. The disposable tests cover privilege
  denial, concurrency/version behavior, and rollback on audit failure. Live
  staging permissions, constraints, and audit history were not inspected.
- **#78:** Adds service-role-only owner-bootstrap and tenant-creation RPCs,
  checks trusted Auth metadata, uses an advisory transaction lock for initial
  bootstrap, and writes profile/membership/audit records atomically. The SQL
  reads `auth.users`; it does not modify it. Auth metadata must still be set
  through the official Auth Admin API/dashboard, not SQL. Live Owner state was
  not verified.

## Required staging deployment gate

Obtain independent review and CI on the exact merge commit; compare the
migration against the actual staging schema/history; retain a verified backup
and tested recovery plan; obtain authorized staging migration approval; then
apply through the approved migration path only. Run API/UI, tenant/branch,
Owner, audit, and regression acceptance afterward. No production migration is
authorized by this report.
