import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";

const edge=await readFile(new URL("../../supabase/functions/dlice-orders/index.ts",import.meta.url),"utf8");
const migration=await readFile(new URL("../../supabase/migrations/20261128102000_executive_approval_center.sql",import.meta.url),"utf8");
test("refund review claims the tenant-scoped unified approval before deciding",()=>{
 const start=edge.indexOf('if (action === "erp-review-refund")');
 const end=edge.indexOf('if (action === "erp-process-refund")',start);
 assert.ok(start>=0&&end>start);
 const block=edge.slice(start,end);
 const claim=block.indexOf('admin.rpc("claim_approval"');
 const decide=block.indexOf('admin.rpc("decide_approval"');
 assert.ok(claim>=0&&decide>claim,"approval must be claimed before decision");
 assert.match(block,/claimed_by/);
 assert.match(block,/claim_expires_at/);
 assert.match(block,/decisionVersion/);
});
test("POS refund processing fails closed until compensating financial and stock effects are atomic",()=>{
 const start=edge.indexOf('if (action === "erp-process-refund")');
 const end=edge.indexOf('if (action === "erp-',start+20);
 const block=edge.slice(start,end<0?undefined:end);
 assert.match(block,/POS_REFUND_COMPENSATION_NOT_READY/);
});
test("refund request automatically enters Finance approval queue with source version",()=>{
 assert.match(migration,/create trigger enqueue_refund_approval after insert or update of status on public\.refund_records/i);
 assert.match(migration,/enqueue_executive_approval\(v_tenant,'finance','refund_record'/i);
 assert.match(migration,/APPROVAL_SOURCE_STALE/);
});
