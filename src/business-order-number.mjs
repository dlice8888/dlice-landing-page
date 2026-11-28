/** D03-F05: business order number is generated and bound server-side. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("BUSINESS_ORDER_NUMBER_INPUT_REQUIRED",k);return v.trim();};
export async function generateBusinessOrderNumber(input,deps){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId"),orderId=req(input?.orderId,"orderId"),idempotencyKey=req(input?.idempotencyKey,"idempotencyKey");
 if(typeof deps?.generateBusinessOrderNumberAtomically!=="function")fail("BUSINESS_ORDER_NUMBER_ADAPTER_REQUIRED","generateBusinessOrderNumberAtomically");
 const result=await deps.generateBusinessOrderNumberAtomically({tenantId,branchId,orderId,idempotencyKey});
 if(!result?.orderId||result.orderId!==orderId||result.tenantId!==tenantId||result.branchId!==branchId||
  !/^DLC-\d{2}\/\d{2}\/\d{4}-\d{5}$/.test(result.businessOrderNumber))fail("BUSINESS_ORDER_NUMBER_INVALID","Server returned an invalid or unbound business order number");
 return Object.freeze(result);
}
