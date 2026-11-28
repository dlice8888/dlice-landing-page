/** D04-F09: separate made-to-order and batch production paths. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("PRODUCTION_MODE_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("PRODUCTION_MODE_ADAPTER_REQUIRED",k);return d[k];};
export async function routeProductionMode(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  productId:req(input?.productId,"productId"),quantity:input.quantity,orderId:input.orderId??null,idempotencyKey:req(input?.idempotencyKey,"idempotencyKey")};
 if(!Number.isFinite(payload.quantity)||payload.quantity<=0)fail("PRODUCTION_MODE_QUANTITY_INVALID","Production quantity must be positive");
 const result=await fn(deps,"routeProductionModeAtomically")(payload);
 if(!result||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||
  !["made_to_order","batch"].includes(result.mode)||
  (result.mode==="made_to_order"&&!result.productionJobId)||(result.mode==="batch"&&(!result.batchId||!result.reservationId)))
  fail("PRODUCTION_MODE_ROUTE_INVALID","Production mode did not create its corresponding work item");
 return Object.freeze(result);
}
