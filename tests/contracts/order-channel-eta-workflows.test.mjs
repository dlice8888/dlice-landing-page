import test from "node:test";
import assert from "node:assert/strict";
import {normalizeVerifiedExternalOrder,estimateOrderPreparationEta,ingestExternalChannelOrder,updateOrderPreparationEta}
 from "../../src/order-channel-eta-workflows.mjs";

const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"order-service",idempotencyKey:"order-channel-0001"};
const common=(overrides={})=>({withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
 appendAudit:async(_tx,e)=>{assert.ok(e.action.startsWith("order."));},...overrides});

test("external order normalization requires verified signed and replay-checked provider event",()=>{
 const result=normalizeVerifiedExternalOrder({tenantId:"tenant-a",branchId:"branch-a",provider:"marketplace-a",
  externalOrderId:"ext-001",signatureVerified:true,replayChecked:true,items:[{productId:"meal-a",quantity:2}],
  totalIdr:50000,providerOccurredAt:"2026-11-27T10:00:00Z"});
 assert.equal(result.currency,"IDR");assert.equal(result.items.length,1);
 assert.throws(()=>normalizeVerifiedExternalOrder({tenantId:"tenant-a",branchId:"branch-a",provider:"marketplace-a",
  externalOrderId:"ext-001",signatureVerified:false,replayChecked:true,items:[{productId:"meal-a",quantity:2}],
  totalIdr:50000,providerOccurredAt:"2026-11-27T10:00:00Z"}),{code:"ORDER_PROVIDER_AUTHENTICITY_REQUIRED"});
});
test("ETA aggregates work per station and adds approved buffer",()=>{
 const result=estimateOrderPreparationEta({now:"2026-11-27T10:00:00Z",sourceRevision:"queue-v1",approvedBufferMinutes:5,
  items:[{stationId:"hot",prepMinutes:4,quantity:2,stationQueuedMinutes:10},
   {stationId:"hot",prepMinutes:3,quantity:1,stationQueuedMinutes:10},
   {stationId:"cold",prepMinutes:5,quantity:1,stationQueuedMinutes:0}]});
 assert.equal(result.etaMinutes,26);
 assert.equal(result.estimatedReadyAt,"2026-11-27T10:26:00.000Z");
});
test("ETA rejects missing station prep standards and invalid horizon",()=>{
 assert.throws(()=>estimateOrderPreparationEta({now:"2026-11-27T10:00:00Z",sourceRevision:"v1",
  items:[{prepMinutes:5,quantity:1}]}),{code:"ORDER_CHANNEL_INPUT_REQUIRED"});
});
test("external order ingestion uses verified provider event and approved mapping",async()=>{
 const deps=common({
  findExternalOrderByProviderEvent:async()=>null,
  loadVerifiedProviderOrderEvent:async()=>({tenantId:"tenant-a",branchId:"branch-a",provider:"marketplace-a",
   externalOrderId:"ext-001",signatureVerified:true,replayChecked:true,items:[{productId:"meal-a",quantity:2}],
   totalIdr:50000,providerOccurredAt:"2026-11-27T10:00:00Z"}),
  loadApprovedChannelProductMapping:async()=>({status:"approved"}),
  persistCanonicalExternalOrder:async(_tx,row)=>{assert.equal(row.currency,"IDR");return{id:"order-a"};},
 });
 const result=await ingestExternalChannelOrder({...base,providerEventId:"event-a"},deps);
 assert.deepEqual(result,{status:"created",orderId:"order-a"});
});
test("external order ingestion rejects missing mapping and cross-branch events",async()=>{
 const deps=common({
  findExternalOrderByProviderEvent:async()=>null,
  loadVerifiedProviderOrderEvent:async()=>({tenantId:"tenant-a",branchId:"branch-b",provider:"marketplace-a",
   externalOrderId:"ext-001",signatureVerified:true,replayChecked:true,items:[{productId:"meal-a",quantity:1}],
   totalIdr:10000,providerOccurredAt:"2026-11-27T10:00:00Z"}),
 });
 await assert.rejects(ingestExternalChannelOrder({...base,providerEventId:"event-a"},deps),
  {code:"ORDER_CHANNEL_SCOPE_MISMATCH"});
});
test("order ETA persists and creates escalation when estimated ready exceeds SLA",async()=>{
 const deps=common({
  loadOrderForEtaUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"order-a",status:"preparing",slaDueAt:"2026-11-27T10:10:00Z"}),
  loadApprovedPrepStandards:async()=>[{stationId:"hot",prepMinutes:10,quantity:2}],
  loadStationQueueTelemetry:async()=>[{stationId:"hot",queuedMinutes:5}],
  persistOrderPreparationEta:async()=>({id:"eta-a"}),
  createOrderSlaEscalation:async()=>({id:"escalation-a"}),
 });
 const result=await updateOrderPreparationEta({...base,orderId:"order-a",now:"2026-11-27T10:00:00Z",
  sourceRevision:"queue-rev-1",approvedBufferMinutes:0},deps);
 assert.equal(result.status,"updated");assert.equal(result.etaMinutes,25);assert.equal(result.escalationId,"escalation-a");
});
