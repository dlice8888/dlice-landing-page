/** D02-F06: server-verified payment intents, split tender and settlement parity. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("POS_PAYMENT_INPUT_REQUIRED",k);return v.trim();};
const amount=(v,k)=>{if(!Number.isSafeInteger(v)||v<=0)fail("POS_PAYMENT_AMOUNT_INVALID",k);return v;};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("POS_PAYMENT_ADAPTER_REQUIRED",k);return d[k];};
const METHODS=new Set(["cash","qris","bank_transfer","card","other"]);
export async function createPosPaymentIntent(input,deps){
 const scope={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),saleId:req(input?.saleId,"saleId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),action:"pos.payment.intent.create"};
 const method=input.paymentMethod;if(!METHODS.has(method))fail("POS_PAYMENT_METHOD_INVALID","Payment method is unsupported");
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  await fn(deps,"authorizePayment")(tx,scope);
  const sale=await fn(deps,"lockSaleForPayment")(tx,scope);
  if(!sale||sale.tenantId!==scope.tenantId||sale.branchId!==scope.branchId)fail("POS_PAYMENT_SALE_SCOPE_DENIED","Sale is outside actor scope");
  if(!["pending","partially_paid"].includes(sale.paymentStatus))fail("POS_PAYMENT_SALE_NOT_PAYABLE","Sale is not awaiting payment");
  const remaining=amount(sale.totalIdr-sum(sale.tenders??[]),"remaining");
  const intent=await fn(deps,"createPaymentIntentOnce")(tx,{...scope,paymentMethod:method,amountIdr:remaining,providerId:input.providerId??null});
  if(!intent?.id||intent.amountIdr!==remaining||intent.status!=="pending")fail("POS_PAYMENT_INTENT_INVALID","Payment intent must be server-priced and pending");
  return Object.freeze(intent);
 });
}
function sum(rows){return rows.reduce((n,x)=>n+x.amountIdr,0);}
export async function recordPosTender(input,deps){
 const scope={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),saleId:req(input?.saleId,"saleId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),action:"pos.payment.tender.record"};
 const method=input.paymentMethod;if(!METHODS.has(method))fail("POS_PAYMENT_METHOD_INVALID","Payment method is unsupported");
 const value=amount(input.amountIdr,"amountIdr");
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  await fn(deps,"authorizePayment")(tx,scope);
  const sale=await fn(deps,"lockSaleForPayment")(tx,scope);
  if(!sale||sale.tenantId!==scope.tenantId||sale.branchId!==scope.branchId)fail("POS_PAYMENT_SALE_SCOPE_DENIED","Sale is outside actor scope");
  if(!["pending","partially_paid"].includes(sale.paymentStatus))fail("POS_PAYMENT_SALE_NOT_PAYABLE","Sale is not awaiting payment");
  const allocated=sum(sale.tenders??[]);
  if(allocated+value>sale.totalIdr)fail("POS_PAYMENT_OVERPAYMENT","Tender allocation exceeds sale total");
  if(method!=="cash"&&!input.verifiedProviderEventId)fail("POS_PAYMENT_PROVIDER_PROOF_REQUIRED","Non-cash tender requires a verified provider event");
  const tender=await fn(deps,"insertTenderOnce")(tx,{...scope,paymentMethod:method,amountIdr:value,providerEventId:input.verifiedProviderEventId??null,reference:input.reference??null});
  if(!tender?.id||tender.amountIdr!==value)fail("POS_PAYMENT_TENDER_PERSIST_FAILED","Tender allocation did not persist");
  const next=allocated+value===sale.totalIdr?"paid":"partially_paid";
  if(next==="paid")await fn(deps,"markSalePaidFromVerifiedTenders")(tx,{...scope,expectedTotalIdr:sale.totalIdr,allocatedTotalIdr:next==="paid"?allocated+value:allocated});
  return Object.freeze({tender,paymentStatus:next,allocatedTotalIdr:allocated+value,remainingIdr:sale.totalIdr-allocated-value});
 });
}
export async function ingestPosProviderCallback(input,deps){
 const eventId=req(input?.eventId,"eventId"),providerId=req(input?.providerId,"providerId"),timestamp=Number(input?.timestamp);
 if(!Number.isSafeInteger(timestamp))fail("POS_PAYMENT_TIMESTAMP_INVALID","Provider timestamp is invalid");
 const now=Number(input.nowMs??Date.now()),maxSkew=Number(input.maxSkewMs??300000);
 if(Math.abs(now-timestamp)>maxSkew)fail("POS_PAYMENT_REPLAY_WINDOW_EXCEEDED","Provider callback is outside replay window");
 const verified=await fn(deps,"verifyProviderSignature")({providerId,eventId,timestamp,signature:req(input.signature,"signature"),rawBody:req(input.rawBody,"rawBody")});
 if(verified!==true)fail("POS_PAYMENT_SIGNATURE_INVALID","Provider signature verification failed");
 const event=JSON.parse(input.rawBody);
 if(event.id!==eventId||!event.saleId||!Number.isSafeInteger(event.amountIdr)||event.amountIdr<=0)fail("POS_PAYMENT_EVENT_INVALID","Signed provider event payload is invalid");
 const scope={tenantId:req(input.tenantId,"tenantId"),branchId:req(input.branchId,"branchId"),actorId:"system:payment-provider",action:"pos.payment.provider_callback"};
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  const sale=await fn(deps,"lockSaleForPayment")(tx,{...scope,saleId:event.saleId});
  if(!sale||sale.tenantId!==scope.tenantId||sale.branchId!==scope.branchId)fail("POS_PAYMENT_SALE_SCOPE_DENIED","Provider event sale is outside tenant/branch");
  const prior=await fn(deps,"findProviderEvent")(tx,{providerId,eventId});
  if(prior){if(prior.payloadHash!==verified.payloadHash)fail("POS_PAYMENT_EVENT_COLLISION","Provider event ID reused with different payload");return Object.freeze({status:"duplicate",eventId});}
  if(!["pending","partially_paid"].includes(sale.paymentStatus))fail("POS_PAYMENT_SALE_NOT_PAYABLE","Sale is not awaiting payment");
  const inserted=await fn(deps,"insertVerifiedProviderEvent")(tx,{providerId,eventId,payloadHash:verified.payloadHash,saleId:event.saleId,amountIdr:event.amountIdr});
  if(!inserted?.id)fail("POS_PAYMENT_EVENT_PERSIST_FAILED","Provider event was not persisted");
  const applied=await fn(deps,"applyProviderPaymentOnce")(tx,{sale,eventId,amountIdr:event.amountIdr,providerId});
  if(!applied?.paymentStatus)fail("POS_PAYMENT_EVENT_APPLY_FAILED","Provider payment event was not applied");
  await fn(deps,"appendAudit")(tx,{...scope,action:"pos.payment.provider_event_applied",entityType:"payment_provider_event",entityId:inserted.id,metadata:{saleId:event.saleId,eventId,providerId}});
  return Object.freeze({status:"applied",eventId,...applied});
 });
}
export async function reconcilePosSettlement(input,deps){
 const tenantId=req(input?.tenantId,"tenantId"),actorId=req(input?.actorId,"actorId"),settlementId=req(input?.settlementId,"settlementId");
 return fn(deps,"withTenantTransaction")({tenantId,actorId,action:"pos.payment.settlement.reconcile"},async tx=>{
  await fn(deps,"authorizeSettlement")(tx,{tenantId,actorId,settlementId});
  const result=await fn(deps,"reconcileSettlementAtomically")(tx,{tenantId,actorId,settlementId});
  if(!result?.matched||result.varianceIdr!==0)fail("POS_PAYMENT_SETTLEMENT_MISMATCH","Settlement did not reconcile exactly");
  return Object.freeze(result);
 });
}
