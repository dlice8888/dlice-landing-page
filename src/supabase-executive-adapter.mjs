/** Supabase RPC adapter for Executive sales and approval workflows. */
const required=(v,k)=>{if(typeof v!=="string"||!v.trim())throw Object.assign(new Error(k+" is required"),{code:"EXECUTIVE_INPUT_REQUIRED"});return v.trim();};
function rpcClient(client){if(typeof client?.rpc!=="function")throw Object.assign(new Error("Supabase RPC client required"),{code:"EXECUTIVE_RPC_CLIENT_REQUIRED"});return client;}
function resultOrThrow(response,code){if(response?.error){const e=new Error(response.error.message||"Executive RPC failed");e.code=response.error.code||code;throw e;}return response?.data??null;}
export function createSupabaseExecutiveAdapter(client){
 const db=rpcClient(client);
 const invoke=async(name,args,code)=>resultOrThrow(await db.rpc(name,args),code);
 return Object.freeze({
  async loadSalesMonitorSnapshot(i){
   return invoke("executive_sales_monitor_snapshot",{
    p_actor_user_id:required(i.actorId,"actorId"),p_tenant_id:required(i.tenantId,"tenantId"),
    p_branch_ids:Array.isArray(i.branchIds)?i.branchIds:null,p_period_type:required(i.period,"period"),
    p_period_start:required(i.startDate,"startDate"),p_period_end:required(i.endDate,"endDate"),
   },"EXECUTIVE_SALES_RPC_FAILED");
  },
  async listPendingApprovals(i){
   return invoke("list_pending_approvals",{p_actor_user_id:required(i.actorId,"actorId"),p_tenant_id:required(i.tenantId,"tenantId"),
    p_branch_ids:Array.isArray(i.branchIds)?i.branchIds:null,p_categories:Array.isArray(i.categories)?i.categories:null,
   },"EXECUTIVE_APPROVAL_LIST_FAILED");
  },
  async claimApproval(i){
   return invoke("claim_approval",{p_actor_user_id:required(i.actorId,"actorId"),p_tenant_id:required(i.tenantId,"tenantId"),
    p_source_entity:required(i.sourceEntity,"sourceEntity"),p_source_entity_id:required(i.sourceEntityId,"sourceEntityId"),
    p_expected_source_version:i.expectedSourceVersion},"EXECUTIVE_APPROVAL_CLAIM_FAILED");
  },
  async decideApproval(i){
   return invoke("decide_approval",{p_actor_user_id:required(i.actorId,"actorId"),p_tenant_id:required(i.tenantId,"tenantId"),
    p_approval_id:required(i.approvalId,"approvalId"),p_decision:required(i.decision,"decision"),
    p_reason:required(i.reason,"reason"),p_expected_version:i.expectedVersion},"EXECUTIVE_APPROVAL_DECISION_FAILED");
  },
 });
}
