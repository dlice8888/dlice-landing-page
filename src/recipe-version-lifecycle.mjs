/** D05-F06: immutable recipe versions and effective-date activation. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("RECIPE_VERSION_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("RECIPE_VERSION_ADAPTER_REQUIRED",k);return d[k];};
export async function activateRecipeVersion(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  recipeId:req(input?.recipeId,"recipeId"),version:input.version,effectiveFrom:req(input?.effectiveFrom,"effectiveFrom"),
  expectedActiveVersion:input.expectedActiveVersion,approvalId:input.approvalId??null};
 if(!Number.isSafeInteger(payload.version)||payload.version<1||!Number.isSafeInteger(payload.expectedActiveVersion)||payload.expectedActiveVersion<0)
  fail("RECIPE_VERSION_PAYLOAD_INVALID","Recipe version and expected active version required");
 const result=await fn(deps,"activateRecipeVersionAtomically")(payload);
 if(!result?.recipeId||result.recipeId!==payload.recipeId||result.activeVersion!==payload.version||
  result.effectiveFrom!==payload.effectiveFrom||result.historicalVersionsImmutable!==true)
  fail("RECIPE_VERSION_ACTIVATION_FAILED","Recipe activation or historical immutability not confirmed");
 return Object.freeze(result);
}
