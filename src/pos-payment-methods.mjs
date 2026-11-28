/** D02-F06: server-verified payment intents, split tender and settlement parity. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("POS_PAYMENT_INPUT_REQUIRED",k);return v.trim();};
const amount=(v,k)=>{if(!Number.isSafeInteger(v)||v<=0)fail("POS_PAYMENT_AMOUNT_INVALID",k);return v;};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("POS_PAYMENT_ADAPTER_REQUIRED",k);return d[k];};
const METHODS=new Set(["cash","qris","bank_transfer","card","split"]);
export async function createPosPaymentIntent(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  saleId:req(input?.saleId,"saleId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),paymentMethod:input.paymentMethod,providerId:input.providerId??null};
 if(!METHODS.has(payload.paymentMethod))fail("POS_PAYMENT_METHOD_INVALID","Payment method is unsupported");
 const result=await fn(deps,"createPaymentIntentAtomically")(payload);
 if(!result?.intentId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||
  result.status!=="pending"||!Number.isSafeInteger(result.amountIdr)||result.amountIdr<=0)
  fail("POS_PAYMENT_INTENT_INVALID","Payment intent must be server-priced and pending");
 return Object.freeze(result);
}
export async function recordPosTender(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  saleId:req(input?.saleId,"saleId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),
  paymentMethod:input.paymentMethod,amountIdr:amount(input.amountIdr,"amountIdr"),
  verifiedProviderEventId:input.verifiedProviderEventId??null,reference:input.reference??null};
 if(!METHODS.has(payload.paymentMethod))fail("POS_PAYMENT_METHOD_INVALID","Payment method is unsupported");
 if(payload.paymentMethod!=="cash"&&!payload.verifiedProviderEventId)fail("POS_PAYMENT_PROVIDER_PROOF_REQUIRED","Non-cash tender requires a verified provider event");
 const result=await fn(deps,"recordTenderAtomically")(payload);
 if(!result?.tenderId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||
  !["pending","paid"].includes(result.paymentStatus)||!Number.isSafeInteger(result.allocatedTotalIdr)||
  !Number.isSafeInteger(result.remainingIdr)||result.remainingIdr<0)
  fail("POS_PAYMENT_TENDER_PERSIST_FAILED","Atomic tender allocation result is invalid");
 return Object.freeze(result);
}
export async function ingestPosProviderCallback(input,deps){
 const eventId=req(input?.eventId,"eventId"),providerId=req(input?.providerId,"providerId"),timestamp=Number(input?.timestamp);
 if(!Number.isSafeInteger(timestamp))fail("POS_PAYMENT_TIMESTAMP_INVALID","Provider timestamp is invalid");
 const now=Number(input.nowMs??Date.now()),maxSkew=Number(input.maxSkewMs??300000);
 if(Math.abs(now-timestamp)>maxSkew)fail("POS_PAYMENT_REPLAY_WINDOW_EXCEEDED","Provider callback is outside replay window");
 const rawBody=req(input.rawBody,"rawBody");
 const verified=await fn(deps,"verifyProviderSignature")({providerId,eventId,timestamp,signature:req(input.signature,"signature"),rawBody});
 if(verified!==true&&(!verified||verified.valid!==true||typeof verified.payloadHash!=="string"))
  fail("POS_PAYMENT_SIGNATURE_INVALID","Provider signature verification failed");
 let event;try{event=JSON.parse(rawBody);}catch{fail("POS_PAYMENT_EVENT_INVALID","Signed provider event is not valid JSON");}
 if(event.id!==eventId||!event.saleId||!Number.isSafeInteger(event.amountIdr)||event.amountIdr<=0)
  fail("POS_PAYMENT_EVENT_INVALID","Signed provider event payload is invalid");
 const payload={tenantId:req(input.tenantId,"tenantId"),branchId:req(input.branchId,"branchId"),providerId,eventId,timestamp,
  signatureVerified:true,payloadHash:verified.payloadHash??null,saleId:event.saleId,amountIdr:event.amountIdr};
 const result=await fn(deps,"applyVerifiedProviderEventAtomically")(payload);
 if(!result||!["applied","duplicate"].includes(result.status)||result.eventId!==eventId)
  fail("POS_PAYMENT_EVENT_APPLY_FAILED","Provider event was not durably applied");
 return Object.freeze(result);
}
export async function reconcilePosSettlement(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),actorId:req(input?.actorId,"actorId"),settlementId:req(input?.settlementId,"settlementId")};
 const result=await fn(deps,"reconcileSettlementAtomically")(payload);
 if(!result?.matched||result.varianceIdr!==0||result.tenantId!==payload.tenantId)
  fail("POS_PAYMENT_SETTLEMENT_MISMATCH","Settlement did not reconcile exactly");
 return Object.freeze(result);
}
