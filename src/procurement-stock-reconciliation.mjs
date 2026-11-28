/** PO -> accepted GRN -> posted stock movement -> inventory balance parity. */
export function reconcileProcurementReceipt({purchaseOrder,receipts,movements,inventoryBalance}){
 if(!purchaseOrder?.id||!Number.isFinite(purchaseOrder.ordered_quantity)||purchaseOrder.ordered_quantity<0)throw new Error("PROCUREMENT_RECONCILIATION_CONTEXT_INVALID");
 const accepted=(receipts||[]).filter(r=>r.purchase_order_id===purchaseOrder.id&&r.status==="accepted").reduce((s,r)=>s+Number(r.accepted_quantity||0),0);
 const rejected=(receipts||[]).filter(r=>r.purchase_order_id===purchaseOrder.id).reduce((s,r)=>s+Number(r.rejected_quantity||0),0);
 if(!Number.isFinite(accepted)||!Number.isFinite(rejected)||accepted<0||rejected<0||accepted+rejected>purchaseOrder.ordered_quantity)throw new Error("PROCUREMENT_RECEIPT_QUANTITY_INVALID");
 const posted=(movements||[]).filter(m=>m.source_type==="procurement_receipt"&&m.source_order_id===purchaseOrder.id&&m.status==="posted").reduce((s,m)=>s+Number(m.quantity_base||0),0);
 if(Math.abs(posted-accepted)>0.000001)throw new Error("PROCUREMENT_STOCK_MOVEMENT_MISMATCH");
 if(Math.abs(Number(inventoryBalance)-posted)>0.000001)throw new Error("PROCUREMENT_INVENTORY_BALANCE_MISMATCH");
 return Object.freeze({purchase_order_id:purchaseOrder.id,ordered_quantity:purchaseOrder.ordered_quantity,accepted_quantity:accepted,rejected_quantity:rejected,posted_stock_quantity:posted,inventory_balance:inventoryBalance,reconciled:accepted===posted&&posted===Number(inventoryBalance)});
}
