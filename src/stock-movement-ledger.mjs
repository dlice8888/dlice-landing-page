/** D06-F02: idempotent append-only stock movement posting. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("STOCK_MOVEMENT_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("STOCK_MOVEMENT_ADAPTER_REQUIRED",k);return d[k];};
export async function postStockMovement(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  inventoryItemId:req(input?.inventoryItemId,"inventoryItemId"),movementType:req(input?.movementType,"movementType"),
  quantity:input.quantity,sourceType:req(input?.sourceType,"sourceType"),sourceId:req(input?.sourceId,"sourceId"),
  idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),reason:req(input?.reason,"reason")};
 if(!Number.isFinite(payload.quantity)||payload.quantity<=0)fail("STOCK_MOVEMENT_QUANTITY_INVALID","Movement quantity must be positive");
 const result=await fn(deps,"postStockMovementAtomically")(payload);
 if(!result?.movementId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||
  result.inventoryItemId!==payload.inventoryItemId||result.quantity!==payload.quantity||result.appendOnly!==true)
  fail("STOCK_MOVEMENT_POST_FAILED","Stock movement did not append exactly once");
 return Object.freeze(result);
}
