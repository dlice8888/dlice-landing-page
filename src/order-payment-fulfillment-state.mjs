/** D02-F13: independent operational, payment and fulfillment state machines. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("ORDER_STATE_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("ORDER_STATE_ADAPTER_REQUIRED",k);return d[k];};
const maps={
 order:{received:["confirmed","cancelled"],confirmed:["preparing","cancelled"],preparing:["ready_for_pickup","waiting_for_courier","in_delivery","cancelled"],ready_for_pickup:["completed","cancelled"],waiting_for_courier:["in_delivery","delivery_issue","cancelled"],in_delivery:["completed","delivery_issue"],delivery_issue:["in_delivery","cancelled"],completed:[],cancelled:[]},
 payment:{unpaid:["pending_verification","paid","rejected"],pending_verification:["paid","rejected"],paid:["partially_refunded","refunded"],partially_refunded:["refunded"],rejected:[],refunded:[]},
 fulfillment:{unassigned:["queued","cancelled"],queued:["accepted","cancelled"],accepted:["preparing","failed","cancelled"],preparing:["ready","failed","cancelled"],ready:["dispatched","fulfilled","cancelled"],dispatched:["fulfilled","failed"],fulfilled:[],failed:["queued","cancelled"],cancelled:[]},
};
export async function transitionOrderPaymentFulfillment(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  orderId:req(input?.orderId,"orderId"),domain:input.domain,nextStatus:input.nextStatus,
  expectedVersion:input.expectedVersion,idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),
  paymentEvidenceType:input.paymentEvidenceType??null,handoverAcknowledgement:input.handoverAcknowledgement??null,
  reason:input.reason??null};
 if(!maps[payload.domain]||!Object.values(maps[payload.domain]).some(states=>states.includes(payload.nextStatus)))
  fail("ORDER_STATE_INVALID","Unknown state domain or target state");
 if(!Number.isSafeInteger(payload.expectedVersion)||payload.expectedVersion<0)fail("ORDER_STATE_VERSION_REQUIRED","Expected version required");
 if(payload.domain==="payment"&&payload.nextStatus==="paid"&&!["verified_provider_event","cash_tender"].includes(payload.paymentEvidenceType))
  fail("ORDER_PAYMENT_PROOF_REQUIRED","Only verified provider event or server-recorded cash tender may mark paid");
 if(payload.domain==="fulfillment"&&payload.nextStatus==="dispatched"&&!payload.handoverAcknowledgement)
  fail("ORDER_HANDOVER_ACK_REQUIRED","Courier or recipient handover acknowledgement required");
 const result=await fn(deps,"transitionOrderStateAtomically")(payload);
 if(!result?.orderId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||
  result.domain!==payload.domain||result.status!==payload.nextStatus||result.version!==payload.expectedVersion+1||
  !result.transitionEventId)fail("ORDER_STATE_TRANSITION_FAILED","Atomic state transition result is invalid");
 return Object.freeze(result);
}
export const ORDER_STATE_TRANSITIONS=Object.freeze(maps);
