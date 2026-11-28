/** D05-F10: recipe change request, costing, approval and branch rollout. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("RECIPE_CHANGE_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("RECIPE_CHANGE_ADAPTER_REQUIRED",k);return d[k];};
export async function requestRecipeChange(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  recipeId:req(input?.recipeId,"recipeId"),changeSet:input.changeSet,reason:req(input.reason,"reason"),idempotencyKey:req(input.idempotencyKey,"idempotencyKey")};
 if(!payload.changeSet||typeof payload.changeSet!=="object"||Array.isArray(payload.changeSet))fail("RECIPE_CHANGE_SET_INVALID","Recipe change set required");
 const result=await fn(deps,"requestRecipeChangeAtomically")(payload);
 if(!result?.requestId||result.tenantId!==payload.tenantId||result.status!=="draft")fail("RECIPE_CHANGE_REQUEST_FAILED","Recipe change request was not persisted");
 return Object.freeze(result);
}
export async function approveAndRolloutRecipeChange(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),actorId:req(input?.actorId,"actorId"),requestId:req(input?.requestId,"requestId"),
  decision:input.decision,reason:req(input.reason,"reason"),expectedVersion:input.expectedVersion};
 if(!["approve","reject"].includes(payload.decision)||!Number.isSafeInteger(payload.expectedVersion)||payload.expectedVersion<0)fail("RECIPE_CHANGE_DECISION_INVALID","Decision and expected version required");
 const result=await fn(deps,"approveAndRolloutRecipeChangeAtomically")(payload);
 if(!result?.requestId||result.requestId!==payload.requestId||result.status!==(payload.decision==="approve"?"rolling_out":"rejected")||
  !Array.isArray(result.branchAcknowledgements))fail("RECIPE_CHANGE_ROLLOUT_FAILED","Approval and branch rollout state incomplete");
 return Object.freeze(result);
}
