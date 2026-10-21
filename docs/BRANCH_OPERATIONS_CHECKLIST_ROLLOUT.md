# Branch Operations Checklist — Staging Rollout Notes

Date: 2026-10-22
Scope: first vertical slice for the D’Lice FnB OS Branch Operations domain.
Target: Supabase staging `higoadrzxnhzbbwhdbmh` and the Vercel Preview for this branch only.

## Implemented in this slice

- Daily opening and closing checklist runs, unique by branch + local business date + checklist type.
- Versioned item snapshot copied into each run so a future template change does not silently rewrite historical runs.
- Checklist date derived from the branch's configured IANA timezone.
- Runs may be started only for active branches.
- Each API action requires the `branches` permission and validates the user's active branch assignment; Owner is global.
- Checklist records have RLS enabled, a restrictive deny policy for `anon` and `authenticated`, and no direct client table grants.
- Item updates use optimistic version checks to avoid silently overwriting concurrent changes.
- Failed items require notes. Checklist completion is blocked unless all items are checked and every critical item passes.
- Start, item update, blocked completion, and successful completion are written to `admin_audit_logs`.
- Completed runs are immutable through these actions.

## Staging rollout order

1. Review CI and the SQL migration in this draft PR.
2. Apply migration `20261021182634_branch_operation_checklists.sql` to the staging project only.
3. Deploy the branch's `dlice-orders` Edge Function source to staging only.
4. Verify table RLS and grants; verify no direct Data API access is possible.
5. Run authenticated tests for Owner, assigned Branch A manager, wrong-branch manager, no-permission user, and inactive user.
6. Verify opening and closing runs, duplicate start idempotency, item notes, critical failure blocking, version conflict handling, immutable completed runs, and local dates across WIB/WITA/WIT.
7. Run mobile/tablet/desktop browser acceptance on the Preview. A READY deployment is not a substitute for this test.
8. Do not merge or deploy to production until all P0 checks pass and the Owner explicitly approves.

## Deliberate limits

This slice is not a full SOP platform. It does not yet include configurable checklist templates, photo/file evidence, calibrated food-safety temperature capture, equipment-maintenance workflows, corrective-action assignment/verification, reminders, escalation, or a branch opening gate that automatically changes operating status. Those require separate domain slices and acceptance tests.

## Rollback

The migration is additive. If runtime validation fails, disable the new navigation/action use by reverting the feature branch; do not drop the table while audit evidence may exist. Keep the table in staging until the failure is understood. No production change is part of this rollout.
