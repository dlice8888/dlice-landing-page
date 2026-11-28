/** Inventory balance projection from opening balance and posted movement ledger. */
export function calculateInventoryBalance({openingQuantity,movements,tenantId,branchId,itemId}){
 if(!tenantId||!branchId||!itemId||!Number.isFinite(openingQuantity)||openingQuantity<0)throw new Error("INVENTORY_BALANCE_CONTEXT_INVALID");
 let balance=openingQuantity;const seen=new Set();
 for(const m of movements||[]){if(m.tenant_id!==tenantId||m.branch_id!==branchId||m.item_id!==itemId)continue;if(!m.id||seen.has(m.id))throw new Error("INVENTORY_MOVEMENT_DUPLICATE");seen.add(m.id);if(m.status!=="posted")continue;if(!Number.isFinite(m.quantity_base)||m.quantity_base===0)throw new Error("INVENTORY_MOVEMENT_QUANTITY_INVALID");balance+=m.direction==="in"?m.quantity_base:m.direction==="out"?-m.quantity_base:NaN;if(!Number.isFinite(balance))throw new Error("INVENTORY_BALANCE_INVALID");}
 if(balance<0)throw new Error("INVENTORY_NEGATIVE_BALANCE");
 return Object.freeze({tenant_id:tenantId,branch_id:branchId,item_id:itemId,on_hand:balance,movement_count:seen.size,ledger_derived:true});
}
