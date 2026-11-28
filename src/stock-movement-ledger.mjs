/** Append-only stock movement posting command. */
export function buildStockMovementCommand({tenantId,branchId,itemId,sourceType,sourceId,quantityBase,direction,idempotencyKey,actorDomain}){
 if(!tenantId||!branchId||!itemId||!sourceType||!sourceId)throw new Error("STOCK_MOVEMENT_SOURCE_REQUIRED");
 if(!Number.isFinite(quantityBase)||quantityBase<=0||!["in","out"].includes(direction))throw new Error("STOCK_MOVEMENT_QUANTITY_INVALID");
 if(typeof idempotencyKey!=="string"||idempotencyKey.trim().length<16)throw new Error("STOCK_MOVEMENT_IDEMPOTENCY_REQUIRED");
 if(!actorDomain||actorDomain==="client")throw new Error("STOCK_MOVEMENT_ACTOR_FORBIDDEN");
 if(!["pos","production","procurement","transfer","waste","cycle_count","adjustment"].includes(sourceType))throw new Error("STOCK_MOVEMENT_SOURCE_TYPE_INVALID");
 return Object.freeze({tenant_id:tenantId,branch_id:branchId,item_id:itemId,source_type:sourceType,source_id:sourceId,quantity_base:quantityBase,direction,idempotency_key:idempotencyKey.trim(),append_only:true});
}
export function validateStockReversal({originalMovement,reversal,actorDomain}){
 if(!originalMovement?.id||originalMovement.status!=="posted"||!reversal?.source_id||reversal.source_id!==originalMovement.id)throw new Error("STOCK_REVERSAL_SOURCE_INVALID");
 if(reversal.quantity_base!==originalMovement.quantity_base||reversal.direction!==(originalMovement.direction==="in"?"out":"in"))throw new Error("STOCK_REVERSAL_MISMATCH");
 if(actorDomain==="client")throw new Error("STOCK_REVERSAL_ACTOR_FORBIDDEN");
 return Object.freeze({reverses_movement_id:originalMovement.id,append_reversal:true});
}
