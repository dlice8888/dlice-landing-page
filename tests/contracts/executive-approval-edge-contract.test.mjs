import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const edge=readFileSync(new URL("../../supabase/functions/dlice-orders/index.ts",import.meta.url),"utf8");
test("approval inbox, claim and decision actions are scoped by server-derived branch membership",()=>{
 const start=edge.indexOf('if (["erp-list-pending-approvals","erp-claim-approval","erp-decide-approval"]');
 const end=edge.indexOf('if (action === "erp-executive-sales-monitor")',start);
 assert.ok(start>=0&&end>start);
 const action=edge.slice(start,end);
 assert.match(action,/branchIdsForActor\(\)/);
 assert.match(action,/p_allowed_branch_ids:allowedBranchIds/);
 assert.match(action,/list_pending_approvals/);
 assert.match(action,/claim_approval/);
 assert.match(action,/decide_approval/);
 assert.match(action,/p_actor_user_id:actor\.user\.id/);
 assert.match(action,/p_expected_version:expectedVersion/);
 assert.match(action,/p_idempotency_key:idempotencyKey/);
 assert.doesNotMatch(action,/body\.tenant_id|body\.role|from\(["']purchase_orders["']\)\.update/);
});
test("approval decision rejects malformed reason, decision and idempotency key before RPC",()=>{
 const start=edge.indexOf('if (["erp-list-pending-approvals","erp-claim-approval","erp-decide-approval"]');
 const end=edge.indexOf('if (action === "erp-executive-sales-monitor")',start);
 const action=edge.slice(start,end);
 assert.match(action,/reason\.length<8/);
 assert.match(action,/idempotencyKey\.length<16/);
 assert.match(action,/\["approved","rejected"\]/);
});
