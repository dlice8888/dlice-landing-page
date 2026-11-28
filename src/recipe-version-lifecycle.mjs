/** Immutable recipe version activation and effective-date overlap contract. */
export function validateRecipeVersionActivation({candidate,versions,actor,now}){
 if(!candidate?.id||candidate.status!=="approved"||!Number.isFinite(Date.parse(candidate.effective_from))||!Number.isFinite(Date.parse(now)))throw new Error("RECIPE_VERSION_NOT_APPROVED");
 if(candidate.created_by===actor?.user_id&&candidate.separation_of_duties===true)throw new Error("RECIPE_VERSION_SELF_APPROVAL_FORBIDDEN");
 const overlap=(versions||[]).some(v=>v.id!==candidate.id&&v.status==="active"&&v.product_id===candidate.product_id&&Date.parse(candidate.effective_from)<Date.parse(v.effective_to||"9999-12-31T00:00:00Z")&&Date.parse(v.effective_to||"9999-12-31T00:00:00Z")>Date.parse(v.effective_from));
 if(overlap)throw new Error("RECIPE_VERSION_EFFECTIVE_DATE_OVERLAP");
 return Object.freeze({recipe_version_id:candidate.id,activated_by:actor.user_id,effective_from:candidate.effective_from,history_immutable:true,rollback_requires_new_version:true});
}
