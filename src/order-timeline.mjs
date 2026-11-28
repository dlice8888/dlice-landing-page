/** D03-F06: append-only cross-channel order timeline with source event deduplication. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("ORDER_TIMELINE_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("ORDER_TIMELINE_ADAPTER_REQUIRED",k);return d[k];};
const TYPES=new Set(["payment","operational","fulfillment","reservation"]);
export async function appendOrderTimelineEvent(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),orderId:req(input?.orderId,"orderId"),
  source:req(input?.source,"source"),sourceEventId:req(input?.sourceEventId,"sourceEventId"),actorId:input.actorId??null,
  statusType:input.statusType,oldStatus:input.oldStatus??null,newStatus:req(input?.newStatus,"newStatus"),
  reason:input.reason??null,expectedVersion:input.expectedVersion,idempotencyKey:req(input?.idempotencyKey,"idempotencyKey")};
 if(!TYPES.has(payload.statusType))fail("ORDER_TIMELINE_TYPE_INVALID","Invalid timeline status type");
 if(!Number.isSafeInteger(payload.expectedVersion)||payload.expectedVersion<0)fail("ORDER_TIMELINE_VERSION_REQUIRED","Expected version required");
 const result=await fn(deps,"appendOrderTimelineEventAtomically")(payload);
 if(!result?.eventId||result.tenantId!==payload.tenantId||result.orderId!==payload.orderId||result.sourceEventId!==payload.sourceEventId||
  !Number.isSafeInteger(result.version))fail("ORDER_TIMELINE_APPEND_FAILED","Timeline event was not appended exactly once");
 return Object.freeze(result);
}
export async function listOrderTimeline(input,deps){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId"),orderId=req(input?.orderId,"orderId");
 const rows=await fn(deps,"listOrderTimelineReadOnly")({tenantId,branchId,orderId});
 if(!Array.isArray(rows)||rows.some(x=>x.tenantId!==tenantId||x.orderId!==orderId))fail("ORDER_TIMELINE_SCOPE_INVALID","Timeline contains an out-of-scope event");
 return Object.freeze(rows);
}
