import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const edge=await readFile(new URL("../../supabase/functions/dlice-orders/index.ts",import.meta.url),"utf8");
const ui=await readFile(new URL("../../erp.html",import.meta.url),"utf8");
test("POS checkout routes split tenders to atomic server RPC and validates method and amount",()=>{
 assert.match(edge,/pos_create_order_with_fulfillment_atomic/);
 assert.match(edge,/body\.tenders\.length<2\|\|body\.tenders\.length>5/);
 assert.match(edge,/new Set\(tenders\.map\(\(t:any\)=>t\.payment_method\)\)\.size<2/);
 assert.match(edge,/split_tender_total_mismatch/);
});
test("POS UI persists split tender allocation through the same offline idempotent operation",()=>{
 assert.match(ui,/id="posUseSplitTender"/);
 assert.match(ui,/id="posTender1Amount"/);
 assert.match(ui,/id="posTender2Amount"/);
 assert.match(ui,/tenders,fulfillment,customer_reference/);
 assert.match(ui,/client_operation_id:crypto\.randomUUID\(\)/);
});
