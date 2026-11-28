/** D06-F09: blind cycle count, variance approval and atomic posting. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("CYCLE_COUNT_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("CYCLE_COUNT_ADAPTER_REQUIRED",k);return d[k];};
export async function createInventoryCycleCount(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  items:input.items,idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),notes:input.notes??null};
 if(!Array.isArray(payload.items)||!payload.items.length)fail("CYCLE_COUNT_ITEMS_REQUIRED","Count items required");
 const r=await fn(deps,"createInventoryCycleCountAtomically")(payload);
 if(!r?.countId||r.tenantId!==payload.tenantId||r.branchId!==payload.branchId||r.status!=="draft")fail("CYCLE_COUNT_CREATE_FAILED","Cycle count not created");
 return Object.freeze(r);
}
export async function postInventoryCycleCount(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  countId:req(input?.countId,"countId"),approvalId:input.approvalId??null,idempotencyKey:req(input?.idempotencyKey,"idempotencyKey")};
 const r=await fn(deps,"postInventoryCycleCountAtomically")(payload);
 if(!r?.countId||r.countId!==payload.countId||r.status!=="posted"||!Array.isArray(r.adjustmentMovements)||r.adjustmentMovements.some(x=>!x.movementId))
  fail("CYCLE_COUNT_POST_FAILED","Count adjustments and movement references are incomplete");
 return Object.freeze(r);
}
