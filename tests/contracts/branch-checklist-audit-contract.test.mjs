import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(
  new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url),
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
