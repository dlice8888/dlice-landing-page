/** D06-F11: dual-control inventory adjustment request, approval and posting. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("INVENTORY_ADJUSTMENT_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("INVENTORY_ADJUSTMENT_ADAPTER_REQUIRED",k);return d[k];};
export async function requestInventoryAdjustment(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  inventoryItemId:req(input?.inventoryItemId,"inventoryItemId"),deltaQuantity:input.deltaQuantity,reasonCode:req(input?.reasonCode,"reasonCode"),
  reason:req(input?.reason,"reason"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey")};
 if(!Number.isFinite(payload.deltaQuantity)||payload.deltaQuantity===0)fail("INVENTORY_ADJUSTMENT_DELTA_INVALID","Adjustment delta must be non-zero");
 const r=await fn(deps,"requestInventoryAdjustmentAtomically")(payload);
 if(!r?.requestId||r.tenantId!==payload.tenantId||r.status!=="pending_approval")fail("INVENTORY_ADJUSTMENT_REQUEST_FAILED","Adjustment request not persisted");
 return Object.freeze(r);
}
export async function decideInventoryAdjustment(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),actorId:req(input?.actorId,"actorId"),requestId:req(input?.requestId,"requestId"),
  decision:input.decision,reason:req(input?.reason,"reason"),expectedVersion:input.expectedVersion};
 if(!["approve","reject"].includes(payload.decision)||!Number.isSafeInteger(payload.expectedVersion)||payload.expectedVersion<0)fail("INVENTORY_ADJUSTMENT_DECISION_INVALID","Decision and expected version required");
 const r=await fn(deps,"decideInventoryAdjustmentAtomically")(payload);
 if(!r?.requestId||r.status!==(payload.decision==="approve"?"approved":"rejected")||r.version!==payload.expectedVersion+1)fail("INVENTORY_ADJUSTMENT_DECISION_FAILED","Adjustment decision invalid");
 return Object.freeze(r);
}
export async function postInventoryAdjustment(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  requestId:req(input?.requestId,"requestId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey")};
 const r=await fn(deps,"postInventoryAdjustmentAtomically")(payload);
 if(!r?.movementId||r.tenantId!==payload.tenantId||r.branchId!==payload.branchId||r.status!=="posted"||r.auditEventId===undefined)
  fail("INVENTORY_ADJUSTMENT_POST_FAILED","Adjustment must create one movement and audit event");
 return Object.freeze(r);
}
