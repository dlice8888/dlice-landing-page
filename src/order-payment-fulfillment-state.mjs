/** D02-F13: independent order, payment and fulfillment state machines. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("ORDER_STATE_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("ORDER_STATE_ADAPTER_REQUIRED",k);return d[k];};
const maps={
 order:{draft:["confirmed","cancelled"],confirmed:["cancelled","completed"],completed:[],cancelled:[]},
 payment:{pending:["partially_paid","paid","failed","voided"],partially_paid:["paid","failed","voided"],paid:["partially_refunded","refunded"],partially_refunded:["refunded"],failed:[],voided:[],refunded:[]},
 fulfillment:{queued:["accepted","cancelled"],accepted:["preparing","cancelled","failed"],preparing:["ready","failed","cancelled"],ready:["handed_over","cancelled","failed"],handed_over:["completed"],completed:[],failed:["queued","cancelled"],cancelled:[]},
};
export async function transitionOrderPaymentFulfillment(input,deps){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId"),actorId=req(input?.actorId,"actorId"),
  orderId=req(input?.orderId,"orderId"),domain=input.domain,next=input.nextStatus,expectedVersion=input.expectedVersion,
  idempotencyKey=req(input?.idempotencyKey,"idempotencyKey");
 if(!maps[domain]||!Object.hasOwn(maps[domain],next))fail("ORDER_STATE_INVALID","Unknown state domain or target state");
 if(!Number.isSafeInteger(expectedVersion)||expectedVersion<0)fail("ORDER_STATE_VERSION_REQUIRED","Expected version required");
 const scope={tenantId,branchId,actorId,orderId,domain,action:"order."+domain+".transition"};
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  await fn(deps,"authorizeTransition")(tx,scope);
  const current=await fn(deps,"lockOrderState")(tx,{tenantId,branchId,orderId});
  if(!current||current.tenantId!==tenantId||current.branchId!==branchId)fail("ORDER_STATE_SCOPE_DENIED","Order outside tenant/branch");
  if(current.version!==expectedVersion)fail("ORDER_STATE_STALE_VERSION","Order state changed; reload timeline");
  const prior=current[domain+"Status"];
  if(!maps[domain][prior]?.includes(next))fail("ORDER_STATE_TRANSITION_INVALID","Illegal state transition");
  if(domain==="payment"&&next==="paid"&&!["verified_provider_event","cash_tender"].includes(input.paymentEvidenceType))
   fail("ORDER_PAYMENT_PROOF_REQUIRED","Only verified provider event or server-recorded cash tender may mark paid");
  if(domain==="order"&&next==="cancelled"&&current.paymentStatus==="paid")
   fail("ORDER_CANCELLATION_COMPENSATION_REQUIRED","Paid order cancellation must execute refund/stock/Finance compensation");
  if(domain==="fulfillment"&&next==="handed_over"&&!input.handoverAcknowledgement)
   fail("ORDER_HANDOVER_ACK_REQUIRED","Handover receiver acknowledgement required");
  const result=await fn(deps,"applyStateTransitionAtomically")(tx,{...scope,nextStatus:next,expectedVersion,idempotencyKey,
   actorAttribution:actorId,paymentEvidenceType:input.paymentEvidenceType??null,handoverAcknowledgement:input.handoverAcknowledgement??null});
  if(!result?.orderId||result.version!==expectedVersion+1||result[domain+"Status"]!==next)fail("ORDER_STATE_TRANSITION_FAILED","State transition did not commit exactly once");
  await fn(deps,"appendAudit")(tx,{...scope,action:"order."+domain+"."+next,entityType:"order",entityId:orderId,metadata:{prior,next,version:result.version,idempotencyKey}});
  return Object.freeze(result);
 });
}
export const ORDER_STATE_TRANSITIONS=Object.freeze(maps);
