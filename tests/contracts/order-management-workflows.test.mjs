import test from "node:test";
import assert from "node:assert/strict";
import { buildUnifiedOrderQueue } from "../../src/order-unified-queue.mjs";
import { quoteBranchAvailability } from "../../src/order-availability-policy.mjs";
import { chooseOrderBranch } from "../../src/order-branch-router.mjs";
import { formatBusinessOrderNumber, assertOrderNumberRetry } from "../../src/business-order-number.mjs";
import { appendOrderTimelineEvent } from "../../src/order-timeline.mjs";
import { validateOrderCancellation, buildCustomerOrderHistory } from "../../src/order-cancellation-history.mjs";
import { prepareOrderNotification, evaluateNotificationAttempt } from "../../src/order-notification-dispatcher.mjs";

const now="2026-11-28T10:00:00.000Z";

test("unified order queue deduplicates canonical records and enforces tenant and branch scope",()=>{
 const pos=[{id:"o1",tenant_id:"t1",branch_id:"b1",created_at:"2026-11-28T09:00:00Z",order_status:"received",payment_status:"unpaid",fulfillment_status:"unassigned"}];
 const online=[{...pos[0],channel:"online",external_order_id:"ext-1"},{id:"o2",tenant_id:"t2",branch_id:"b1",created_at:"2026-11-28T09:00:00Z"}];
 const rows=buildUnifiedOrderQueue({posOrders:pos,onlineOrders:online,tenantId:"t1",allowedBranchIds:["b1"],now});
 assert.equal(rows.length,1);assert.deepEqual(rows[0].channels,["pos","online"]);
 assert.throws(()=>buildUnifiedOrderQueue({posOrders:pos,tenantId:"t1",allowedBranchIds:[],now}),/ORDER_QUEUE_SCOPE_REQUIRED/);
 assert.throws(()=>buildUnifiedOrderQueue({posOrders:[{...pos[0],id:"o3",external_order_id:"x"},{...pos[0],id:"o4",external_order_id:"x"}],tenantId:"t1",allowedBranchIds:["b1"],now}),/ORDER_QUEUE_EXTERNAL_ID_COLLISION/);
 assert.throws(()=>buildUnifiedOrderQueue({posOrders:[pos[0]],onlineOrders:[{...pos[0],order_status:"cancelled"}],tenantId:"t1",allowedBranchIds:["b1"],now}),/ORDER_QUEUE_SOURCE_STATUS_MISMATCH/);
});

test("availability enforces branch timezone, holiday, operating hours, cutoff and capacity",()=>{
 const hours={Sat:{open:"09:00",close:"21:00"}};
 const base={now,timezone:"Asia/Jakarta",operatingHours:hours,capacityUsed:2,capacityLimit:5,requestedAt:"2026-11-28T03:00:00Z"};
 assert.equal(quoteBranchAvailability(base).available,true);
 assert.equal(quoteBranchAvailability({...base,holidayDates:["2026-11-28"]}).reason,"holiday");
 assert.equal(quoteBranchAvailability({...base,capacityUsed:5}).reason,"capacity_full");
 assert.equal(quoteBranchAvailability({...base,cutoffMinutes:700}).reason,"cutoff_passed");
 assert.throws(()=>quoteBranchAvailability({...base,timezone:"UTC"}),/TIMEZONE_INVALID/);
});

test("branch router selects nearest eligible same-tenant branch and rejects client override",()=>{
 const branches=[
  {id:"far",tenant_id:"t1",status:"active",latitude:-6.3,longitude:106.8,service_radius_km:20,capacity_used:1,capacity_limit:5},
  {id:"near",tenant_id:"t1",status:"active",latitude:-6.2,longitude:106.8,service_radius_km:20,capacity_used:2,capacity_limit:5},
  {id:"other",tenant_id:"t2",status:"active",latitude:-6.2,longitude:106.8,service_radius_km:20,capacity_used:0,capacity_limit:5},
 ];
 const result=chooseOrderBranch({tenantId:"t1",latitude:-6.201,longitude:106.8,branches});
 assert.equal(result.branch_id,"near");
 assert.throws(()=>chooseOrderBranch({tenantId:"t1",latitude:-6.2,longitude:106.8,branches,requestedBranchId:"far"}),/OVERRIDE_FORBIDDEN/);
 const polygonBranch={id:"poly",tenant_id:"t1",status:"active",latitude:-6.2,longitude:106.8,service_area_polygon:[{latitude:-6.21,longitude:106.79},{latitude:-6.19,longitude:106.79},{latitude:-6.19,longitude:106.81},{latitude:-6.21,longitude:106.81}],capacity_used:0,capacity_limit:5};
 assert.equal(chooseOrderBranch({tenantId:"t1",latitude:-6.2,longitude:106.8,branches:[polygonBranch]}).branch_id,"poly");
});

test("business order number is deterministic and idempotent retry does not regenerate",()=>{
 const number=formatBusinessOrderNumber({businessDate:"2026-11-28",sequence:12,branchCode:"JKT01"});
 assert.equal(number,"DLC-20261128-JKT01-000012");
 assert.equal(assertOrderNumberRetry({existingNumber:number,idempotencyKey:"order-key-0000001",requestedIdempotencyKey:"order-key-0000001"}).generate_only_if_absent,false);
 assert.throws(()=>formatBusinessOrderNumber({businessDate:"2026-02-31",sequence:1,branchCode:"JKT01"}),/BUSINESS_DATE_INVALID/);
 assert.throws(()=>assertOrderNumberRetry({existingNumber:number,idempotencyKey:"old",requestedIdempotencyKey:"new-idempotency-key"}),/IDEMPOTENCY_CONFLICT/);
});

test("timeline events are append-only, versioned, actor-owned and idempotent",()=>{
 const command=appendOrderTimelineEvent({orderId:"o1",tenantId:"t1",branchId:"b1",fromStatus:"received",toStatus:"confirmed",actorDomain:"branch",actorId:"u1",expectedVersion:2,currentVersion:2,sourceEventId:"evt-1",occurredAt:now});
 assert.equal(command.version,3);assert.equal(command.append_only,true);
 assert.equal(appendOrderTimelineEvent({orderId:"o1",tenantId:"t1",branchId:"b1",fromStatus:"received",toStatus:"confirmed",actorDomain:"branch",expectedVersion:2,currentVersion:3,sourceEventId:"evt-1",occurredAt:now,existingSourceEventIds:["evt-1"]}).duplicate,true);
 assert.throws(()=>appendOrderTimelineEvent({orderId:"o1",tenantId:"t1",branchId:"b1",fromStatus:"received",toStatus:"completed",actorDomain:"branch",expectedVersion:2,currentVersion:2,sourceEventId:"evt-2",occurredAt:now}),/TRANSITION_INVALID/);
});

test("paid cancellation requires refund compensation and customer history is owner scoped",()=>{
 const order={id:"o1",branch_id:"b1",customer_id:"cust-1",order_status:"confirmed",payment_status:"paid",fulfillment_status:"unassigned",created_at:now,order_number:"DLC-1"};
 assert.throws(()=>validateOrderCancellation({order,actor:{kind:"staff",user_id:"u1",allowed_branch_ids:["b1"]},reason:"Customer requested cancellation",refundRequired:false}),/REFUND_COMPENSATION_REQUIRED/);
 const result=validateOrderCancellation({order,actor:{kind:"staff",user_id:"u1",allowed_branch_ids:["b1"]},reason:"Customer requested cancellation",refundRequired:true,compensationAdaptersReady:true,refundIdempotencyKey:"refund-key-0000001"});
 assert.equal(result.refund_required,true);
 assert.throws(()=>buildCustomerOrderHistory({orders:[order],customerId:"cust-1",actor:{kind:"customer",user_id:"cust-2"}}),/CUSTOMER_FORBIDDEN/);
 assert.throws(()=>validateOrderCancellation({order,actor:{kind:"customer",user_id:"attacker"},customerId:"cust-1",reason:"Customer requested cancellation"}),/HISTORY_CUSTOMER_FORBIDDEN/);
 assert.equal(buildCustomerOrderHistory({orders:[order],customerId:"cust-1",actor:{kind:"customer",user_id:"cust-1"}}).length,1);
});

test("notification outbox respects consent and retry exhaustion dead letters",()=>{
 const input={orderId:"o1",tenantId:"t1",customerId:"c1",eventId:"e1",eventType:"order_confirmed",channel:"whatsapp",destination:"+628123456789",consent:{whatsapp:"granted"},preferences:{whatsapp:true},templateVersion:"v1"};
 assert.equal(prepareOrderNotification(input).dispatch,true);
 assert.equal(prepareOrderNotification({...input,consent:{whatsapp:"withdrawn"}}).reason,"customer_opt_out");
 assert.equal(evaluateNotificationAttempt({attemptCount:2,maxAttempts:3,providerResult:"timeout"}).status,"dead_letter");
 assert.equal(evaluateNotificationAttempt({attemptCount:0,maxAttempts:3,providerResult:"timeout",nextAttemptAt:"2026-11-28T10:05:00Z"}).status,"retry");
});
