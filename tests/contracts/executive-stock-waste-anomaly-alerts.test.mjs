import test from "node:test";
import assert from "node:assert/strict";
import {evaluateExecutiveStockRisks,evaluateSalesFoodCostAnomalies} from "../../src/executive-stock-waste-anomaly-alerts.mjs";

test("executive stock risk detects zero stock, near expiry and high waste",()=>{
 const result=evaluateExecutiveStockRisks({tenantId:"tenant-a",branchId:"branch-a",at:"2026-11-27T00:00:00Z",
  expiryHorizonDays:7,wasteRateThresholdPct:5,stockRows:[
   {tenantId:"tenant-a",branchId:"branch-a",reconciliationStatus:"RECONCILED",itemId:"flour",onHandQuantity:0,reorderPointQuantity:10,
    expiryDate:"2026-11-29",lotId:"lot-a",wasteQuantity:10,consumedQuantity:20},
  ]});
 assert.equal(result.alertCount,3);
 assert.deepEqual(result.alerts.map(x=>x.type),["critical_stock","near_expiry","waste_variance"]);
});
test("executive stock alerts reject unreconciled and cross-branch data",()=>{
 assert.throws(()=>evaluateExecutiveStockRisks({tenantId:"tenant-a",branchId:"branch-a",at:"2026-11-27T00:00:00Z",
  stockRows:[{tenantId:"tenant-a",branchId:"branch-b",reconciliationStatus:"RECONCILED",itemId:"x",onHandQuantity:0,reorderPointQuantity:1}]}),
  {code:"EXECUTIVE_STOCK_SOURCE_UNRECONCILED"});
});
test("sales drop and food-cost increase anomalies require reconciled comparison windows",()=>{
 const result=evaluateSalesFoodCostAnomalies({tenantId:"tenant-a",branchId:"branch-a",salesDropThresholdPct:15,foodCostIncreaseThresholdPp:3,
  windows:[
   {tenantId:"tenant-a",branchId:"branch-a",reconciliationStatus:"RECONCILED",netSalesIdr:100000,foodCostPct:30},
   {tenantId:"tenant-a",branchId:"branch-a",reconciliationStatus:"RECONCILED",netSalesIdr:70000,foodCostPct:35},
  ]});
 assert.equal(result.alertCount,2);
 assert.deepEqual(result.alerts.map(x=>x.type),["sales_drop","food_cost_increase"]);
});
test("anomaly detection refuses pending or mismatched source facts",()=>{
 assert.throws(()=>evaluateSalesFoodCostAnomalies({tenantId:"tenant-a",branchId:"branch-a",windows:[
  {tenantId:"tenant-a",branchId:"branch-a",reconciliationStatus:"RECONCILED",netSalesIdr:100,foodCostPct:20},
  {tenantId:"tenant-a",branchId:"branch-a",reconciliationStatus:"PENDING",netSalesIdr:80,foodCostPct:30},
 ]}),{code:"EXECUTIVE_ANOMALY_SOURCE_UNRECONCILED"});
});
