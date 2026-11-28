/** D04-F07: production batch completion and ledger-to-consumption reconciliation. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("PRODUCTION_CONSUMPTION_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("PRODUCTION_CONSUMPTION_ADAPTER_REQUIRED",k);return d[k];};
export async function completeProductionBatchAndReconcile(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  batchId:req(input?.batchId,"batchId"),actualGoodQuantity:input.actualGoodQuantity,wasteQuantity:input.wasteQuantity,
  actualConsumptions:input.actualConsumptions};
 if(!Number.isFinite(payload.actualGoodQuantity)||payload.actualGoodQuantity<0||!Number.isFinite(payload.wasteQuantity)||payload.wasteQuantity<0||
  !Array.isArray(payload.actualConsumptions))fail("PRODUCTION_CONSUMPTION_INPUT_INVALID","Production yield and actual consumption invalid");
 const completed=await fn(deps,"completeProductionBatchAtomically")(payload);
 if(!completed?.ok||completed.status!=="completed"||completed.batchId!==payload.batchId)fail("PRODUCTION_BATCH_COMPLETION_FAILED","Batch completion did not persist");
 const reconciliation=await fn(deps,"reconcileProductionBatchReadOnly")({tenantId:payload.tenantId,branchId:payload.branchId,batchId:payload.batchId});
 if(!reconciliation||reconciliation.tenantId!==payload.tenantId||reconciliation.branchId!==payload.branchId||
  !Array.isArray(reconciliation.ingredients)||reconciliation.ingredients.some(x=>x.actualQuantity!==x.stockMovementQuantity))
  fail("PRODUCTION_STOCK_RECONCILIATION_MISMATCH","Actual consumption differs from stock movement ledger");
 return Object.freeze({completed,reconciliation});
}
