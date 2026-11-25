/**
 * Validates BI snapshot lineage/freshness before publication.
 * All source rows and reconciliation evidence must be fetched server-side.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function validateBiSnapshotLineage({tenantId,metric,formulaVersion,periodStart,periodEnd,sourceRows,watermarks,reconciliations,now=Date.now()}) {
 if(!tenantId||!metric?.id||metric.status!=="active"||!formulaVersion||formulaVersion!==metric.approvedFormulaVersion)fail("APPROVED_METRIC_FORMULA_REQUIRED","Active metric and approved formula version are required");
 const start=Date.parse(periodStart),end=Date.parse(periodEnd);
 if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start)fail("BI_PERIOD_INVALID","A valid non-empty reporting period is required");
 const declared=new Set(metric.declaredSourceKeys??[]);
 if(!declared.size)fail("BI_SOURCE_LINEAGE_EMPTY","Metric must declare source lineage");
 const sources=new Set((sourceRows??[]).map(x=>x.sourceKey));
 for(const source of declared)if(!sources.has(source))fail("BI_SOURCE_ROW_MISSING",source);
 const maxAgeMs=(metric.freshnessSlaMinutes??0)*60_000;
 if(!Number.isSafeInteger(metric.freshnessSlaMinutes)||metric.freshnessSlaMinutes<=0)fail("BI_FRESHNESS_SLA_REQUIRED","Metric freshness SLA must be approved");
 const missing=[];
 for(const source of declared){
  const candidates=(watermarks??[]).filter(w=>w.tenantId===tenantId&&w.sourceKey===source&&w.status==="complete"&&Date.parse(w.windowStart)<=start&&Date.parse(w.windowEnd)>=end);
  const w=candidates.sort((a,b)=>Date.parse(b.observedAt)-Date.parse(a.observedAt))[0];
  if(!w||w.expectedCount==null||w.observedCount!==w.expectedCount||now-Date.parse(w.observedAt)>maxAgeMs)missing.push(source);
 }
 if(missing.length)fail("BI_LINEAGE_WATERMARK_STALE_OR_INCOMPLETE",missing.join(","));
 const validReconciliation=(reconciliations??[]).filter(r=>r.tenantId===tenantId&&r.status==="passed"&&r.reviewedBy&&r.reviewedAt&&Date.parse(r.periodStart)<=start&&Date.parse(r.periodEnd)>=end);
 if(!validReconciliation.length)fail("BI_SOURCE_RECONCILIATION_REQUIRED","At least one reviewed, passed reconciliation covering the reporting period is required");
 for(const row of sourceRows??[])if(!declared.has(row.sourceKey)||row.tenantId!==tenantId||!row.sourceId||!row.sourceHash)fail("BI_SOURCE_LINEAGE_ROW_INVALID","Every source row needs tenant, source id and immutable hash");
 return Object.freeze({eligible:true,tenantId,metricId:metric.id,formulaVersion,periodStart,periodEnd,sourceKeys:Object.freeze([...declared].sort()),sourceRowCount:sourceRows.length,reconciliationIds:Object.freeze(validReconciliation.map(x=>x.id))});
}
