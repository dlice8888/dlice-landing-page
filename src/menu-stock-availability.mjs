/** D05-F09: stock-aware menu availability and atomic reservation quote. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("MENU_AVAILABILITY_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("MENU_AVAILABILITY_ADAPTER_REQUIRED",k);return d[k];};
export async function quoteMenuStockAvailability(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  serviceDate:req(input?.serviceDate,"serviceDate"),items:input.items,idempotencyKey:input.idempotencyKey??null};
 if(!Array.isArray(payload.items)||!payload.items.length||payload.items.some(x=>!x.productId||!Number.isSafeInteger(x.quantity)||x.quantity<1))
  fail("MENU_AVAILABILITY_ITEMS_INVALID","Product and positive quantity required");
 const result=await fn(deps,"quoteMenuStockAvailabilityAtomically")(payload);
 if(!result||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||!Array.isArray(result.items)||
  typeof result.available!=="boolean")fail("MENU_AVAILABILITY_RESULT_INVALID","Server stock availability result invalid");
 if(result.available&&result.items.some(x=>x.availableQuantity<x.requestedQuantity))fail("MENU_AVAILABILITY_OVERSELL","Available result exceeds allocatable stock");
 return Object.freeze(result);
}
