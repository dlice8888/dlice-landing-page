/** Reorder point and replenishment recommendation from demand/lead time. */
export function calculateReorderRecommendation({onHand,reserved,inTransit,averageDailyDemand,leadTimeDays,safetyStock,minimumOrderQuantity=0,maximumStock=Number.MAX_SAFE_INTEGER,supplierActive=true}){
 const v=[onHand,reserved,inTransit,averageDailyDemand,leadTimeDays,safetyStock,minimumOrderQuantity,maximumStock];if(!v.every(Number.isFinite)||onHand<0||reserved<0||inTransit<0||averageDailyDemand<0||leadTimeDays<0||safetyStock<0||minimumOrderQuantity<0||maximumStock<0)throw new Error("REORDER_INPUT_INVALID");
 if(!supplierActive)throw new Error("REORDER_SUPPLIER_INACTIVE");
 const available=onHand-reserved+inTransit,point=averageDailyDemand*leadTimeDays+safetyStock,shortfall=Math.max(0,point-available);
 const recommended=shortfall===0?0:Math.max(minimumOrderQuantity,Math.ceil(shortfall));
 if(available+recommended>maximumStock)throw new Error("REORDER_MAXIMUM_STOCK_EXCEEDED");
 return Object.freeze({available_stock:available,reorder_point:point,recommended_quantity:recommended,reason:recommended?"below_reorder_point":"stock_sufficient"});
}
