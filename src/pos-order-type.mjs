/** D02-F03: dine-in, takeaway, pickup and delivery parity via one atomic server operation. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("POS_ORDER_TYPE_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("POS_ORDER_TYPE_ADAPTER_REQUIRED",k);return d[k];};
const TYPES=new Set(["dine_in","takeaway","pickup","delivery"]);
export function normalizePosOrderType(input){
 const type=input?.orderType;if(!TYPES.has(type))fail("POS_ORDER_TYPE_INVALID","Unsupported order type");
 const detail={};
 if(type==="dine_in")detail.tableId=req(input.tableId,"tableId");
 if(type==="pickup")detail.pickupAt=req(input.pickupAt,"pickupAt");
 if(type==="delivery"){detail.deliveryAddress=req(input.deliveryAddress,"deliveryAddress");detail.deliveryAreaId=req(input.deliveryAreaId,"deliveryAreaId");}
 return Object.freeze({orderType:type,...detail});
}
export async function createPosOrderWithFulfillment(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),fulfillment:normalizePosOrderType(input),items:input.items??[]};
 const result=await fn(deps,"createPosOrderAtomically")(payload);
 if(!result?.orderId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||
  result.orderType!==payload.fulfillment.orderType||result.paymentStatus!=="pending"||!result.fulfillmentStatus||
  !result.fulfillmentId)fail("POS_ORDER_TYPE_CREATE_FAILED","Atomic order creation must persist independent payment and fulfillment states");
 return Object.freeze(result);
}
