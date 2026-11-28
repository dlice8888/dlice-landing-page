import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const edge=readFileSync(new URL("../../supabase/functions/dlice-orders/index.ts",import.meta.url),"utf8");
test("split tender Edge action scopes branch and delegates atomic checkout to the existing RPC",()=>{
 const start=edge.indexOf('if (action === "erp-create-pos-sale-split-tender")');
 const end=edge.indexOf('if (action === "erp-create-pos-sale")',start);
 assert.ok(start>=0&&end>start);
 const action=edge.slice(start,end);
 assert.match(action,/branchAccess\(branchId\)/);
 assert.match(action,/erp_create_pos_sale_split_tender_idempotent/);
 assert.match(action,/p_actor_user_id:actor\.user\.id/);
 assert.match(action,/p_idempotency_key:idempotencyKey/);
 assert.match(action,/split_tender_total_mismatch/);
 assert.match(action,/\["cash","bank_transfer","qris"\]/);
 assert.doesNotMatch(action,/body\.tenant_id|body\.payment_status|from\(["']pos_sales["']\)\.insert/);
});

test("split tender action is included in central POS permission map",()=>{
 assert.match(edge,/"erp-create-pos-sale-split-tender": "pos"/);
});
