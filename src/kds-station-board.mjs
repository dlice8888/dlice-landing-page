/** D04-F01: station-scoped KDS board and idempotent ticket dispatch. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("KDS_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("KDS_ADAPTER_REQUIRED",k);return d[k];};
export async function listKitchenStationBoard(input,deps){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId"),actorId=req(input?.actorId,"actorId");
 const result=await fn(deps,"listKitchenStationBoardReadOnly")({tenantId,branchId,actorId,stationId:input.stationId??null});
 if(!result||result.tenantId!==tenantId||result.branchId!==branchId||!Array.isArray(result.stations))fail("KDS_BOARD_SCOPE_INVALID","KDS board result is outside branch scope");
 const ids=new Set();
 for(const station of result.stations)for(const ticket of station.tickets??[]){if(ticket.branchId!==branchId||ids.has(ticket.ticketId))fail("KDS_BOARD_DUPLICATE_OR_SCOPE_INVALID","Ticket appears more than once or outside branch");ids.add(ticket.ticketId);}
 return Object.freeze(result);
}
export async function dispatchKitchenTicket(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  sourceType:input.sourceType,sourceId:req(input?.sourceId,"sourceId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey")};
 if(!["pos_sale","online_order"].includes(payload.sourceType))fail("KDS_SOURCE_TYPE_INVALID","Ticket source must be POS sale or online order");
 const result=await fn(deps,"dispatchKitchenTicketAtomically")(payload);
 if(!result?.ticketId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||!Array.isArray(result.items)||!result.stationId)
  fail("KDS_DISPATCH_FAILED","Ticket dispatch did not return station and source items");
 return Object.freeze(result);
}
