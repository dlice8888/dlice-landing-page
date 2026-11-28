/** D03-F03: branch-local hours, cutoff, capacity and stock availability quote. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("ORDER_AVAILABILITY_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("ORDER_AVAILABILITY_ADAPTER_REQUIRED",k);return d[k];};
export async function quoteOrderAvailability(input,deps){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId"),
  serviceDate=req(input?.serviceDate,"serviceDate"),requestedTime=req(input?.requestedTime,"requestedTime");
 if(!/^\d{4}-\d{2}-\d{2}$/.test(serviceDate)||!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(requestedTime))fail("ORDER_AVAILABILITY_TIME_INVALID","Use branch-local YYYY-MM-DD and HH:MM");
 if(!Array.isArray(input.items)||!input.items.length)fail("ORDER_AVAILABILITY_ITEMS_REQUIRED","At least one item is required");
 const result=await fn(deps,"quoteOrderAvailabilityAtomically")({tenantId,branchId,serviceDate,requestedTime,items:input.items});
 if(!result||result.tenantId!==tenantId||result.branchId!==branchId||typeof result.accepted!=="boolean"||
  !result.timezone||!Array.isArray(result.items))fail("ORDER_AVAILABILITY_RESULT_INVALID","Server availability quote is incomplete");
 try{new Intl.DateTimeFormat("en",{timeZone:result.timezone});}catch{fail("ORDER_AVAILABILITY_TIMEZONE_INVALID","Branch timezone is invalid");}
 if(result.accepted&&result.items.some(x=>x.availableQuantity<x.requestedQuantity))fail("ORDER_AVAILABILITY_OVERBOOKED","Accepted quote exceeds available capacity");
 return Object.freeze(result);
}
