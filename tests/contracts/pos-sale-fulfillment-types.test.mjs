import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const sql=readFileSync(new URL("../../supabase/migrations/20261128104000_pos_sale_fulfillment_types.sql",import.meta.url),"utf8");
const edge=readFileSync(new URL("../../supabase/functions/dlice-orders/index.ts",import.meta.url),"utf8");
const ui=readFileSync(new URL("../../erp.html",import.meta.url),"utf8");
const adapter=readFileSync(new URL("../../src/supabase-pos-workflow-adapter.mjs",import.meta.url),"utf8");

test("POS fulfillment persists all four order types with type-specific required details",()=>{
 assert.match(sql,/order_type in \('dine_in','takeaway','pickup','delivery'\)/i);
 assert.match(sql,/POS_ORDER_TYPE_DETAILS_INVALID/i);
 assert.match(sql,/table_code text/i);
 assert.match(sql,/pickup_at timestamptz/i);
 assert.match(sql,/delivery_address text/i);
 assert.match(sql,/delivery_area_id text/i);
});
test("POS order and fulfillment creation is one service-role atomic RPC",()=>{
 assert.match(sql,/pos_create_order_with_fulfillment_atomic/i);
 assert.match(sql,/erp_create_pos_sale_idempotent/i);
 assert.match(sql,/erp_create_pos_sale_split_tender_idempotent/i);
 assert.match(sql,/pg_advisory_xact_lock/i);
 assert.match(sql,/POS_FULFILLMENT_IDEMPOTENCY_PAYLOAD_MISMATCH/i);
 assert.match(sql,/grant execute on function public\.pos_create_order_with_fulfillment_atomic[\s\S]*?to service_role/i);
});
test("pickup time uses branch timezone and delivery data is mandatory",()=>{
 assert.match(sql,/at time zone v_branch\.timezone/i);
 assert.match(sql,/v_type='delivery' and \(v_delivery_address is null or v_delivery_area_id is null\)/i);
 assert.match(sql,/POS_PICKUP_TIME_IN_PAST/i);
});
test("Edge, adapter and POS UI use the fulfillment workflow",()=>{
 assert.match(edge,/admin\.rpc\("pos_create_order_with_fulfillment_atomic"/i);
 assert.match(edge,/pos_sale_fulfillments\(order_type,table_code,pickup_at,delivery_address,delivery_area_id,order_status,fulfillment_status,version\)/i);
 assert.match(adapter,/createPosOrderAtomically:async/i);
 for(const id of ["posOrderType","posTableCode","posPickupAt","posDeliveryAddress","posDeliveryArea"])assert.match(ui,new RegExp(id));
 assert.match(ui,/order_type:orderType/);
});
