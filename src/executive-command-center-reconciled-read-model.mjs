/**
 * Reconciled Executive Command Center read model.
 * One server-side transaction loads active branches and source revisions;
 * only fully reconciled, fresh branch facts contribute to group totals.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("ECC_READ_MODEL_INPUT_REQUIRED",f);return v.trim();};
const adapter=(d,n)=>{if(typeof d?.[n]!=="function")fail("ECC_READ_MODEL_ADAPTER_REQUIRED",n);return d[n];};
const integer=(v,f)=>{if(!Number.isSafeInteger(v)||v<0)fail("ECC_READ_MODEL_METRIC_INVALID",f);return v;};
const sourceNames=["pos","finance","inventory","delivery","hr","kds"];
const freshness=(source,asOf,maxAgeMs,name)=>{
 if(!source||source.status!=="reconciled"||!source.revision||!Number.isFinite(Date.parse(source.asOf)))
  fail("ECC_SOURCE_UNRECONCILED",name);
 const age=asOf-Date.parse(source.asOf);
 if(age<0||age>maxAgeMs)fail("ECC_SOURCE_STALE",name);
};
const sum=(rows,key)=>rows.reduce((n,row)=>{const v=integer(row[key],key),next=n+v;if(!Number.isSafeInteger(next))fail("ECC_TOTAL_OVERFLOW",key);return next;},0);

/** Required tx adapters: authorizeGroupRead, loadActiveBranches,
 * loadReconciledBranchCommandFacts, persistReadModelSnapshot, appendAudit.
 */
export async function buildExecutiveCommandCenterReadModel(input,deps){
 const tenantId=req(input?.tenantId,"tenantId"),actorId=req(input?.actorId,"actorId");
 const asOf=req(input?.asOf,"asOf"),asOfMs=Date.parse(asOf);
 if(!Number.isFinite(asOfMs))fail("ECC_READ_MODEL_TIME_INVALID","asOf must be ISO date/time");
 const expectedBranchCount=input.expectedBranchCount??150,maxAgeMs=input.maxSourceAgeMs??15*60*1000;
 if(!Number.isInteger(expectedBranchCount)||expectedBranchCount<1||!Number.isSafeInteger(maxAgeMs)||maxAgeMs<1)
  fail("ECC_READ_MODEL_CONFIG_INVALID","Expected branch count and freshness threshold are invalid");
 const scope=Object.freeze({tenantId,actorId,asOf,action:"executive.command_center.read"});
 return adapter(deps,"withTenantTransaction")(scope,async tx=>{
  if(!tx)fail("ECC_READ_MODEL_TRANSACTION_REQUIRED","Database transaction required");
  await adapter(deps,"authorizeGroupRead")(tx,scope);
  const branches=await adapter(deps,"loadActiveBranches")(tx,scope);
  if(!Array.isArray(branches))fail("ECC_BRANCH_SOURCE_INVALID","Active branch list is required");
  const branchIds=new Set();
  for(const b of branches){
   if(!b||b.tenantId!==tenantId||typeof b.id!=="string"||!b.id)fail("ECC_BRANCH_SCOPE_MISMATCH","Branch must belong to tenant");
   if(branchIds.has(b.id))fail("ECC_DUPLICATE_BRANCH","Duplicate active branch");
   branchIds.add(b.id);
  }
  const facts=await adapter(deps,"loadReconciledBranchCommandFacts")(tx,{...scope,branchIds:[...branchIds]});
  if(!Array.isArray(facts))fail("ECC_FACT_SOURCE_INVALID","Branch command facts are required");
  const byBranch=new Map();
  const sourceGaps=[];
  for(const fact of facts){
   if(!fact||fact.tenantId!==tenantId||!branchIds.has(fact.branchId))fail("ECC_FACT_SCOPE_MISMATCH","Fact must belong to an active tenant branch");
   if(byBranch.has(fact.branchId))fail("ECC_DUPLICATE_BRANCH_FACT","One consolidated fact row per branch is required");
   const branchGaps=[];
   for(const name of sourceNames){
    try{freshness(fact.sources?.[name],asOfMs,maxAgeMs,name);}catch(e){branchGaps.push({source:name,reason:e.code});}
   }
   if(branchGaps.length){sourceGaps.push({branchId:fact.branchId,gaps:branchGaps});continue;}
   for(const key of ["netSalesIdr","foodCostIdr","wasteIdr","openOrders","deliveryBreaches","stockoutCount","kdsBacklog"])
    integer(fact[key],key);
   if(!Number.isFinite(fact.labourCoveragePct)||fact.labourCoveragePct<0||fact.labourCoveragePct>100)
    fail("ECC_READ_MODEL_METRIC_INVALID","labourCoveragePct");
   if(!Number.isSafeInteger(fact.cashVarianceIdr))fail("ECC_READ_MODEL_METRIC_INVALID","cashVarianceIdr");
   byBranch.set(fact.branchId,Object.freeze({...fact}));
  }
  for(const id of branchIds)if(!byBranch.has(id)&&!sourceGaps.some(x=>x.branchId===id))sourceGaps.push({branchId:id,gaps:[{source:"all",reason:"ECC_BRANCH_FACT_MISSING"}]});
  const accepted=[...byBranch.values()];
  const totals={
   netSalesIdr:sum(accepted,"netSalesIdr"),foodCostIdr:sum(accepted,"foodCostIdr"),
   wasteIdr:sum(accepted,"wasteIdr"),openOrders:sum(accepted,"openOrders"),
   deliveryBreaches:sum(accepted,"deliveryBreaches"),stockoutCount:sum(accepted,"stockoutCount"),
   kdsBacklog:sum(accepted,"kdsBacklog"),
   cashVarianceIdr:accepted.reduce((n,row)=>n+row.cashVarianceIdr,0),
  };
  if(!Number.isSafeInteger(totals.cashVarianceIdr))fail("ECC_TOTAL_OVERFLOW","cashVarianceIdr");
  const coveragePct=branches.length===0?0:Number((accepted.length/branches.length*100).toFixed(2));
  const scaleCoveragePct=Number((Math.min(accepted.length,expectedBranchCount)/expectedBranchCount*100).toFixed(2));
  const snapshot={tenantId,asOf,expectedBranchCount,activeBranchCount:branches.length,
   reconciledBranchCount:accepted.length,coveragePct,scaleCoveragePct,
   status:accepted.length===branches.length&&branches.length>=expectedBranchCount?"complete":"partial",
   sourceGaps,totals,branches:accepted};
  const saved=await adapter(deps,"persistReadModelSnapshot")(tx,snapshot);
  if(!saved?.id)fail("ECC_READ_MODEL_PERSIST_FAILED","Read model snapshot was not persisted");
  await adapter(deps,"appendAudit")(tx,{...scope,action:"executive.command_center.snapshot_built",
   entityType:"executive_command_center_snapshots",entityId:saved.id,
   metadata:{activeBranchCount:branches.length,reconciledBranchCount:accepted.length,status:snapshot.status,coveragePct}});
  return Object.freeze({...snapshot,snapshotId:saved.id});
 });
}
