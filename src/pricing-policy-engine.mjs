/** Central > regional > branch price resolution with effective dates and approval. */
export function resolveEffectivePrice({productId,branchId,regionId,at,pricePolicies}){
 const instant=Date.parse(at);if(!productId||!branchId||!Number.isFinite(instant))throw new Error("PRICING_CONTEXT_INVALID");
 const rank={central:1,regional:2,branch:3};
 const eligible=(pricePolicies||[]).filter(p=>p.product_id===productId&&p.approval_status==="approved"&&Number.isSafeInteger(p.price_idr)&&p.price_idr>=0&&Number.isFinite(Date.parse(p.effective_from))&&Date.parse(p.effective_from)<=instant&&(!p.effective_to||Date.parse(p.effective_to)>instant)&&((p.scope==="central"&&!p.branch_id&&!p.region_id)||(p.scope==="regional"&&p.region_id===regionId)||(p.scope==="branch"&&p.branch_id===branchId)));
 eligible.sort((a,b)=>rank[b.scope]-rank[a.scope]||Date.parse(b.effective_from)-Date.parse(a.effective_from));
 if(!eligible.length)throw new Error("PRICING_POLICY_NOT_FOUND");
 return Object.freeze({product_id:productId,branch_id:branchId,price_idr:eligible[0].price_idr,policy_id:eligible[0].id,scope:eligible[0].scope,effective_from:eligible[0].effective_from});
}
export function validatePriceChange({policy,actor,now}){
 if(!actor?.user_id||!policy?.id||!["central","regional","branch"].includes(policy.scope))throw new Error("PRICING_CHANGE_CONTEXT_INVALID");
 if(policy.approval_status!=="approved"&&policy.operation==="publish")throw new Error("PRICING_APPROVAL_REQUIRED");
 if(Date.parse(policy.effective_from)<=Date.parse(now)&&policy.approval_status!=="approved")throw new Error("PRICING_IMMEDIATE_CHANGE_REQUIRES_APPROVAL");
 return Object.freeze({policy_id:policy.id,actor_user_id:actor.user_id,approval_required:true});
}
