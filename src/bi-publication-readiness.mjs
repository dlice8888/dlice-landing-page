/**
 * BI snapshot publication gate. It validates lineage and freshness evidence;
 * it does not perform ingestion, aggregation, or publish database snapshots.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
export function evaluateBiPublication({metric,formula,window,sourceRuns,reconciliation,reviewer,now=new Date()}) {
 if(!metric?.active||!metric.id||!Number.isInteger(metric.formulaVersion)||metric.formulaVersion<1)fail("ACTIVE_METRIC_REQUIRED","Active metric definition/version is required");
 if(!formula?.approved||formula.version!==metric.formulaVersion||!formula.approvedBy)fail("FORMULA_NOT_GOVERNED","Formula must be approved at the metric's current version");
 if(!window?.start||!window?.end||new Date(window.end)<=new Date(window.start))fail("INVALID_METRIC_WINDOW","Metric window is invalid");
 if(!Array.isArray(metric.sourceEntities)||!metric.sourceEntities.length||!Array.isArray(sourceRuns))fail("LINEAGE_REQUIRED","Declared source entities and source runs are required");
 const bySource=new Map(sourceRuns.map(x=>[x.sourceKey,x]));
 for(const source of metric.sourceEntities){const run=bySource.get(source);if(!run||run.status!=="complete"||!run.lineageRef||!run.watermarkAt||!Number.isSafeInteger(run.recordCount)||run.recordCount<0)fail("SOURCE_LINEAGE_INCOMPLETE",source);const age=(now.getTime()-new Date(run.watermarkAt).getTime())/60000;if(!Number.isFinite(age)||age<0||age>metric.freshnessSlaMinutes)fail("SOURCE_STALE",source);if(run.windowStart>window.start||run.windowEnd<window.end)fail("SOURCE_WINDOW_INCOMPLETE",source);}
 if(!reconciliation||reconciliation.status!=="passed"||!reconciliation.evidenceRef||reconciliation.formulaVersion!==metric.formulaVersion)fail("SOURCE_RECONCILIATION_REQUIRED","Source reconciliation must pass for this formula version");
 if(!reviewer?.id||!reviewer.independent||reviewer.id===formula.approvedBy)fail("INDEPENDENT_REVIEW_REQUIRED","Publication reviewer must be independent from formula approver");
 return Object.freeze({publishable:true,metricId:metric.id,formulaVersion:metric.formulaVersion,windowStart:window.start,windowEnd:window.end,sourceLineage:metric.sourceEntities.map(source=>({sourceKey:source,lineageRef:bySource.get(source).lineageRef,watermarkAt:bySource.get(source).watermarkAt,recordCount:bySource.get(source).recordCount})),reconciliationRef:reconciliation.evidenceRef,reviewedBy:reviewer.id});
}
