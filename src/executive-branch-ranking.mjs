/**
 * Ranks branches only from reconciled Finance-backed KPI snapshots and targets.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function rankReconciledBranches({tenantId,periodStart,periodEnd,branchSnapshots,targets,expectedBranchIds,limit=150}) {
 if(!tenantId||!Array.isArray(branchSnapshots)||!Number.isSafeInteger(limit)||limit<1||limit>150)fail("BRANCH_RANKING_INPUT_INVALID","Tenant, snapshots and a limit up to 150 are required");
 if(!Array.isArray(expectedBranchIds)||expectedBranchIds.length===0||expectedBranchIds.length>150||new Set(expectedBranchIds).size!==expectedBranchIds.length)fail("EXPECTED_BRANCH_SCOPE_REQUIRED","A unique authoritative branch scope of 1–150 branches is required");
 const targetByBranch=new Map((targets??[]).map(t=>[t.branchId,t]));
 const rows=[];
 for(const s of branchSnapshots){
  if(s.tenantId!==tenantId||s.periodStart!==periodStart||s.periodEnd!==periodEnd||s.status!=="reconciled"||!s.financeJournalBatchId||!s.sourceReconciliationId)continue;
  if(!s.branchId||!Number.isSafeInteger(s.netSalesIdr)||s.netSalesIdr<0)fail("BRANCH_KPI_SOURCE_INVALID","Branch KPI must have a valid Finance-backed net sales amount");
  const target=targetByBranch.get(s.branchId);
  if(!target||!Number.isSafeInteger(target.netSalesTargetIdr)||target.netSalesTargetIdr<=0)fail("BRANCH_TARGET_REQUIRED",s.branchId);
  rows.push({branchId:s.branchId,netSalesIdr:s.netSalesIdr,targetNetSalesIdr:target.netSalesTargetIdr,achievementBps:Math.floor(s.netSalesIdr*10000/target.netSalesTargetIdr),financeJournalBatchId:s.financeJournalBatchId,sourceReconciliationId:s.sourceReconciliationId});
 }
 rows.sort((a,b)=>b.netSalesIdr-a.netSalesIdr||a.branchId.localeCompare(b.branchId));
 return Object.freeze({tenantId,periodStart,periodEnd,branchCount:rows.length,ranking:Object.freeze(rows.slice(0,limit).map((r,i)=>Object.freeze({...r,rank:i+1})))});
}
