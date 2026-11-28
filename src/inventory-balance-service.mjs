/** D06-F01: inventory balance is a read projection over the append-only movement ledger. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("INVENTORY_BALANCE_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("INVENTORY_BALANCE_ADAPTER_REQUIRED",k);return d[k];};
export async function getInventoryBalance(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  inventoryItemId:req(input?.inventoryItemId,"inventoryItemId"),warehouseId:input.warehouseId??null};
 const result=await fn(deps,"getInventoryBalanceLedgerReadOnly")(payload);
 if(!result||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||result.inventoryItemId!==payload.inventoryItemId||
  !Number.isFinite(result.onHand)||!Number.isFinite(result.reserved)||!Number.isFinite(result.inTransit)||!Number.isFinite(result.blocked)||
  !Number.isFinite(result.available)||!Number.isFinite(result.ledgerOnHand))fail("INVENTORY_BALANCE_RESULT_INVALID","Inventory balance projection is incomplete");
 if(result.onHand!==result.ledgerOnHand||result.available!==result.onHand-result.reserved-result.inTransit-result.blocked)
  fail("INVENTORY_BALANCE_LEDGER_MISMATCH","Balance projection differs from movement ledger or stock buckets");
 return Object.freeze(result);
}
