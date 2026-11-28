/** D06-F07: replenishment recommendation from available stock, lead time and demand. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("REORDER_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("REORDER_ADAPTER_REQUIRED",k);return d[k];};
export async function generateInventoryReorderRecommendations(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),asOfDate:req(input?.asOfDate,"asOfDate")};
 const result=await fn(deps,"generateInventoryReorderRecommendationsAtomically")(payload);
 if(!result||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||!Array.isArray(result.recommendations))
  fail("REORDER_RESULT_INVALID","Reorder recommendations are incomplete");
 for(const r of result.recommendations){if(!r.inventoryItemId||!Number.isFinite(r.availableQuantity)||!Number.isFinite(r.reorderQuantity)||r.reorderQuantity<0||!Number.isFinite(r.leadTimeDays)||r.leadTimeDays<0||!r.reason)fail("REORDER_RECOMMENDATION_INVALID","Recommendation missing stock, lead time or rationale");}
 return Object.freeze(result);
}
