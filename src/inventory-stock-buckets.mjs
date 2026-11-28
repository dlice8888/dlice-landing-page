/** D06-F06: available/reserved/in-transit/blocked stock bucket lifecycle. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("STOCK_BUCKET_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("STOCK_BUCKET_ADAPTER_REQUIRED",k);return d[k];};
export async function getInventoryStockBuckets(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),inventoryItemId:req(input?.inventoryItemId,"inventoryItemId")};
 const r=await fn(deps,"getInventoryStockBucketsReadOnly")(payload);
 if(!r||r.tenantId!==payload.tenantId||r.branchId!==payload.branchId||r.onHand!==r.available+r.reserved+r.inTransit+r.blocked)
  fail("STOCK_BUCKET_LEDGER_MISMATCH","On-hand must equal all stock buckets");
 return Object.freeze(r);
}
export async function reserveInventoryStock(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  inventoryItemId:req(input?.inventoryItemId,"inventoryItemId"),quantity:input.quantity,sourceId:req(input?.sourceId,"sourceId"),
  idempotencyKey:req(input?.idempotencyKey,"idempotencyKey")};
 if(!Number.isFinite(payload.quantity)||payload.quantity<=0)fail("STOCK_BUCKET_QUANTITY_INVALID","Reservation quantity must be positive");
 const r=await fn(deps,"reserveInventoryStockAtomically")(payload);
 if(!r?.reservationId||r.tenantId!==payload.tenantId||r.branchId!==payload.branchId||r.quantity!==payload.quantity)fail("STOCK_BUCKET_RESERVATION_FAILED","Stock reservation did not persist");
 return Object.freeze(r);
}
