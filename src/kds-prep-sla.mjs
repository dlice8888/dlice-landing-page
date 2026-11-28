/** D04-F03: station/product prep SLA and one-time overdue escalation. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("KDS_SLA_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("KDS_SLA_ADAPTER_REQUIRED",k);return d[k];};
export async function evaluateKitchenPrepSla(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  evaluatedAt:input.evaluatedAt??new Date().toISOString(),limit:input.limit??100};
 if(!Number.isSafeInteger(payload.limit)||payload.limit<1||payload.limit>500)fail("KDS_SLA_LIMIT_INVALID","limit must be 1..500");
 const result=await fn(deps,"evaluateKitchenPrepSlaAtomically")(payload);
 if(!result||!Array.isArray(result.tickets)||!Array.isArray(result.escalations)||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId)
  fail("KDS_SLA_RESULT_INVALID","SLA evaluation result is incomplete");
 const seen=new Set();
 for(const e of result.escalations){const key=e.ticketId+":"+e.stage;if(!e.ticketId||!e.stage||seen.has(key)||e.created!==true)fail("KDS_SLA_DUPLICATE_ESCALATION","Each overdue ticket stage may escalate once");seen.add(key);}
 return Object.freeze(result);
}
