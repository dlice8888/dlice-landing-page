/** D04-F04: KDS lifecycle with station ownership and handover acknowledgement. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("KDS_LIFECYCLE_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("KDS_LIFECYCLE_ADAPTER_REQUIRED",k);return d[k];};
const allowed={queued:["accepted","cancelled","blocked"],accepted:["preparing","cancelled","blocked"],preparing:["ready","cancelled","blocked"],ready:["served","preparing"],blocked:["accepted","cancelled"],served:[],cancelled:[]};
export async function transitionKitchenTicket(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  ticketId:req(input?.ticketId,"ticketId"),nextStatus:input.nextStatus,expectedVersion:input.expectedVersion,
  stationId:req(input?.stationId,"stationId"),handoverReceiver:input.handoverReceiver??null,notes:input.notes??null,
  idempotencyKey:req(input?.idempotencyKey,"idempotencyKey")};
 if(!Object.values(allowed).some(x=>x.includes(payload.nextStatus)))fail("KDS_LIFECYCLE_STATUS_INVALID","Unknown KDS status");
 if(!Number.isSafeInteger(payload.expectedVersion)||payload.expectedVersion<0)fail("KDS_LIFECYCLE_VERSION_REQUIRED","Expected ticket version required");
 if(payload.nextStatus==="served"&&!payload.handoverReceiver)fail("KDS_HANDOVER_ACK_REQUIRED","Handover recipient acknowledgement required");
 const result=await fn(deps,"transitionKitchenTicketAtomically")(payload);
 if(!result?.ticketId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||
  result.status!==payload.nextStatus||result.version!==payload.expectedVersion+1||!result.eventId)
  fail("KDS_LIFECYCLE_TRANSITION_FAILED","KDS transition did not persist exactly once");
 return Object.freeze(result);
}
