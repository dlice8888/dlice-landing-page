import test from "node:test";
import assert from "node:assert/strict";
import { applyDeliveryProviderEvent } from "../../src/delivery-fulfillment-reconciliation.mjs";
const input={tenantId:"tenant-a",branchId:"branch-a",actorId:"delivery-a",orderId:"order-a",providerEventId:"evt-a",idempotencyKey:"delivery-evt-0001"};
const make=(overrides={})=>({withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
 findProviderEvent:async()=>null,
 loadVerifiedProviderEvent:async()=>({tenantId:"tenant-a",branchId:"branch-a",providerEventId:"evt-a",provider:"provider-a",
  signatureVerified:true,replayChecked:true,currentStatus:"in_transit",nextStatus:"delivered",occurredAt:"2026-11-28T10:00:00Z",
  deliveredAt:"2026-11-28T10:00:00Z",proofReference:"private://proof-a"}),
 loadOrderForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"preparing",deliveryStatus:"in_transit"}),
 verifyPrivateDeliveryProof:async()=>true,persistDeliveryTransition:async()=>({id:"delivery-a"}),
 reconcileDeliveryCharge:async()=>({id:"charge-a",tenantId:"tenant-a",branchId:"branch-a",reconciled:true}),
 appendAudit:async()=>{},...overrides});
test("delivered transition requires authenticated provider event, private proof and reconciled fee",async()=>{
 const r=await applyDeliveryProviderEvent(input,make());assert.equal(r.status,"applied");assert.equal(r.deliveryStatus,"delivered");
});
test("idempotent provider retry does not repeat transition or charge reconciliation",async()=>{
 assert.deepEqual(await applyDeliveryProviderEvent(input,make({findProviderEvent:async()=>({deliveryId:"delivery-old"})})),{status:"duplicate",deliveryId:"delivery-old"});
});
test("rejects invalid provider authentication, cross-branch order and missing proof",async()=>{
 await assert.rejects(applyDeliveryProviderEvent(input,make({loadVerifiedProviderEvent:async()=>({tenantId:"tenant-a",branchId:"branch-a",providerEventId:"evt-a",signatureVerified:false,replayChecked:true})})),{code:"DELIVERY_PROVIDER_AUTHENTICITY_REQUIRED"});
 await assert.rejects(applyDeliveryProviderEvent(input,make({loadOrderForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-b"})})),{code:"DELIVERY_SCOPE_MISMATCH"});
 await assert.rejects(applyDeliveryProviderEvent(input,make({verifyPrivateDeliveryProof:async()=>false})),{code:"DELIVERY_PROOF_UNVERIFIED"});
});
test("rejects invalid transition, state conflict and unreconciled provider fee",async()=>{
 await assert.rejects(applyDeliveryProviderEvent(input,make({loadVerifiedProviderEvent:async()=>({tenantId:"tenant-a",branchId:"branch-a",providerEventId:"evt-a",signatureVerified:true,replayChecked:true,currentStatus:"delivered",nextStatus:"in_transit"})})),{code:"DELIVERY_TRANSITION_INVALID"});
 await assert.rejects(applyDeliveryProviderEvent(input,make({loadOrderForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"preparing",deliveryStatus:"picked_up"})})),{code:"DELIVERY_STATE_CONFLICT"});
 await assert.rejects(applyDeliveryProviderEvent(input,make({reconcileDeliveryCharge:async()=>({tenantId:"tenant-a",branchId:"branch-a",reconciled:false})})),{code:"DELIVERY_CHARGE_UNRECONCILED"});
});
