/**
 * External order ingestion and preparation ETA/SLA escalation.
 * Provider authenticity and source mapping are verified by server-side adapters.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("ORDER_CHANNEL_INPUT_REQUIRED",f);return v.trim();};
const adapter=(d,n)=>{if(typeof d?.[n]!=="function")fail("ORDER_CHANNEL_ADAPTER_REQUIRED",n);return d[n];};
const scope=(i,a)=>({tenantId:req(i?.tenantId,"tenantId"),branchId:req(i?.branchId,"branchId"),
 actorId:req(i?.actorId,"actorId"),idempotencyKey:req(i?.idempotencyKey,"idempotencyKey"),action:a});
const txScope=(d,s,fn)=>adapter(d,"withTenantTransaction")(s,async tx=>{
 if(!tx)fail("ORDER_CHANNEL_TRANSACTION_REQUIRED","Database transaction required");
 await adapter(d,"authorize")(tx,s);return fn(tx);
});
const assertScope=(r,s,n)=>{if(!r||r.tenantId!==s.tenantId||r.branchId!==s.branchId)fail("ORDER_CHANNEL_SCOPE_MISMATCH",n);};

/** Normalize a provider-verified external order to canonical order facts. */
export function normalizeVerifiedExternalOrder(input){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId");
 const provider=req(input?.provider,"provider"),externalOrderId=req(input?.externalOrderId,"externalOrderId");
 if(input.signatureVerified!==true||input.replayChecked!==true)fail("ORDER_PROVIDER_AUTHENTICITY_REQUIRED","Signed provider event and replay protection must be verified");
 if(!Array.isArray(input.items)||!input.items.length)fail("ORDER_PROVIDER_ITEMS_REQUIRED","External order requires items");
 const items=input.items.map(item=>{
  const productId=req(item.productId,"productId"),quantity=Number(item.quantity);
  if(!Number.isFinite(quantity)||quantity<=0)fail("ORDER_PROVIDER_QUANTITY_INVALID","Item quantity must be positive");
  return Object.freeze({productId,quantity,modifiers:Array.isArray(item.modifiers)?item.modifiers:[]});
 });
 const total=Number(input.totalIdr);
 if(!Number.isSafeInteger(total)||total<0)fail("ORDER_PROVIDER_TOTAL_INVALID","Provider total must be integer IDR");
 return Object.freeze({tenantId,branchId,provider,externalOrderId,items:Object.freeze(items),
  totalIdr:total,currency:"IDR",customerReference:input.customerReference??null,
  providerOccurredAt:req(input.providerOccurredAt,"providerOccurredAt")});
}

/** Calculate prep ETA from approved prep standards and live station queue telemetry. */
export function estimateOrderPreparationEta(input){
 const now=Date.parse(req(input.now,"now"));
 if(!Number.isFinite(now)||!Array.isArray(input.items)||!input.items.length)fail("ORDER_ETA_INPUT_INVALID","Now and order items are required");
 let workloadMinutes=0;
 for(const item of input.items){
  const standard=Number(item.prepMinutes),quantity=Number(item.quantity),queued=Number(item.stationQueuedMinutes??0);
  if(!Number.isFinite(standard)||standard<0||!Number.isFinite(quantity)||quantity<=0||!Number.isFinite(queued)||queued<0)
   fail("ORDER_ETA_STANDARD_INVALID","Prep standards and queue minutes must be non-negative");
  workloadMinutes=Math.max(workloadMinutes,queued+standard*quantity);
 }
 const buffer=Number(input.approvedBufferMinutes??0);
 if(!Number.isFinite(buffer)||buffer<0)fail("ORDER_ETA_BUFFER_INVALID","Approved buffer must be non-negative");
 const etaMinutes=Math.ceil(workloadMinutes+buffer);
 return Object.freeze({etaMinutes,estimatedReadyAt:new Date(now+etaMinutes*60000).toISOString(),
  sourceRevision:req(input.sourceRevision,"sourceRevision")});
}

/** Ingest verified provider order idempotently into canonical tenant/branch Order. */
export async function ingestExternalChannelOrder(input,deps){
 const s=scope(input,"order.external_channel.ingest"),eventId=req(input.providerEventId,"providerEventId");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findExternalOrderByProviderEvent")(tx,{...s,eventId});
  if(prior)return Object.freeze({status:"duplicate",orderId:prior.id});
  const verified=await adapter(deps,"loadVerifiedProviderOrderEvent")(tx,{...s,eventId});
  assertScope(verified,s,"providerEvent");
  if(verified.signatureVerified!==true||verified.replayChecked!==true)fail("ORDER_PROVIDER_AUTHENTICITY_REQUIRED","Provider event verification failed");
  const mapping=await adapter(deps,"loadApprovedChannelProductMapping")(tx,{...s,provider:verified.provider});
  if(!mapping||mapping.status!=="approved")fail("ORDER_CHANNEL_MAPPING_NOT_APPROVED","Approved product/branch mapping is required");
  const normalized=normalizeVerifiedExternalOrder({...verified,tenantId:s.tenantId,branchId:s.branchId});
  const saved=await adapter(deps,"persistCanonicalExternalOrder")(tx,{...s,...normalized,providerEventId:eventId});
  if(!saved?.id)fail("ORDER_CHANNEL_INGEST_FAILED","External order was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"order.external_channel.ingested",entityType:"order",entityId:saved.id,
   metadata:{provider:normalized.provider,externalOrderId:normalized.externalOrderId,providerEventId:eventId}});
  return Object.freeze({status:"created",orderId:saved.id});
 });
}

/** Persist ETA and raise a durable exception when an order breaches its SLA. */
export async function updateOrderPreparationEta(input,deps){
 const s=scope(input,"order.preparation_eta.update"),orderId=req(input.orderId,"orderId");
 return txScope(deps,s,async tx=>{
  const order=await adapter(deps,"loadOrderForEtaUpdate")(tx,{...s,orderId});assertScope(order,s,"order");
  if(["served","cancelled","refunded"].includes(order.status))fail("ORDER_ETA_TERMINAL_STATE","Terminal order cannot receive ETA updates");
  const standards=await adapter(deps,"loadApprovedPrepStandards")(tx,{...s,orderId});
  const queue=await adapter(deps,"loadStationQueueTelemetry")(tx,{...s,orderId});
  if(!Array.isArray(standards)||!Array.isArray(queue))fail("ORDER_ETA_SOURCE_REQUIRED","Approved prep standards and live queue telemetry are required");
  const items=standards.map(item=>({...item,stationQueuedMinutes:queue.find(q=>q.stationId===item.stationId)?.queuedMinutes??0}));
  const eta=estimateOrderPreparationEta({items,now:req(input.now,"now"),approvedBufferMinutes:input.approvedBufferMinutes??0,
   sourceRevision:req(input.sourceRevision,"sourceRevision")});
  const saved=await adapter(deps,"persistOrderPreparationEta")(tx,{...s,orderId,...eta});
  if(!saved?.id)fail("ORDER_ETA_PERSIST_FAILED","Preparation ETA was not persisted");
  let escalationId=null;
  if(order.slaDueAt&&Date.parse(eta.estimatedReadyAt)>Date.parse(order.slaDueAt)){
   const escalation=await adapter(deps,"createOrderSlaEscalation")(tx,{...s,orderId,etaId:saved.id,
    slaDueAt:order.slaDueAt,estimatedReadyAt:eta.estimatedReadyAt});
   if(!escalation?.id)fail("ORDER_SLA_ESCALATION_FAILED","SLA breach requires durable escalation");
   escalationId=escalation.id;
  }
  await adapter(deps,"appendAudit")(tx,{...s,action:"order.preparation_eta.updated",entityType:"order",entityId:orderId,
   metadata:{etaId:saved.id,etaMinutes:eta.etaMinutes,escalationId}});
  return Object.freeze({status:"updated",etaId:saved.id,...eta,escalationId});
 });
}
