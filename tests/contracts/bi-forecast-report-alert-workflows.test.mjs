import test from "node:test";
import assert from "node:assert/strict";
import {
 buildDemandForecast,evaluateForecastAccuracy,publishDemandForecast,
 createScheduledExecutiveReport,transitionKpiAlert,
} from "../../src/bi-forecast-report-alert-workflows.mjs";

const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"analyst-a",idempotencyKey:"bi-flow-0001"};
const common=(overrides={})=>({
 withTenantTransaction:async(_s,fn)=>fn({tx:true}),
 authorize:async(_tx,s)=>{assert.equal(s.tenantId,"tenant-a");},
 appendAudit:async(_tx,e)=>{assert.ok(e.action.startsWith("bi."));},
 ...overrides,
});
const actuals=Array.from({length:7},(_,i)=>({tenantId:"tenant-a",itemId:"item-a",status:"reconciled",
 businessDate:`2026-11-${String(i+1).padStart(2,"0")}`,quantity:10+i}));

test("demand forecast uses reconciled same-tenant daily actuals and bounded horizon",()=>{
 const result=buildDemandForecast({tenantId:"tenant-a",itemId:"item-a",horizonDays:7,dailyActuals:actuals});
 assert.equal(result.forecasts.length,7);assert.equal(result.model,"weighted-moving-average-v1");
 assert.ok(result.forecasts[6].quantity>result.forecasts[0].quantity);
});
test("demand forecast rejects unreconciled, cross-tenant and duplicate actuals",()=>{
 assert.throws(()=>buildDemandForecast({tenantId:"tenant-a",itemId:"item-a",dailyActuals:actuals.map((x,i)=>i===0?{...x,status:"pending"}:x)}),
  {code:"BI_FORECAST_UNRECONCILED_SOURCE"});
 assert.throws(()=>buildDemandForecast({tenantId:"tenant-a",itemId:"item-a",dailyActuals:actuals.map((x,i)=>i===0?{...x,tenantId:"tenant-b"}:x)}),
  {code:"BI_FORECAST_SCOPE_MISMATCH"});
 assert.throws(()=>buildDemandForecast({tenantId:"tenant-a",itemId:"item-a",dailyActuals:[...actuals,actuals[0]]}),
  {code:"BI_FORECAST_DUPLICATE_DATE"});
});
test("forecast accuracy reports WAPE and bias from published and reconciled pairs",()=>{
 const result=evaluateForecastAccuracy({rows:[
  {forecastStatus:"published",actualStatus:"reconciled",forecastQuantity:110,actualQuantity:100},
  {forecastStatus:"published",actualStatus:"reconciled",forecastQuantity:90,actualQuantity:100},
 ]});
 assert.equal(result.wapePct,10);assert.equal(result.bias,0);
});
test("forecast accuracy refuses unreconciled actuals",()=>{
 assert.throws(()=>evaluateForecastAccuracy({rows:[{forecastStatus:"published",actualStatus:"pending",forecastQuantity:10,actualQuantity:9}]}),
  {code:"BI_FORECAST_EVALUATION_UNRECONCILED"});
});
test("forecast publication loads approved model and authoritative actuals",async()=>{
 const deps=common({
  findForecastByIdempotencyKey:async()=>null,
  loadApprovedForecastModel:async()=>({status:"approved",version:2}),
  loadReconciledDailyDemand:async()=>actuals,
  persistForecastSnapshot:async(_tx,row)=>{assert.equal(row.modelVersion,2);return{id:"forecast-a"};},
 });
 const result=await publishDemandForecast({...base,itemId:"item-a",horizonDays:7},deps);
 assert.equal(result.status,"published");assert.equal(result.forecastId,"forecast-a");
});
test("scheduled report requires approved definition and active same-tenant recipients",async()=>{
 const deps=common({
  findScheduledReportByIdempotencyKey:async()=>null,
  loadApprovedReportDefinition:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"approved",allowedColumns:["sales_net","food_cost"]}),
  resolveTenantReportRecipients:async()=>[{tenantId:"tenant-a",userId:"owner-a",active:true}],
  persistScheduledReport:async(_tx,row)=>{assert.deepEqual(row.allowedColumns,["sales_net","food_cost"]);return{id:"schedule-a"};},
 });
 const result=await createScheduledExecutiveReport({...base,reportDefinitionId:"report-a",schedule:"0 7 * * *",recipientIds:["owner-a"]},deps);
 assert.deepEqual(result,{status:"scheduled",scheduleId:"schedule-a",recipientCount:1});
});
test("scheduled report rejects cross-tenant recipients",async()=>{
 const deps=common({
  findScheduledReportByIdempotencyKey:async()=>null,
  loadApprovedReportDefinition:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"approved",allowedColumns:["sales_net"]}),
  resolveTenantReportRecipients:async()=>[{tenantId:"tenant-b",userId:"intruder",active:true}],
 });
 await assert.rejects(createScheduledExecutiveReport({...base,reportDefinitionId:"report-a",schedule:"0 7 * * *"},deps),
  {code:"BI_REPORT_RECIPIENT_SCOPE_INVALID"});
});
test("KPI alert must be assigned, resolved by owner and independently verified with improved reconciled outcome",async()=>{
 const states={status:"open",assignedTo:null,tenantId:"tenant-a",branchId:"branch-a"};
 const deps=common({
  loadKpiAlertForUpdate:async()=>({...states}),
  loadTenantAlertAssignee:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"manager-a"}),
  assignKpiAlert:async(_tx,row)=>{states.status="assigned";states.assignedTo=row.assigneeId;return{id:"alert-a",status:"assigned"};},
  resolveKpiAlert:async()=>{states.status="resolved";return{id:"alert-a",status:"resolved"};},
  loadAuthoritativeAlertOutcome:async()=>({tenantId:"tenant-a",reconciled:true,improved:true,revision:"kpi-rev-2"}),
  verifyKpiAlertOutcome:async()=>{states.status="verified";return{id:"alert-a",status:"verified"};},
 });
 assert.equal((await transitionKpiAlert({...base,alertId:"alert-a",decision:"assign",assigneeId:"manager-a"},deps)).status,"assigned");
 assert.equal((await transitionKpiAlert({...base,actorId:"manager-a",alertId:"alert-a",decision:"resolve",actionEvidence:"reduced waste"},deps)).status,"resolved");
 assert.equal((await transitionKpiAlert({...base,actorId:"owner-a",alertId:"alert-a",decision:"verify"},deps)).status,"verified");
});
test("KPI alert refuses same-actor verification and unreconciled outcome",async()=>{
 const deps=common({
  loadKpiAlertForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"resolved",assignedTo:"analyst-a"}),
  loadAuthoritativeAlertOutcome:async()=>({tenantId:"tenant-a",reconciled:false,improved:true,revision:"r1"}),
 });
 await assert.rejects(transitionKpiAlert({...base,alertId:"alert-a",decision:"verify"},deps),
  {code:"BI_ALERT_INDEPENDENT_VERIFIER_REQUIRED"});
 const other={...deps,loadKpiAlertForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"resolved",assignedTo:"manager-a"})};
 await assert.rejects(transitionKpiAlert({...base,alertId:"alert-a",decision:"verify"},other),
  {code:"BI_ALERT_OUTCOME_NOT_VERIFIED"});
});
