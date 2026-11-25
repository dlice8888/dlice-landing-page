/** Verified branch target-vs-actual aggregation from reconciled source facts. */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function aggregateVerifiedBranchPerformance({tenantId,branches,targets,facts,periodStart,periodEnd,requiredBranchCount=150}) {
 if(!tenantId||!Array.isArray(branches)||branches.length!==requiredBranchCount)fail("BRANCH_COVERAGE_INCOMPLETE",`Expected ${requiredBranchCount} branches`);
 const ids=new Set(branches.map(b=>b.id));if(ids.size!==branches.length||branches.some(b=>b.tenantId!==tenantId||b.status!=="active"))fail("BRANCH_POPULATION_INVALID","Branch population must be unique, active and tenant scoped");
 const targetMap=new Map((targets??[]).map(t=>[t.branchId,t])),factMap=new Map();
 for(const f of facts??[]){if(f.tenantId!==tenantId||!ids.has(f.branchId)||f.reconciliationStatus!=="reconciled"||f.periodStart!==periodStart||f.periodEnd!==periodEnd||!Number.isSafeInteger(f.netSalesIdr)||f.netSalesIdr<0)fail("BRANCH_FACT_NOT_RECONCILED","Branch facts must be reconciled for exact period");if(factMap.has(f.branchId))fail("DUPLICATE_BRANCH_FACT","Only one reconciled aggregate per branch allowed");factMap.set(f.branchId,f);}
 const rows=branches.map(b=>{const t=targetMap.get(b.id),f=factMap.get(b.id);if(!t||!Number.isSafeInteger(t.netSalesTargetIdr)||t.netSalesTargetIdr<0||!f)fail("BRANCH_TARGET_OR_ACTUAL_MISSING",b.id);return Object.freeze({branchId:b.id,targetIdr:t.netSalesTargetIdr,actualIdr:f.netSalesIdr,varianceIdr:f.netSalesIdr-t.netSalesTargetIdr,achievementBps:t.netSalesTargetIdr===0?null:Math.floor(f.netSalesIdr*10000/t.netSalesTargetIdr),sourceRefs:Object.freeze(f.sourceRefs??[])});});
 rows.sort((a,b)=>b.actualIdr-a.actualIdr);return Object.freeze({tenantId,periodStart,periodEnd,branchCount:rows.length,ranked:Object.freeze(rows),totalTargetIdr:rows.reduce((s,x)=>s+x.targetIdr,0),totalActualIdr:rows.reduce((s,x)=>s+x.actualIdr,0),status:"verified_source_reconciled"});
}
