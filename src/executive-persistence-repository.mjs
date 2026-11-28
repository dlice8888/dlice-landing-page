/**
 * Server-only persistence adapter for Executive Command Center T01/T02.
 * The caller must authenticate the user and resolve tenant/branch scope before
 * invoking this repository. Never expose the service-role client to browsers.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("EXEC_PERSIST_INPUT_REQUIRED",k);return v.trim();};
const unwrap=(result,op)=>{
 if(result?.error){const e=new Error(`Executive ${op} failed`);e.code=result.error.code??"EXEC_PERSIST_FAILED";e.details=result.error.message;throw e;}
 return result?.data;
};
export function createExecutivePersistenceRepository({serviceClient,tenantId,actorId}){
 if(!serviceClient||typeof serviceClient.rpc!=="function")fail("EXEC_PERSIST_SERVICE_CLIENT_REQUIRED","Server-side Supabase client required");
 const scope={p_tenant_id:req(tenantId,"tenantId"),p_actor_user_id:req(actorId,"actorId")};
 const rpc=async(name,args,op)=>unwrap(await serviceClient.rpc(name,{...scope,...args}),op);
 return Object.freeze({
  async persistSnapshot(snapshot){
   if(!snapshot||!Array.isArray(snapshot.branches)||!Array.isArray(snapshot.sourceGaps))fail("EXEC_PERSIST_SNAPSHOT_INVALID","Snapshot branch facts and gaps are required");
   const result=await rpc("executive_persist_command_center_snapshot",{
    p_period_start:req(snapshot.periodStart,"periodStart"),p_period_end:req(snapshot.periodEnd,"periodEnd"),
    p_as_of:req(snapshot.asOf,"asOf"),p_formula_version:snapshot.formulaVersion,
    p_expected_branch_count:snapshot.expectedBranchCount,p_active_branch_count:snapshot.activeBranchCount,
    p_reconciled_branch_count:snapshot.reconciledBranchCount,p_status:snapshot.status,
    p_totals:snapshot.totals,p_branch_facts:snapshot.branches,p_source_gaps:snapshot.sourceGaps,
    p_idempotency_key:req(snapshot.idempotencyKey,"idempotencyKey")
   },"persistSnapshot");
   if(!result?.id)fail("EXEC_PERSIST_SNAPSHOT_MISSING_ID","Snapshot RPC did not return a persisted id");
   return result;
  },
  async claimApproval({approvalId,expectedVersion,idempotencyKey,claimTtlSeconds=300}){
   if(!Number.isSafeInteger(expectedVersion)||expectedVersion<0)fail("EXEC_PERSIST_VERSION_INVALID","expectedVersion must be a non-negative integer");
   return rpc("executive_claim_approval",{
    p_approval_id:req(approvalId,"approvalId"),p_expected_version:expectedVersion,
    p_idempotency_key:req(idempotencyKey,"idempotencyKey"),p_claim_ttl_seconds:claimTtlSeconds
   },"claimApproval");
  }
 });
}
