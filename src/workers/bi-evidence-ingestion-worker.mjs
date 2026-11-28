/**
 * Evidence-first BI worker. It records source completeness, creates a pending
 * reconciliation and a draft snapshot. It never self-approves or publishes.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const need=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("BI_INPUT_REQUIRED",k+" is required");return v.trim();};
export async function runBiEvidenceIngestion({tenantId,actorId,periodStart,periodEnd,metrics,collectSource,calculateMetric,adapter,runIdempotencyKey}){
 need(tenantId,"tenantId");need(actorId,"actorId");need(periodStart,"periodStart");need(periodEnd,"periodEnd");need(runIdempotencyKey,"runIdempotencyKey");
 if(Date.parse(periodEnd)<=Date.parse(periodStart))fail("BI_PERIOD_INVALID","BI period end must be after period start");
 if(!Array.isArray(metrics)||!metrics.length)fail("BI_METRICS_REQUIRED","At least one metric is required");
 if(typeof collectSource!=="function"||typeof calculateMetric!=="function")fail("BI_COLLECTORS_REQUIRED","Source and metric collectors are required");
 for(const name of ["recordSourceWatermark","createReconciliationRun","createMetricSnapshot"])if(typeof adapter?.[name]!=="function")fail("BI_ADAPTER_INCOMPLETE",name+" adapter is required");
 const results=[];
 for(const metric of metrics){
  try{
   if(!metric?.id||!Number.isInteger(metric.formulaVersion)||!Array.isArray(metric.sourceEntities)||!metric.sourceEntities.length)
    fail("BI_METRIC_DEFINITION_INVALID","Metric definition is incomplete");
   const watermarks=[],evidence=[];
   for(const sourceKey of metric.sourceEntities){
    const collected=await collectSource({tenantId,sourceKey,periodStart,periodEnd});
    if(!collected||typeof collected!=="object")fail("BI_SOURCE_EVIDENCE_INVALID","Collector returned no evidence for "+sourceKey);
    const ingestionRunId=(runIdempotencyKey+":"+metric.id+":"+sourceKey).slice(0,160);
    const recorded=await adapter.recordSourceWatermark({tenantId,sourceKey,windowStart:collected.windowStart,windowEnd:collected.windowEnd,
     maxSourceUpdatedAt:collected.maxSourceUpdatedAt,expectedCount:collected.expectedCount,observedCount:collected.observedCount,ingestionRunId,actorId});
    if(!recorded?.watermark_id)fail("BI_WATERMARK_NOT_PERSISTED","Watermark was not persisted for "+sourceKey);
    watermarks.push(recorded.watermark_id);evidence.push({sourceKey,collected,watermark:recorded});
   }
   const calculated=await calculateMetric({tenantId,metric,periodStart,periodEnd,evidence});
   if(!calculated||!Number.isFinite(Number(calculated.metricValue))||!calculated.reconciliation)
    fail("BI_METRIC_CALCULATION_INVALID","Metric calculator must return a finite value and reconciliation totals");
   const reconciliation=calculated.reconciliation;
   const reconciliationKey=(runIdempotencyKey+":"+metric.id+":recon").slice(0,120);
   const recon=await adapter.createReconciliationRun({tenantId,periodStart:periodStart.slice(0,10),periodEnd:periodEnd.slice(0,10),
    sourceDomain:metric.ownerDomain||"bi",sourceReference:reconciliation.sourceReference||reconciliationKey,
    expectedTotal:reconciliation.expectedTotal,observedTotal:reconciliation.observedTotal,tolerance:reconciliation.tolerance??0,
    idempotencyKey:reconciliationKey,actorId});
   if(!recon?.reconciliation_id)fail("BI_RECONCILIATION_NOT_PERSISTED","Reconciliation run was not persisted");
   const snapshotKey=(runIdempotencyKey+":"+metric.id+":snapshot").slice(0,120);
   const snapshot=await adapter.createMetricSnapshot({tenantId,metricId:metric.id,periodStart,periodEnd,
    dimensionKey:calculated.dimensionKey||"all",dimensionValue:calculated.dimensionValue||"all",metricValue:Number(calculated.metricValue),
    sourceWatermarkIds:watermarks,reconciliationRunIds:[recon.reconciliation_id],formulaVersion:metric.formulaVersion,
    idempotencyKey:snapshotKey,actorId});
   if(!snapshot?.snapshot_id)fail("BI_SNAPSHOT_NOT_PERSISTED","Draft snapshot was not persisted");
   results.push({metricId:metric.id,status:"pending_review",watermarkIds:watermarks,reconciliationId:recon.reconciliation_id,snapshotId:snapshot.snapshot_id});
  }catch(error){results.push({metricId:metric?.id||null,status:"failed",errorCode:error?.code||"BI_INGESTION_FAILED"});}
 }
 return Object.freeze({status:results.every(x=>x.status==="pending_review")?"pending_review":"partial",metricCount:metrics.length,
  published:false,results:Object.freeze(results.map(Object.freeze))});
}
