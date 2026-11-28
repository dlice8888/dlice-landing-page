import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const ui = await readFile(new URL("../../erp.html", import.meta.url), "utf8");
const edge = await readFile(new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url), "utf8");

test("approval center exposes pending queue, source evidence, reasoned decisions and history", () => {
  for (const marker of ["executiveApprovalList","approvalReason-","loadApprovalHistory","approvalHistoryList","erp-list-approval-history"]) {
    assert.ok(ui.includes(marker) || edge.includes(marker), `missing approval UI marker: ${marker}`);
  }
  assert.match(ui, /data-approval-claim/);
  assert.match(ui, /data-approval-decision/);
  assert.match(ui, /idempotency_key:crypto\.randomUUID\(\)/);
});

test("approval center exposes scoped delegation create, list and revoke", () => {
  for (const marker of ["createApprovalDelegation","loadApprovalDelegations","approvalDelegationList","erp-create-approval-delegation","erp-list-approval-delegations","erp-revoke-approval-delegation"]) {
    assert.ok(ui.includes(marker) || edge.includes(marker), `missing delegation UI marker: ${marker}`);
  }
  assert.match(ui, /data-revoke-approval-delegation/);
});
