/** D04-F05: theoretical recipe yield, portion conversion and waste tolerance. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("RECIPE_COST_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("RECIPE_COST_ADAPTER_REQUIRED",k);return d[k];};
export async function calculateRecipeYieldCost(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  recipeId:req(input?.recipeId,"recipeId"),recipeVersion:input.recipeVersion,desiredGoodQuantity:input.desiredGoodQuantity,
  wasteTolerancePercent:input.wasteTolerancePercent??0};
 if(!Number.isSafeInteger(payload.recipeVersion)||payload.recipeVersion<1||!Number.isFinite(payload.desiredGoodQuantity)||payload.desiredGoodQuantity<=0||
  !Number.isFinite(payload.wasteTolerancePercent)||payload.wasteTolerancePercent<0||payload.wasteTolerancePercent>100)
  fail("RECIPE_COST_INPUT_INVALID","Recipe version, quantity or waste tolerance invalid");
 const result=await fn(deps,"calculateRecipeYieldCostAtomically")(payload);
 if(!result?.recipeId||result.recipeId!==payload.recipeId||result.recipeVersion!==payload.recipeVersion||
  !Array.isArray(result.ingredients)||!Number.isFinite(result.expectedOutputQuantity)||result.expectedOutputQuantity<=0||
  !Number.isSafeInteger(result.totalCostIdr)||result.totalCostIdr<0)
  fail("RECIPE_COST_RESULT_INVALID","Server costing snapshot is incomplete");
 return Object.freeze(result);
}
