/** D03-F01: unified POS and online order queue from canonical source records. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("ORDER_QUEUE_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("ORDER_QUEUE_ADAPTER_REQUIRED",k);return d[k];};
export async function listUnifiedOrderQueue(input,deps){
 const tenantId=req(input?.tenantId,"tenantId"),actorId=req(input?.actorId,"actorId");
 const limit=input.limit??50;if(!Number.isSafeInteger(limit)||limit<1||limit>200)fail("ORDER_QUEUE_LIMIT_INVALID","limit must be 1..200");
 const result=await fn(deps,"listUnifiedOrderQueueAtomically")({tenantId,actorId,branchIds:input.branchIds??null,
  channels:input.channels??["pos","online"],cursor:input.cursor??null,limit,statuses:input.statuses??null});
 if(!result||!Array.isArray(result.rows)||!result.scope||result.scope.tenantId!==tenantId)fail("ORDER_QUEUE_RESULT_INVALID","Queue result is incomplete or tenant mismatched");
 const seen=new Set();
 for(const row of result.rows){
  if(row.tenantId!==tenantId||!row.branchId||!row.sourceId||!["pos","online"].includes(row.channel))fail("ORDER_QUEUE_SOURCE_SCOPE_INVALID","Queue source is outside tenant or channel scope");
  const key=row.channel+":"+row.sourceId;if(seen.has(key))fail("ORDER_QUEUE_DUPLICATE_SOURCE","Canonical source appeared more than once");seen.add(key);
 }
 return Object.freeze(result);
}
