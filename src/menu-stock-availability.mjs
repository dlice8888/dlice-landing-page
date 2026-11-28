/** Atomic stock-aware menu reservation command contract. */
export function buildMenuStockReservation({tenantId,branchId,productId,requestedQuantity,onHand,reserved,safetyStock,expectedStockVersion,actualStockVersion,idempotencyKey,expiresAt,now}){
 if(!tenantId||!branchId||!productId||!Number.isInteger(requestedQuantity)||requestedQuantity<1)throw new Error("MENU_RESERVATION_CONTEXT_INVALID");
 if(expectedStockVersion!==actualStockVersion)throw new Error("MENU_STOCK_STALE_VERSION");
 const available=Number(onHand)-Number(reserved)-Number(safetyStock||0);if(!Number.isFinite(available)||available<requestedQuantity)throw new Error("MENU_STOCK_UNAVAILABLE");
 if(typeof idempotencyKey!=="string"||idempotencyKey.trim().length<16)throw new Error("MENU_RESERVATION_IDEMPOTENCY_REQUIRED");
 if(Date.parse(expiresAt)<=Date.parse(now))throw new Error("MENU_RESERVATION_EXPIRY_INVALID");
 return Object.freeze({tenant_id:tenantId,branch_id:branchId,product_id:productId,quantity:requestedQuantity,expected_stock_version:expectedStockVersion,idempotency_key:idempotencyKey.trim(),expires_at:expiresAt,atomic_reserve_required:true});
}
