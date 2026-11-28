/** Executive KPI gate: Finance-backed, reconciled metrics only. */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function verifyExecutiveFinanceKpi({tenantId,metric,periodStart,periodEnd,financeFacts,sourceReconciliations,targets}) {
 if(!tenantId||!metric?.id||metric.sourceOfTruth!=="finance"||metric.status!=="approved"||!metric.formulaVersion)fail("FINANCE_KPI_DEFINITION_REQUIRED","Approved Finance-sourced KPI definition required");
 const facts=financeFacts??[];if(!facts.length)fail("FINANCE_KPI_FACTS_REQUIRED","Finance facts required");
 const valid=new Set((sourceReconciliations??[]).filter(r=>r.tenantId===tenantId&&r.status==="reconciled"&&r.reviewedBy&&r.periodStart<=periodStart&&r.periodEnd>=periodEnd).map(r=>r.sourceId));
 for(const f of facts)if(f.tenantId!==tenantId||f.metricId!==metric.id||f.formulaVersion!==metric.formulaVersion||f.periodStart!==periodStart||f.periodEnd!==periodEnd||f.status!=="posted"||!valid.has(f.sourceId)||!Number.isSafeInteger(f.amountIdr))fail("EXECUTIVE_FINANCE_FACT_UNVERIFIED","KPI facts must be posted and source reconciled");
 const actual=facts.reduce((s,f)=>s+f.amountIdr,0),target=targets?.amountIdr;if(!Number.isSafeInteger(target)||target<0)fail("EXECUTIVE_TARGET_REQUIRED","Approved target amount required");
 return Object.freeze({tenantId,metricId:metric.id,formulaVersion:metric.formulaVersion,periodStart,periodEnd,actualIdr:actual,targetIdr:target,varianceIdr:actual-target,sourceCount:facts.length,status:"verified_finance_reconciled"});
}
