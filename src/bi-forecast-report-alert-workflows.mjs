/**
 * BI forecasting, governed scheduled exports and closed-loop KPI alerts.
 * All source facts are server-loaded, reconciled and tenant-scoped.
 */
const fail=(code,message)=>{const error=new Error(message);error.code=code;throw error;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("BI_WORKFLOW_INPUT_REQUIRED",f);return v.trim();};
const adapter=(deps,name)=>{if(typeof deps?.[name]!=="function")fail("BI_WORKFLOW_ADAPTER_REQUIRED",name);return deps[name];};
const scope=(input,action)=>({tenantId:req(input?.tenantId,"tenantId"),actorId:req(input?.actorId,"actorId"),
 branchId:input?.branchId==null?null:req(input.branchId,"branchId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),action});
const txScope=(deps,s,fn)=>adapter(deps,"withTenantTransaction")(s,async tx=>{
 if(!tx)fail("BI_WORKFLOW_TRANSACTION_REQUIRED","Database transaction required");
 await adapter(deps,"authorize")(tx,s);return fn(tx);
});
const assertTenant=(row,s,name)=>{if(!row||row.tenantId!==s.tenantId||(s.branchId&&row.branchId!==s.branchId))fail("BI_WORKFLOW_SCOPE_MISMATCH",name);};

/** Weighted moving-average forecast using reconciled daily actuals only. */
export function buildDemandForecast(input){
 const tenantId=req(input?.tenantId,"tenantId"),itemId=req(input?.itemId,"itemId");
 const horizon=Number(input.horizonDays??7);
 if(!Number.isInteger(horizon)||horizon<1||horizon>28)fail("BI_FORECAST_HORIZON_INVALID","Forecast horizon must be 1..28 days");
 if(!Array.isArray(input.dailyActuals)||input.dailyActuals.length<7)fail("BI_FORECAST_HISTORY_INSUFFICIENT","At least seven daily observations are required");
 const dates=new Set(),values=[];
 for(const row of input.dailyActuals){
  if(row.tenantId!==tenantId||row.itemId!==itemId)fail("BI_FORECAST_SCOPE_MISMATCH","Actual rows must match tenant and item");
  if(row.status!=="reconciled")fail("BI_FORECAST_UNRECONCILED_SOURCE","Only reconciled actuals may be used");
  const date=req(row.businessDate,"businessDate"),value=Number(row.quantity);
  if(dates.has(date))fail("BI_FORECAST_DUPLICATE_DATE","One reconciled actual per business date is required");
  if(!Number.isFinite(Date.parse(date))||!Number.isFinite(value)||value<0)fail("BI_FORECAST_ACTUAL_INVALID","Business date and non-negative quantity are required");
  dates.add(date);values.push({date,value});
 }
 values.sort((a,b)=>a.date.localeCompare(b.date));
 const window=values.slice(-7),denominator=window.reduce((sum,_x,i)=>sum+i+1,0);
 const base=window.reduce((sum,x,i)=>sum+x.value*(i+1),0)/denominator;
 const first=window[0].value,last=window.at(-1).value;
 const trend=window.length>1?(last-first)/(window.length-1):0;
 const forecasts=Array.from({length:horizon},(_,i)=>Object.freeze({
  dayOffset:i+1,quantity:Number(Math.max(0,base+trend*(i+1)).toFixed(3)),
 }));
 return Object.freeze({tenantId,itemId,model:"weighted-moving-average-v1",historyCount:values.length,
  sourceStart:values[0].date,sourceEnd:values.at(-1).date,forecasts:Object.freeze(forecasts)});
}

/** Compute WAPE and bias only from paired reconciled forecast/actual facts. */
export function evaluateForecastAccuracy(input){
 if(!Array.isArray(input.rows)||!input.rows.length)fail("BI_FORECAST_EVALUATION_REQUIRED","Paired forecast and actual rows are required");
 let absoluteError=0,actualTotal=0,bias=0;
 for(const row of input.rows){
  if(row.forecastStatus!=="published"||row.actualStatus!=="reconciled")fail("BI_FORECAST_EVALUATION_UNRECONCILED","Published forecast and reconciled actual are required");
  const f=Number(row.forecastQuantity),a=Number(row.actualQuantity);
  if(!Number.isFinite(f)||!Number.isFinite(a)||f<0||a<0)fail("BI_FORECAST_EVALUATION_VALUE_INVALID","Forecast and actual quantities must be non-negative");
  absoluteError+=Math.abs(f-a);actualTotal+=a;bias+=f-a;
 }
 return Object.freeze({sampleCount:input.rows.length,absoluteError:Number(absoluteError.toFixed(3)),
  wapePct:actualTotal===0?null:Number((absoluteError/actualTotal*100).toFixed(2)),
  bias:Number(bias.toFixed(3))});
}

/** Persist a forecast from authoritative reconciled source rows and an approved model. */
export async function publishDemandForecast(input,deps){
 const s=scope(input,"bi.forecast.publish"),itemId=req(input.itemId,"itemId");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findForecastByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",forecastId:prior.id});
  const model=await adapter(deps,"loadApprovedForecastModel")(tx,{...s,itemId});
  if(!model||model.status!=="approved")fail("BI_FORECAST_MODEL_NOT_APPROVED","Approved forecast model is required");
  const actuals=await adapter(deps,"loadReconciledDailyDemand")(tx,{...s,itemId});
  const forecast=buildDemandForecast({tenantId:s.tenantId,itemId,horizonDays:input.horizonDays,dailyActuals:actuals});
  const saved=await adapter(deps,"persistForecastSnapshot")(tx,{...s,...forecast,modelVersion:model.version});
  if(!saved?.id)fail("BI_FORECAST_PERSIST_FAILED","Forecast snapshot was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"bi.demand_forecast.published",entityType:"bi_demand_forecast",entityId:saved.id,
   metadata:{itemId,modelVersion:model.version,sourceEnd:forecast.sourceEnd}});
  return Object.freeze({status:"published",forecastId:saved.id,forecast});
 });
}

/** Create a scheduled export from an approved report definition and tenant members only. */
export async function createScheduledExecutiveReport(input,deps){
 const s=scope(input,"bi.report.schedule"),reportDefinitionId=req(input.reportDefinitionId,"reportDefinitionId");
 const schedule=req(input.schedule,"schedule"),format=input.format??"csv";
 if(!["csv","xlsx","pdf"].includes(format))fail("BI_REPORT_FORMAT_INVALID","Unsupported report format");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findScheduledReportByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",scheduleId:prior.id});
  const definition=await adapter(deps,"loadApprovedReportDefinition")(tx,{...s,reportDefinitionId});
  assertTenant(definition,s,"reportDefinition");
  if(definition.status!=="approved"||!Array.isArray(definition.allowedColumns)||definition.allowedColumns.length===0)
   fail("BI_REPORT_DEFINITION_NOT_APPROVED","Approved report definition with governed columns is required");
  const recipients=await adapter(deps,"resolveTenantReportRecipients")(tx,{...s,recipientIds:input.recipientIds??[]});
  if(!Array.isArray(recipients)||recipients.length===0||recipients.some(r=>r.tenantId!==s.tenantId||r.active!==true))
   fail("BI_REPORT_RECIPIENT_SCOPE_INVALID","All recipients must be active members of the same tenant");
  const saved=await adapter(deps,"persistScheduledReport")(tx,{...s,reportDefinitionId,schedule,format,
   allowedColumns:definition.allowedColumns,recipientIds:recipients.map(r=>r.userId)});
  if(!saved?.id)fail("BI_REPORT_SCHEDULE_PERSIST_FAILED","Scheduled report was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"bi.report.scheduled",entityType:"bi_scheduled_report",entityId:saved.id,
   metadata:{reportDefinitionId,format,recipientCount:recipients.length}});
  return Object.freeze({status:"scheduled",scheduleId:saved.id,recipientCount:recipients.length});
 });
}

/** Transition an alert through assigned -> resolved -> independently verified. */
export async function transitionKpiAlert(input,deps){
 const s=scope(input,"bi.alert.transition"),alertId=req(input.alertId,"alertId"),decision=input.decision;
 if(!["assign","resolve","verify"].includes(decision))fail("BI_ALERT_DECISION_INVALID","Unsupported alert transition");
 return txScope(deps,s,async tx=>{
  const alert=await adapter(deps,"loadKpiAlertForUpdate")(tx,{...s,alertId});assertTenant(alert,s,"alert");
  if(decision==="assign"){
   if(alert.status!=="open")fail("BI_ALERT_TRANSITION_INVALID","Only open alerts may be assigned");
   const assigneeId=req(input.assigneeId,"assigneeId");
   const assignee=await adapter(deps,"loadTenantAlertAssignee")(tx,{...s,assigneeId});
   assertTenant(assignee,s,"assignee");
   const updated=await adapter(deps,"assignKpiAlert")(tx,{...s,alertId,assigneeId});
   if(!updated?.id||updated.status!=="assigned")fail("BI_ALERT_ASSIGN_FAILED","Alert assignment was not persisted");
   await adapter(deps,"appendAudit")(tx,{...s,action:"bi.alert.assigned",entityType:"bi_kpi_alert",entityId:alertId});
   return Object.freeze({status:"assigned",alertId});
  }
  if(decision==="resolve"){
   if(alert.status!=="assigned"||alert.assignedTo!==s.actorId)fail("BI_ALERT_RESOLUTION_ACTOR_INVALID","Only the assigned owner may resolve an assigned alert");
   const actionEvidence=req(input.actionEvidence,"actionEvidence");
   const updated=await adapter(deps,"resolveKpiAlert")(tx,{...s,alertId,actionEvidence});
   if(!updated?.id||updated.status!=="resolved")fail("BI_ALERT_RESOLUTION_FAILED","Alert resolution was not persisted");
   await adapter(deps,"appendAudit")(tx,{...s,action:"bi.alert.resolved",entityType:"bi_kpi_alert",entityId:alertId});
   return Object.freeze({status:"resolved",alertId});
  }
  if(alert.status!=="resolved"||alert.assignedTo===s.actorId)fail("BI_ALERT_INDEPENDENT_VERIFIER_REQUIRED","A different actor must verify a resolved alert");
  const outcome=await adapter(deps,"loadAuthoritativeAlertOutcome")(tx,{...s,alertId});
  if(!outcome||outcome.tenantId!==s.tenantId||outcome.reconciled!==true||outcome.improved!==true)
   fail("BI_ALERT_OUTCOME_NOT_VERIFIED","Authoritative reconciled KPI outcome must demonstrate improvement");
  const updated=await adapter(deps,"verifyKpiAlertOutcome")(tx,{...s,alertId,outcomeRevision:req(outcome.revision,"outcome.revision")});
  if(!updated?.id||updated.status!=="verified")fail("BI_ALERT_VERIFICATION_FAILED","Alert verification was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"bi.alert.verified",entityType:"bi_kpi_alert",entityId:alertId});
  return Object.freeze({status:"verified",alertId,outcomeRevision:outcome.revision});
 });
}
