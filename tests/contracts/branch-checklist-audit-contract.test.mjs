import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(
  new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url),
  "utf8",
);
const migrationWorkflow = await readFile(
  new URL("../../.github/workflows/disposable-migration-replay.yml", import.meta.url),
  "utf8",
);

const checklistSection = source.slice(
  source.indexOf('if (action === "erp-list-branch-checklists")'),
  source.indexOf('if (action === "erp-list-branches")'),
);

test("checklist mutations use the atomic database workflow", () => {
  for (const action of ["start", "update_item", "complete"]) {
    assert.match(
      checklistSection,
      new RegExp(`dlice_manage_branch_checklist[\\s\\S]*?p_action:\\s*"${action}"`),
    );
  }

  assert.doesNotMatch(
    checklistSection,
    /from\("branch_operation_checklist_runs"\)\s*\.(?:insert|update)\(/,
  );
  assert.doesNotMatch(
    checklistSection,
    /from\("admin_audit_logs"\)\s*\.insert\(/,
  );
});

test("checklist mutation RPC errors never produce success responses", () => {
  assert.match(checklistSection, /if\s*\(\s*error\s*\)\s*return fail\(/);
  assert.match(checklistSection, /result\?\.blocked/);
});

test("disposable CI runs database assertions without logging local credentials", () => {
  assert.match(migrationWorkflow, /cp "\$GITHUB_WORKSPACE"\/supabase\/tests\/\*\.sql supabase\/tests\//);
  assert.match(migrationWorkflow, /supabase test db/);
  assert.ok(migrationWorkflow.includes("grep -viE '(key|secret|password|jwt|token|authorization|bearer)'"));
});


test("all checklist reads and writes derive branch access from active server-side membership", () => {
  const contextHelper = source.slice(
    source.indexOf("const checklistContext = async"),
    source.indexOf("const checklistMutationFailure ="),
  );
  assert.match(contextHelper, /Asia\\/Jakarta.*Asia\\/Makassar.*Asia\\/Jayapura/);
  assert.match(contextHelper, /Zona waktu cabang tidak valid/);
  assert.match(contextHelper, /timeZone: branch\\.timezone/);
  assert.doesNotMatch(contextHelper, /branch\\.timezone \\|\\| "Asia\\/Jakarta"/);

  const accessHelper = source.slice(
    source.indexOf("const branchAccess = async"),
    source.indexOf("const branchIdsForActor = async"),
  );
  assert.match(accessHelper, /branches[\s\S]*?select\("tenant_id"\)[\s\S]*?eq\("id",branchId\)/);
  assert.match(accessHelper, /tenant_memberships[\s\S]*?eq\("tenant_id",branch\.tenant_id\)[\s\S]*?eq\("user_id",actor\.user\.id\)[\s\S]*?eq\("status","active"\)/);
  assert.match(accessHelper, /branch_assignments[\s\S]*?eq\("branch_id",branchId\)[\s\S]*?eq\("user_id",actor\.user\.id\)[\s\S]*?eq\("employment_status","active"\)/);

  for (const action of [
    'if (action === "erp-list-branch-checklists")',
    'if (action === "erp-start-branch-checklist")',
  ]) {
    const start = checklistSection.indexOf(action);
    assert.notEqual(start, -1, `missing ${action}`);
    const next = checklistSection.indexOf('if (action ===', start + action.length);
    const block = checklistSection.slice(start, next === -1 ? undefined : next);
    assert.match(block, /checklistContext\(branchId\)/);
    // checklistContext calls branchAccess before querying the branch row.
  }

  for (const action of [
    'if (action === "erp-update-branch-checklist-item")',
    'if (action === "erp-complete-branch-checklist")',
  ]) {
    const start = checklistSection.indexOf(action);
    assert.notEqual(start, -1, `missing ${action}`);
    const next = checklistSection.indexOf('if (action ===', start + action.length);
    const block = checklistSection.slice(start, next === -1 ? undefined : next);
    assert.match(block, /select\("id,branch_id/);
    assert.match(block, /branchAccess\(run\.branch_id\)/);
    assert.ok(block.indexOf("branchAccess(run.branch_id)") < block.indexOf("admin.rpc("), "authorization must precede the privileged RPC");
  }

  const listBlock = checklistSection.slice(
    checklistSection.indexOf('if (action === "erp-list-branch-checklists")'),
    checklistSection.indexOf('if (action === "erp-start-branch-checklist")'),
  );
  assert.match(listBlock, /\.eq\("branch_id", branchId\)\.eq\("business_date", context\.businessDate\)/);
});
