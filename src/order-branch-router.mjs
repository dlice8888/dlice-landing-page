/** D03-F04: server-side branch assignment with atomic area/capacity reservation. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("ORDER_ROUTER_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("ORDER_ROUTER_ADAPTER_REQUIRED",k);return d[k];};
export async function routeOrderToBranch(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),orderId:req(input?.orderId,"orderId"),postalCode:req(input?.postalCode,"postalCode"),
  serviceDate:req(input?.serviceDate,"serviceDate"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),items:input.items};
 if(!Array.isArray(payload.items)||!payload.items.length)fail("ORDER_ROUTER_ITEMS_REQUIRED","Order items required");
 const result=await fn(deps,"reserveOrderBranchAtomically")(payload);
 if(!result?.branchId||!result.reservationId||result.tenantId!==payload.tenantId||result.orderId!==payload.orderId||
  !Number.isSafeInteger(result.reservedCapacity)||!result.reason)fail("ORDER_ROUTER_RESULT_INVALID","Routing decision or capacity reservation missing");
 if(result.overCapacity===true)fail("ORDER_ROUTER_OVERBOOKED","Server attempted to overbook branch capacity");
 return Object.freeze(result);
}
export async function releaseOrderBranchCapacity(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),orderId:req(input?.orderId,"orderId"),reservationId:req(input?.reservationId,"reservationId"),reason:req(input?.reason,"reason")};
 const result=await fn(deps,"releaseOrderBranchCapacityAtomically")(payload);
 if(!result?.released||result.tenantId!==payload.tenantId||result.reservationId!==payload.reservationId)fail("ORDER_ROUTER_RELEASE_FAILED","Capacity release did not commit exactly once");
 return Object.freeze(result);
}
