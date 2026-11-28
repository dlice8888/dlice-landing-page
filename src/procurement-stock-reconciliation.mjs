/** D06-F12: PO receipt, GRN acceptance, stock movement and balance reconciliation. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("PROCUREMENT_RECEIPT_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("PROCUREMENT_RECEIPT_ADAPTER_REQUIRED",k);return d[k];};
export async function receivePurchaseOrderAndReconcile(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  purchaseOrderId:req(input?.purchaseOrderId,"purchaseOrderId"),receiptNumber:req(input?.receiptNumber,"receiptNumber"),
  supplierDeliveryReference:input.supplierDeliveryReference??null,items:input.items,notes:input.notes??null};
 if(!Array.isArray(payload.items)||!payload.items.length||payload.items.some(x=>!x.purchaseOrderItemId||
  !Number.isFinite(x.acceptedQuantity)||x.acceptedQuantity<0||!Number.isFinite(x.rejectedQuantity)||x.rejectedQuantity<0))
  fail("PROCUREMENT_RECEIPT_ITEMS_INVALID","Accepted and rejected quantities required");
 const received=await fn(deps,"receivePurchaseOrderAtomically")(payload);
 if(!received?.grnId||received.tenantId!==payload.tenantId||received.branchId!==payload.branchId||received.status!=="received")
  fail("PROCUREMENT_RECEIPT_FAILED","Goods receipt did not persist");
 const reconciliation=await fn(deps,"reconcilePurchaseReceiptReadOnly")({tenantId:payload.tenantId,branchId:payload.branchId,grnId:received.grnId});
 if(!reconciliation||reconciliation.acceptedQuantity!==reconciliation.stockMovementQuantity||
  reconciliation.rejectedQuantityAddedToStock!==0||reconciliation.balanceAfter!==reconciliation.balanceBefore+reconciliation.stockMovementQuantity)
  fail("PROCUREMENT_STOCK_RECONCILIATION_MISMATCH","PO, GRN, stock ledger and branch balance differ");
 return Object.freeze({received,reconciliation});
}
