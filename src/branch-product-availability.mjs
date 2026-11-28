/** Branch-specific product availability and override validation. */
export function evaluateBranchProductAvailability({productId,branchId,branchEnabled,productActive,stockTracked,onHand,reserved,safetyStock=0,scheduleAvailable=true,override,actorCanOverride=false}){
 if(!productId||!branchId)throw new Error("BRANCH_PRODUCT_CONTEXT_REQUIRED");
 if(override!==undefined&&!actorCanOverride)throw new Error("BRANCH_PRODUCT_OVERRIDE_FORBIDDEN");
 const availableStock=stockTracked?Number(onHand)-Number(reserved)-Number(safetyStock):Number.POSITIVE_INFINITY;
 if(stockTracked&&(!Number.isFinite(availableStock)||availableStock<0))throw new Error("BRANCH_PRODUCT_STOCK_INVALID");
 const policyEnabled=override===false?false:(override===true||branchEnabled===true);\n const available=productActive===true&&policyEnabled&&scheduleAvailable===true&&availableStock>0;
 return Object.freeze({product_id:productId,branch_id:branchId,available,reason:available?null:!productActive?"product_inactive":!branchEnabled?"branch_disabled":!scheduleAvailable?"outside_schedule":"stock_unavailable",available_stock:stockTracked?availableStock:null});
}
