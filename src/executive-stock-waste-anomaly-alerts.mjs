/**
 * Executive operational risk alerts from reconciled stock, expiry, waste and sales/food-cost facts.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("EXECUTIVE_ALERT_INPUT_REQUIRED",f);return v.trim();};

/** Detect critical stock, near-expiry and waste risks using same-tenant reconciled inventory facts. */
export function evaluateExecutiveStockRisks(input){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId");
 const at=Date.parse(req(input.at,"at")),expiryHorizon=Number(input.expiryHorizonDays??7);
 if(!Number.isFinite(at)||!Number.isInteger(expiryHorizon)||expiryHorizon<0)fail("EXECUTIVE_STOCK_RISK_INPUT_INVALID","Timestamp and expiry horizon are required");
 const alerts=[];
 for(const row of input.stockRows||[]){
  if(row.tenantId!==tenantId||row.branchId!==branchId||row.reconciliationStatus!=="RECONCILED")
   fail("EXECUTIVE_STOCK_SOURCE_UNRECONCILED","Stock facts must be reconciled and same-branch");
  const onHand=Number(row.onHandQuantity),reorder=Number(row.reorderPointQuantity);
  if(!Number.isFinite(onHand)||onHand<0||!Number.isFinite(reorder)||reorder<0)fail("EXECUTIVE_STOCK_QUANTITY_INVALID","Stock quantities are invalid");
  if(onHand<=reorder)alerts.push(Object.freeze({type:"critical_stock",itemId:req(row.itemId,"itemId"),severity:onHand===0?"critical":"high",
   onHandQuantity:onHand,reorderPointQuantity:reorder}));
  if(row.expiryDate){
   const expiry=Date.parse(row.expiryDate+"T23:59:59Z");
   if(!Number.isFinite(expiry))fail("EXECUTIVE_EXPIRY_DATE_INVALID","Expiry date is invalid");
   const days=(expiry-at)/86400000;
   if(days>=0&&days<=expiryHorizon)alerts.push(Object.freeze({type:"near_expiry",itemId:req(row.itemId,"itemId"),
    lotId:req(row.lotId,"lotId"),severity:days<=1?"critical":"high",daysToExpiry:Number(days.toFixed(2))}));
  }
  const waste=Number(row.wasteQuantity??0),consumed=Number(row.consumedQuantity??0),threshold=Number(input.wasteRateThresholdPct??5);
  if(!Number.isFinite(waste)||waste<0||!Number.isFinite(consumed)||consumed<0||!Number.isFinite(threshold)||threshold<0)
   fail("EXECUTIVE_WASTE_METRIC_INVALID","Waste metrics are invalid");
  const wasteRate=consumed+waste===0?0:waste/(consumed+waste)*100;
  if(wasteRate>threshold)alerts.push(Object.freeze({type:"waste_variance",itemId:req(row.itemId,"itemId"),
   severity:wasteRate>threshold*2?"critical":"medium",wasteRatePct:Number(wasteRate.toFixed(2)),thresholdPct:threshold}));
 }
 return Object.freeze({tenantId,branchId,alerts:Object.freeze(alerts),alertCount:alerts.length});
}

/** Detect sales drop and food-cost anomalies only from reconciled comparison windows. */
export function evaluateSalesFoodCostAnomalies(input){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId");
 const rows=input.windows;
 if(!Array.isArray(rows)||rows.length<2)fail("EXECUTIVE_ANOMALY_HISTORY_REQUIRED","Baseline and current reconciled windows are required");
 for(const row of rows)if(row.tenantId!==tenantId||row.branchId!==branchId||row.reconciliationStatus!=="RECONCILED")
  fail("EXECUTIVE_ANOMALY_SOURCE_UNRECONCILED","Anomaly inputs must be reconciled and same-branch");
 const baseline=rows[0],current=rows.at(-1);
 const baseSales=Number(baseline.netSalesIdr),currentSales=Number(current.netSalesIdr);
 const baseCost=Number(baseline.foodCostPct),currentCost=Number(current.foodCostPct);
 if([baseSales,currentSales,baseCost,currentCost].some(n=>!Number.isFinite(n)||n<0))
  fail("EXECUTIVE_ANOMALY_METRIC_INVALID","Sales and food-cost metrics must be non-negative");
 const salesDropPct=baseSales===0?0:(baseSales-currentSales)/baseSales*100;
 const foodCostIncreasePp=currentCost-baseCost;
 const salesThreshold=Number(input.salesDropThresholdPct??15),foodThreshold=Number(input.foodCostIncreaseThresholdPp??3);
 const alerts=[];
 if(salesDropPct>=salesThreshold)alerts.push(Object.freeze({type:"sales_drop",severity:salesDropPct>=salesThreshold*2?"critical":"high",
  baselineNetSalesIdr:baseSales,currentNetSalesIdr:currentSales,changePct:Number(salesDropPct.toFixed(2))}));
 if(foodCostIncreasePp>=foodThreshold)alerts.push(Object.freeze({type:"food_cost_increase",severity:foodCostIncreasePp>=foodThreshold*2?"critical":"high",
  baselineFoodCostPct:baseCost,currentFoodCostPct:currentCost,changePp:Number(foodCostIncreasePp.toFixed(2))}));
 return Object.freeze({tenantId,branchId,alerts:Object.freeze(alerts),alertCount:alerts.length});
}
