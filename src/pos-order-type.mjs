/** D02-F03: order-type parity with required fulfillment metadata. */
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
 const scope={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),action:"pos.order.create"};
 const fulfillment=normalizePosOrderType(input);
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  await fn(deps,"authorizeOrderType")(tx,scope);
  const policy=await fn(deps,"loadBranchOrderTypePolicy")(tx,scope);
  if(!policy?.enabledTypes?.includes(fulfillment.orderType))fail("POS_ORDER_TYPE_DISABLED","Order type is disabled for this branch");
  if(fulfillment.orderType==="delivery"&&!policy.deliveryAreaIds?.includes(fulfillment.deliveryAreaId))fail("POS_ORDER_DELIVERY_AREA_DENIED","Delivery area is not served by this branch");
  const result=await fn(deps,"createOrderAndFulfillmentAtomically")(tx,{...scope,fulfillment,items:input.items});
  if(!result?.orderId||!result?.fulfillmentId||result.paymentStatus!=="pending"||!result.fulfillmentStatus)
   fail("POS_ORDER_TYPE_CREATE_FAILED","Order, payment and fulfillment records were not created independently");
  return Object.freeze(result);
 });
}
