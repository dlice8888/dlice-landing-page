import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const sql=readFileSync(new URL("../../supabase/migrations/20261128103500_order_state_transition_atomic.sql",import.meta.url),"utf8");
const edge=readFileSync(new URL("../../supabase/functions/dlice-orders/index.ts",import.meta.url),"utf8");
const ui=readFileSync(new URL("../../erp.html",import.meta.url),"utf8");

test("order, payment and fulfillment have independent persisted state and version",()=>{
 assert.match(sql,/add column if not exists state_version integer not null default 1/i);
 assert.match(sql,/operational_status=p_next_status/i);
 assert.match(sql,/payment_status='paid'/i);
 assert.match(sql,/fulfillment_status=p_next_status/i);
 assert.match(sql,/order_state_transition_events/i);
});
test("state RPC is service-role-only, branch-scoped, versioned and idempotent",()=>{
 assert.match(sql,/auth\.jwt\(\)->>'role'\s*<>\s*'service_role'/i);
 assert.match(sql,/pos_actor_can_access_branch\(p_actor_user_id,p_tenant_id,p_branch_id\)/i);
 assert.match(sql,/ORDER_STATE_STALE_VERSION/i);
 assert.match(sql,/ORDER_STATE_IDEMPOTENCY_PAYLOAD_MISMATCH/i);
 assert.match(sql,/unique\(tenant_id,actor_user_id,idempotency_key\)/i);
 assert.match(sql,/grant execute on function public\.pos_transition_order_state_atomic[\s\S]*?to service_role/i);
});
test("payment transitions require verified evidence and reconcile refunds",()=>{
 assert.match(sql,/ORDER_PAYMENT_PROOF_REQUIRED/i);
 assert.match(sql,/ORDER_PROVIDER_PROOF_REQUIRED/i);
 assert.match(sql,/order_reservations set status='consumed'/i);
 assert.match(sql,/ORDER_PARTIAL_REFUND_TOTAL_INVALID/i);
 assert.match(sql,/ORDER_FULL_REFUND_TOTAL_REQUIRED/i);
});
test("fulfillment dispatch requires handover acknowledgement and payment settlement",()=>{
 assert.match(sql,/ORDER_HANDOVER_ACK_REQUIRED/i);
 assert.match(sql,/ORDER_PAYMENT_NOT_SETTLED/i);
 assert.match(edge,/p_domain:"fulfillment"[\s\S]*?p_handover_acknowledgement:handover/i);
 assert.match(ui,/Catat bukti serah-terima kepada kurir/i);
});
test("Edge order/payment/fulfillment routes use the atomic state RPC",()=>{
 assert.equal((edge.match(/admin\.rpc\("pos_transition_order_state_atomic"/g)||[]).length,3);
 assert.match(edge,/p_domain:"order"/);
 assert.match(edge,/p_domain:"payment"/);
 assert.match(edge,/p_domain:"fulfillment"/);
});
