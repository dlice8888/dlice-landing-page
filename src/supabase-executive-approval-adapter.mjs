/** Supabase transport adapter for the atomic Executive approval RPCs. */
const required=(v,k)=>{if(typeof v!=="string"||!v.trim())throw Object.assign(new Error(k+" is required"),{code:"APPROVAL_INPUT_REQUIRED"});return v.trim();};
const unwrap=(r)=>{if(r?.error){const e=new Error(r.error.message||"Approval RPC failed");e.code=r.error.code||"APPROVAL_RPC_FAILED";throw e;}return r?.data??null;};
export function createSupabaseExecutiveApprovalAdapter(client){
 if(typeof client?.rpc!=="function")throw Object.assign(new Error("Supabase RPC client required"),{code:"APPROVAL_RPC_CLIENT_REQUIRED"});
 const call=async(name,args)=>unwrap(await client.rpc(name,args));
 return Object.freeze({
  listPendingApprovals:async q=>call("list_pending_approvals",{p_actor_user_id:required(q.actorId,"actorId"),p_tenant_id:required(q.tenantId,"tenantId"),p_branch_ids:q.branchIds??[],p_categories:q.categories??null}),
  claimApproval:async q=>call("claim_approval",{p_actor_user_id:required(q.actorId,"actorId"),p_tenant_id:required(q.tenantId,"tenantId"),p_branch_ids:q.branchIds??[],p_approval_id:required(q.approvalId,"approvalId"),p_expected_version:q.expectedVersion}),
  decideApproval:async q=>call("decide_approval",{p_actor_user_id:required(q.actorId,"actorId"),p_tenant_id:required(q.tenantId,"tenantId"),p_branch_ids:q.branchIds??[],p_approval_id:required(q.approvalId,"approvalId"),p_decision:q.decision,p_reason:required(q.reason,"reason"),p_expected_version:q.expectedVersion}),
  listApprovalHistory:async q=>call("list_approval_decision_history",{p_actor_user_id:required(q.actorId,"actorId"),p_tenant_id:required(q.tenantId,"tenantId"),p_branch_ids:q.branchIds??[],p_approval_id:required(q.approvalId,"approvalId")}),
 });
}
