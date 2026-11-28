import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {createPosPaymentIntent,recordPosTender,ingestPosProviderCallback,reconcilePosSettlement} from "../../src/pos-payment-methods.mjs";
const scope={tenantId:"t1",branchId:"b1",actorId:"u1",saleId:"s1",idempotencyKey:"payment-key"};
const base=()=>({nowMs:()=>1000000,createPaymentIntentAtomically:async x=>({intentId:"i1",tenantId:x.tenantId,branchId:x.branchId,amountIdr:10000,status:"pending"}),
 recordTenderAtomically:async x=>({tenderId:"t1",tenantId:x.tenantId,branchId:x.branchId,paymentStatus:"paid",allocatedTotalIdr:x.amountIdr,remainingIdr:0}),
 verifyProviderSignature:async()=>({valid:true,payloadHash:"sha256:abc"}),
 applyVerifiedProviderEventAtomically:async x=>({status:"applied",eventId:x.eventId,paymentStatus:"paid"}),
 reconcileSettlementAtomically:async x=>({tenantId:x.tenantId,matched:true,varianceIdr:0})});
test("payment intent is created by server with source sale amount",async()=>{const r=await createPosPaymentIntent({...scope,paymentMethod:"qris"},base());assert.equal(r.amountIdr,10000);});
test("record tender rejects split as an individual tender method",async()=>{await assert.rejects(recordPosTender({...scope,paymentMethod:"split",amountIdr:100,verifiedProviderEventId:"evt1"},base()),{code:"POS_PAYMENT_METHOD_INVALID"});});
test("split tender record uses server atomic allocation result",async()=>{const r=await recordPosTender({...scope,paymentMethod:"cash",amountIdr:6000},base());assert.equal(r.paymentStatus,"paid");});
test("rejects unsupported method and unverified non-cash tender",async()=>{await assert.rejects(createPosPaymentIntent({...scope,paymentMethod:"crypto"},base()),{code:"POS_PAYMENT_METHOD_INVALID"});\n await assert.rejects(createPosPaymentIntent({...scope,paymentMethod:"card"},base()),{code:"POS_PAYMENT_PROVIDER_REQUIRED"});const cardIntent=await createPosPaymentIntent({...scope,paymentMethod:"card",providerId:"terminal-1"},base());assert.equal(cardIntent.status,"pending");await assert.rejects(recordPosTender({...scope,paymentMethod:"qris",amountIdr:10000},base()),{code:"POS_PAYMENT_PROVIDER_PROOF_REQUIRED"});\n await assert.rejects(recordPosTender({...scope,paymentMethod:"card",amountIdr:10000},base()),{code:"POS_PAYMENT_PROVIDER_PROOF_REQUIRED"});\n const cardTender=await recordPosTender({...scope,paymentMethod:"card",amountIdr:10000,verifiedProviderEventId:"terminal-event-1"},base());assert.equal(cardTender.paymentStatus,"paid");});
test("provider callback verifies signature, replay window and exact event identity",async()=>{const rawBody=JSON.stringify({id:"evt1",saleId:"s1",amountIdr:10000});const r=await ingestPosProviderCallback({tenantId:"t1",branchId:"b1",providerId:"p1",eventId:"evt1",timestamp:1000000,signature:"sig",rawBody},base());assert.equal(r.status,"applied");await assert.rejects(ingestPosProviderCallback({tenantId:"t1",branchId:"b1",providerId:"p1",eventId:"evt1",timestamp:1,signature:"sig",rawBody,nowMs:1000000},base()),{code:"POS_PAYMENT_REPLAY_WINDOW_EXCEEDED"});await assert.rejects(ingestPosProviderCallback({tenantId:"t1",branchId:"b1",providerId:"p1",eventId:"evt2",timestamp:1000000,signature:"sig",rawBody,nowMs:1000000},base()),{code:"POS_PAYMENT_EVENT_INVALID"});});
test("settlement reconciliation requires exact match",async()=>{const r=await reconcilePosSettlement({tenantId:"t1",actorId:"u1",settlementId:"set1"},base());assert.equal(r.matched,true);await assert.rejects(reconcilePosSettlement({tenantId:"t1",actorId:"u1",settlementId:"set1"},{...base(),reconcileSettlementAtomically:async x=>({tenantId:x.tenantId,matched:false,varianceIdr:1})}),{code:"POS_PAYMENT_SETTLEMENT_MISMATCH"});});


test("card is accepted by cart, order and tender source contracts while provider proof remains mandatory",async()=>{
 const {validatePosCart}=await import("../../src/pos-cart.mjs");
 const {createPosOrderWithFulfillment}=await import("../../src/pos-order-type.mjs");
 const cart=validatePosCart({items:[{slug:"coffee",quantity:1}],paymentMethod:"card"});
 assert.equal(cart.paymentMethod,"card");
 const order=await createPosOrderWithFulfillment({tenantId:"t1",branchId:"b1",actorId:"u1",shiftId:"sh1",
  idempotencyKey:"card-order-1",paymentMethod:"card",orderType:"takeaway",items:[{slug:"coffee",quantity:1}]},{
  createPosOrderAtomically:async x=>({tenantId:x.tenantId,branchId:x.branchId,orderId:"o-card",fulfillmentId:"f-card",
   orderType:x.fulfillment.orderType,paymentStatus:"pending",fulfillmentStatus:"queued"})
 });
 assert.equal(order.paymentStatus,"pending");
});

test("card payment database expansion remains a reviewed draft, not a staging migration",async()=>{
 const draft=await readFile(new URL("../../docs/implementation/sql/POS_PAYMENT_METHODS_DRAFT.sql",import.meta.url),"utf8");
 assert.match(draft,/NOT an official migration/);
 assert.match(draft,/pos_sales_payment_method_check[\s\S]*?'card'/);
 assert.match(draft,/pos_sale_tenders_payment_method_check[\s\S]*?'card'/);
 assert.match(draft,/payment_records_method_check[\s\S]*?'card'/);
 assert.match(draft,/payment_settlements_payment_method_check[\s\S]*?'card'/);
});


test("provider replay window cannot be widened or time-shifted by client input",async()=>{
 const rawBody=JSON.stringify({id:"evt1",saleId:"s1",amountIdr:10000});
 await assert.rejects(ingestPosProviderCallback({tenantId:"t1",branchId:"b1",providerId:"p1",eventId:"evt1",
  timestamp:1,signature:"sig",rawBody,nowMs:1,maxSkewMs:999999999},base()),
  {code:"POS_PAYMENT_REPLAY_WINDOW_EXCEEDED"});
});
