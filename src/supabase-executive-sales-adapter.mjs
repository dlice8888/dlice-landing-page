/** Supabase transport adapter for the executive sales snapshot RPC. */
const required=(v,k)=>{if(typeof v!=="string"||!v.trim())throw Object.assign(new Error(k+" is required"),{code:"EXEC_SALES_INPUT_REQUIRED"});return v.trim();};
export function createSupabaseExecutiveSalesAdapter(client){
 if(typeof client?.rpc!=="function")throw Object.assign(new Error("Supabase RPC client required"),{code:"EXEC_SALES_RPC_CLIENT_REQUIRED"});
 return Object.freeze({loadSalesMonitorSnapshot:async q=>{
  const {data,error}=await client.rpc("executive_sales_monitor_snapshot",{
   p_actor_user_id:required(q.actorId,"actorId"),p_tenant_id:required(q.tenantId,"tenantId"),
   p_branch_ids:q.branchIds??null,p_period_type:q.period,p_period_start:q.startDate,p_period_end:q.endDate
  });
  if(error){const e=new Error(error.message||"Executive sales snapshot RPC failed");e.code=error.code||"EXEC_SALES_RPC_FAILED";throw e;}
  return data;
 }});
}
