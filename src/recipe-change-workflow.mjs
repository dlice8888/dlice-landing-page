/** Recipe change request -> costing -> independent approval -> branch rollout. */
export function prepareRecipeChange({request,author,costSnapshot,approver,rolloutBranches,now}){
 if(!request?.id||!request.product_id||!author?.user_id||!costSnapshot?.version||!Number.isFinite(costSnapshot.total_cost_idr)||costSnapshot.total_cost_idr<0)throw new Error("RECIPE_CHANGE_CONTEXT_INVALID");
 if(approver?.user_id===author.user_id)throw new Error("RECIPE_CHANGE_SELF_APPROVAL_FORBIDDEN");
 if(!Array.isArray(rolloutBranches)||!rolloutBranches.length)throw new Error("RECIPE_CHANGE_ROLLOUT_BRANCHES_REQUIRED");
 if(Date.parse(costSnapshot.calculated_at)>Date.parse(now))throw new Error("RECIPE_CHANGE_COST_TIMESTAMP_INVALID");
 return Object.freeze({change_request_id:request.id,product_id:request.product_id,author_user_id:author.user_id,cost_snapshot_version:costSnapshot.version,cost_snapshot_idr:costSnapshot.total_cost_idr,approval_required:true,approved:approver?.decision==="approved",rollout_branch_ids:Object.freeze([...new Set(rolloutBranches)]),activation_allowed:approver?.decision==="approved"&&rolloutBranches.every(b=>b.acknowledged===true)});
}
export function assertRecipeRolloutComplete({branchAcks,requiredBranchIds}){
 const acked=new Set((branchAcks||[]).filter(x=>x.status==="applied").map(x=>x.branch_id));
 const missing=(requiredBranchIds||[]).filter(id=>!acked.has(id));
 if(missing.length)throw new Error("RECIPE_ROLLOUT_INCOMPLETE");
 return Object.freeze({complete:true,acknowledged_branch_ids:[...acked]});
}
