/** D04-F06: demand-driven prep plan and ingredient reservation. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("PREP_PLAN_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("PREP_PLAN_ADAPTER_REQUIRED",k);return d[k];};
export async function createProductionPrepPlan(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  serviceDate:req(input?.serviceDate,"serviceDate"),shiftId:req(input?.shiftId,"shiftId"),demandReference:req(input?.demandReference,"demandReference"),
  items:input.items,idempotencyKey:req(input?.idempotencyKey,"idempotencyKey")};
 if(!Array.isArray(payload.items)||!payload.items.length||payload.items.some(x=>!x.productId||!Number.isFinite(x.quantity)||x.quantity<=0))
  fail("PREP_PLAN_ITEMS_INVALID","Prep plan items require product and positive quantity");
 const result=await fn(deps,"createProductionPrepPlanAtomically")(payload);
 if(!result?.planId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||
  !Array.isArray(result.ingredientReservations)||result.status!=="planned")
  fail("PREP_PLAN_RESULT_INVALID","Prep plan or ingredient reservations are incomplete");
 return Object.freeze(result);
}
