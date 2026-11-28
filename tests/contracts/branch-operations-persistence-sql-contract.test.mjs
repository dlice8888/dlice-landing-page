import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const sql = readFileSync(new URL("../../docs/implementation/sql/BRANCH_OPERATIONS_CONCRETE_PERSISTENCE_DRAFT.sql", import.meta.url), "utf8");
const edge = readFileSync(new URL("../../supabase/functions/branch-operations/index.ts", import.meta.url), "utf8");
const ui = readFileSync(new URL("../../src/branch-operations-ui.mjs", import.meta.url), "utf8");
const erp = readFileSync(new URL("../../erp.html", import.meta.url), "utf8");

test("Branch Operations schema is tenant/branch keyed and RLS protected", () => {
  for (const table of ["branch_ops_equipment","branch_ops_tasks","branch_ops_evidence_assets","branch_ops_incidents","branch_ops_work_orders","branch_ops_compliance_checks","branch_ops_compliance_snapshots"]) {
    assert.match(sql, new RegExp("create table if not exists public\\."+table));
    assert.match(sql, new RegExp("alter table public\\."+table+" enable row level security"));
    assert.match(sql, new RegExp("foreign key \\(tenant_id,branch_id\\) references public\\.branches\\(tenant_id,id\\)"));
  }
  assert.match(sql, /revoke all on public\.branch_ops_equipment[\s\S]*from anon,authenticated/);
  assert.match(sql, /values \('branch-ops-evidence','branch-ops-evidence',false/);
  assert.doesNotMatch(sql, /create policy branch_ops_evidence_(?:upload|read)_scope/);
});

test("Branch Operations SQL function bodies have balanced PostgreSQL dollar delimiters", () => {
  assert.equal((sql.match(/as \\$\\$/g) || []).length, (sql.match(/end \\$\\$;/g) || []).length);
  assert.equal((sql.match(/as \\$\\$/g) || []).length, 13);
});

test("Branch Operations RPCs are atomic server-only entry points with audit events", () => {
  for (const fn of ["branch_ops_create_task","branch_ops_record_incident","branch_ops_create_maintenance_order","branch_ops_register_evidence_asset","branch_ops_submit_compliance_check","branch_ops_review_compliance_check","branch_ops_publish_compliance_snapshot","branch_ops_register_equipment","branch_ops_update_task_status","branch_ops_update_incident_status","branch_ops_update_work_order_status"]) {
    assert.match(sql, new RegExp("create or replace function public\\."+fn));
    assert.match(sql, new RegExp("grant execute on function public\\."+fn));
  }
  assert.match(sql, /perform public\.branch_ops_assert_actor/);
  assert.match(sql, /insert into public\.admin_audit_logs/);
  assert.match(sql, /BRANCH_COMPLIANCE_SEPARATION_OF_DUTIES/);
  assert.match(sql, /branch_ops_assert_approver/);
  assert.match(sql, /BRANCH_TASK_TRANSITION_INVALID/);
  assert.match(sql, /BRANCH_INCIDENT_TRANSITION_INVALID/);
  assert.match(sql, /BRANCH_WORK_ORDER_TRANSITION_INVALID/);
  assert.match(sql, /BRANCH_EVIDENCE_OWNERSHIP_UNVERIFIED/);
});

test("Edge API validates Auth, tenant membership and branch assignment before server-role writes", () => {
  assert.match(edge, /auth\.getUser\(token\)/);
  assert.match(edge, /admin_profiles/);
  assert.match(edge, /tenant_memberships/);
  assert.match(edge, /branch_assignments/);
  assert.match(edge, /service\.storage\.from\("branch-ops-evidence"\)\.upload/);
  assert.match(edge, /createBranchOperationsRepository\(service/);
  for (const action of ["register-equipment","update-task-status","update-incident-status","update-work-order-status"]) assert.match(edge, new RegExp(action));
});

test("ERP Branch Operations UI is wired but remains closed behind the release gate", () => {
  assert.match(erp, /mountBranchOperationsUI/);
  assert.match(erp, /BRANCH_OPS_WORKFLOWS_RELEASED=false/);
  assert.match(erp, /loadBranchOpsWorkflows\(\)/);
  assert.match(ui, /submit-compliance-check/);
  assert.match(ui, /review-compliance-check/);
  assert.match(ui, /upload-evidence/);
  assert.match(ui, /register-equipment/);
  assert.match(ui, /update-work-order-status/);
});
