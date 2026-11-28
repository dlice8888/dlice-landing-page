/** D03-F09: customer-scoped order history and compensated cancellation. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("ORDER_HISTORY_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("ORDER_HISTORY_ADAPTER_REQUIRED",k);return d[k];};
export async function getCustomerOrderHistory(input,deps){
 const trackingToken=req(input?.trackingToken,"trackingToken");
 const result=await fn(deps,"loadCustomerOrderHistoryByToken")({trackingToken});
 if(!result||!Array.isArray(result.orders)||result.orders.some(x=>x.customerScopeVerified!==true))fail("ORDER_HISTORY_CUSTOMER_SCOPE_DENIED","Customer history token did not resolve to owned orders");
 return Object.freeze(result);
}
export async function requestOrderCancellation(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),orderId:req(input?.orderId,"orderId"),reason:req(input?.reason,"reason"),
  idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),actorId:input.actorId??null,trackingToken:input.trackingToken??null};
 if(!payload.actorId&&!payload.trackingToken)fail("ORDER_CANCEL_IDENTITY_REQUIRED","Authenticated staff or customer tracking token required");
 const result=await fn(deps,"cancelOrderWithCompensationsAtomically")(payload);
 if(!result?.orderId||result.tenantId!==payload.tenantId||!["cancelled","cancellation_pending"].includes(result.operationalStatus)||
  !result.compensation||!["not_required","refund_requested","refunded"].includes(result.compensation.refundStatus))
  fail("ORDER_CANCEL_COMPENSATION_INCOMPLETE","Cancellation did not return source and compensation states");
 return Object.freeze(result);
}
