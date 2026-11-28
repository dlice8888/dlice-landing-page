/** Separate made-to-order and batch production routing. */
export function resolveProductionMode({productId,branchId,configuredMode,batchAvailable,allowOnDemandFallback=false,overrideMode,actorCanOverride=false}){
 if(!productId||!branchId||!["made_to_order","batch"].includes(configuredMode))throw new Error("PRODUCTION_MODE_CONFIG_INVALID");
 let mode=configuredMode;
 if(overrideMode){if(!actorCanOverride||!["made_to_order","batch"].includes(overrideMode))throw new Error("PRODUCTION_MODE_OVERRIDE_FORBIDDEN");mode=overrideMode;}
 if(mode==="batch"&&!batchAvailable){if(!allowOnDemandFallback)throw new Error("PRODUCTION_BATCH_UNAVAILABLE");mode="made_to_order";}
 return Object.freeze({product_id:productId,branch_id:branchId,production_mode:mode,source:mode==="batch"?"production_batch":"kitchen_ticket",fallback:configuredMode==="batch"&&mode==="made_to_order"});
}
