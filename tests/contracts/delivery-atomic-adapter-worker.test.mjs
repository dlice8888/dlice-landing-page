import test from "node:test";
import assert from "node:assert/strict";
import { createSupabaseDeliveryAdapter } from "../../src/supabase-delivery-adapter.mjs";
import { runDeliveryOutboxBatch } from "../../src/workers/delivery-outbox-worker.mjs";

test("Delivery adapter delegates state changes to single atomic RPCs",async()=>{
 const calls=[];const adapter=createSupabaseDeliveryAdapter({rpc:async(name,args)=>{calls.push({name,args});return {data:{ok:true},error:null}}});
 await adapter.bookDispatchFromQuote({tenantId:"t",branchId:"b",quoteId:"q",idempotencyKey:"delivery-idem-1",actorId:"u"});
 await adapter.claimOutboxBatch({workerId:"worker-1",limit:5});
 await adapter.reconcileCost({tenantId:"t",branchId:"b",dispatchId:"d",customerFeeIdr:100,merchantSubsidyIdr:0,codExpectedIdr:0,codCollectedIdr:0,codRemittedIdr:0,courierCostExpectedIdr:100,courierCostFinalIdr:100,providerSettlementIdr:95,providerFeeIdr:5,financeJournalEntryId:"j",evidenceSha256:"a".repeat(64),actorId:"u"});
 assert.deepEqual(calls.map(x=>x.name),["delivery_book_dispatch_from_quote","delivery_claim_outbox_batch","delivery_reconcile_cost"]);
});

test("worker books only with an API provider and secret, then confirms and completes",async()=>{
 const calls=[];const adapter={
  claimOutboxBatch:async()=>[{id:"outbox-1",tenant_id:"t",dispatch_id:"d",event_type:"book",idempotency_key:"delivery-book-1"}],
  getOutboxJobContext:async()=>({provider_config:{provider_key:"carrier-x",integration_mode:"api",credential_secret_reference:"CARRIER_X_KEY"},dispatch:{id:"d",created_by:"owner"},quote:{id:"q"},order:{id:"o"}}),
  confirmProviderBooking:async x=>calls.push(["confirm",x.succeeded]),
  finishOutbox:async x=>{calls.push(["finish",x.succeeded]);return {status:x.succeeded?"completed":"retry"}}
 };
 const result=await runDeliveryOutboxBatch({adapter,providerAdapters:{"carrier-x":{book:async()=>({success:true,bookingReference:"BOOK-1"})}},loadSecret:async()=> "secret",workerId:"worker-1"});
 assert.equal(result[0].status,"completed");assert.deepEqual(calls,[["confirm",true],["finish",true]]);
});

test("worker fails closed if secret or provider adapter is missing",async()=>{
 const calls=[];const adapter={
  claimOutboxBatch:async()=>[{id:"outbox-1",tenant_id:"t",dispatch_id:"d",event_type:"book",idempotency_key:"delivery-book-1"}],
  getOutboxJobContext:async()=>({provider_config:{provider_key:"carrier-x",integration_mode:"api",credential_secret_reference:"MISSING"},dispatch:{id:"d",created_by:"owner"}}),
  confirmProviderBooking:async()=>calls.push("confirm"),
  finishOutbox:async x=>{calls.push(x.errorCode);return {status:"retry"}}
 };
 const result=await runDeliveryOutboxBatch({adapter,providerAdapters:{},loadSecret:async()=>null,workerId:"worker-1"});
 assert.equal(result[0].errorCode,"DELIVERY_PROVIDER_SECRET_UNAVAILABLE");assert.deepEqual(calls,["DELIVERY_PROVIDER_SECRET_UNAVAILABLE"]);
});
