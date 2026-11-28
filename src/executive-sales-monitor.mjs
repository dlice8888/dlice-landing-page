/**
 * D01-F02: authoritative Executive sales monitor domain service.
 * All source reads, role resolution, KPI persistence and audit writes are
 * delegated to a tenant-scoped server transaction. Client scope is never trusted.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const required=(v,name)=>{if(typeof v!=="string"||!v.trim())fail("EXEC_SALES_INPUT_REQUIRED",name);return v.trim();};
const integer=(v,name)=>{if(!Number.isSafeInteger(v)||v<0)fail("EXEC_SALES_AMOUNT_INVALID",name);return v;};
const fn=(d,n)=>{if(typeof d?.[n]!=="function")fail("EXEC_SALES_ADAPTER_REQUIRED",n);return d[n];};
const validDate=(v,n)=>{if(typeof v!=="string"||!/^\d{4}-\d{2}-\d{2}$/.test(v)||Number.isNaN(Date.parse(v+"T00:00:00Z")))fail("EXEC_SALES_DATE_INVALID",n);return v;};
const periods={day:1,week:7,month:31};
const add=(a,b,n)=>{const v=a+b;if(!Number.isSafeInteger(v))fail("EXEC_SALES_OVERFLOW",n);return v;};
const amount=(r,k)=>integer(r[k],k);

/**
 * Required adapters:
 * withTenantTransaction(scope, fn), resolveSalesScope(tx, actor), loadSalesLedgerRows(tx, query),
 * loadFinanceSettlementTotals(tx, query), persistKpiSnapshot(tx, snapshot), appendAudit(tx,event).
 * loadSalesLedgerRows must return one canonical row per POS sale, with businessDate assigned
 * using the branch's configured IANA timezone and cutoff, plus processed refund rows/totals.
 */
export async function getExecutiveSalesMonitor(input,deps){
 const actorId=required(input?.actorId,"actorId");
 const tenantId=required(input?.tenantId,"tenantId");
 const period=input?.period??"day";
 if(!Object.hasOwn(periods,period))fail("EXEC_SALES_PERIOD_INVALID","period must be day, week or month");
 const startDate=validDate(input?.startDate,"startDate"),endDate=validDate(input?.endDate??startDate,"endDate");
 if(endDate<startDate)fail("EXEC_SALES_RANGE_INVALID","endDate precedes startDate");
 const timezone=required(input?.timezone,"timezone");
 try{new Intl.DateTimeFormat("en",{timeZone:timezone});}catch{fail("EXEC_SALES_TIMEZONE_INVALID","Invalid IANA timezone");}
 const requestedBranchIds=input?.branchIds;
 if(requestedBranchIds!==undefined&&(!Array.isArray(requestedBranchIds)||requestedBranchIds.some(x=>typeof x!=="string"||!x)))fail("EXEC_SALES_BRANCH_FILTER_INVALID","branchIds must be UUID strings");
 const scope=Object.freeze({actorId,tenantId,action:"executive.sales.read"});
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  const authorized=await fn(deps,"resolveSalesScope")(tx,scope);
  if(!authorized||authorized.tenantId!==tenantId||!Array.isArray(authorized.branchIds))fail("EXEC_SALES_SCOPE_DENIED","Authorized tenant and branch scope required");
  const allowed=new Set(authorized.branchIds);
  const branchIds=requestedBranchIds??[...allowed];
  if(branchIds.some(id=>!allowed.has(id)))fail("EXEC_SALES_BRANCH_SCOPE_DENIED","Requested branch is outside actor scope");
  const query=Object.freeze({tenantId,branchIds:[...branchIds],startDate,endDate,timezone,period,kpiVersion:"sales-net-v1"});
  const rows=await fn(deps,"loadSalesLedgerRows")(tx,query);
  const finance=await fn(deps,"loadFinanceSettlementTotals")(tx,query);
  if(!Array.isArray(rows)||!finance||!Array.isArray(finance.byBranch))fail("EXEC_SALES_SOURCE_INVALID","Canonical POS and Finance sources are required");
  const seen=new Set(),daily=new Map(),transactions=[];
  const totals={grossIdr:0,discountIdr:0,refundIdr:0,netIdr:0,settledIdr:0};
  for(const row of rows){
   if(!row||row.tenantId!==tenantId||!allowed.has(row.branchId)||!branchIds.includes(row.branchId))fail("EXEC_SALES_SOURCE_SCOPE_MISMATCH","Source row outside authorized tenant/branch");
   if(typeof row.saleId!=="string"||!row.saleId||seen.has(row.saleId))fail("EXEC_SALES_DUPLICATE_OR_INVALID_SALE","Each canonical sale must occur exactly once");
   seen.add(row.saleId);
   const businessDate=validDate(row.businessDate,"businessDate");
   if(businessDate<startDate||businessDate>endDate)continue;
   if(row.timezone!==timezone&&branchIds.length===1)fail("EXEC_SALES_TIMEZONE_SOURCE_MISMATCH","Requested timezone differs from branch business timezone");
   if(!["paid","partially_refunded","refunded"].includes(row.paymentStatus))continue;
   const gross=amount(row,"grossIdr"),discount=amount(row,"discountIdr"),refund=amount(row,"processedRefundIdr");
   if(discount>gross||refund>gross-discount)fail("EXEC_SALES_LEDGER_INVARIANT","Discount/refund exceeds gross sale");
   const net=gross-discount-refund;
   const item={saleId:row.saleId,branchId:row.branchId,businessDate,transactionCode:row.transactionCode??null,grossIdr:gross,discountIdr:discount,refundIdr:refund,netIdr:net,createdAt:row.createdAt};
   transactions.push(item);
   for(const [k,v] of Object.entries({grossIdr:gross,discountIdr:discount,refundIdr:refund,netIdr:net}))totals[k]=add(totals[k],v,k);
   const d=daily.get(businessDate)??{businessDate,grossIdr:0,discountIdr:0,refundIdr:0,netIdr:0,transactionCount:0};
   for(const k of ["grossIdr","discountIdr","refundIdr","netIdr"])d[k]=add(d[k],item[k],k);
   d.transactionCount++;daily.set(businessDate,d);
  }
  const financeByBranch=new Map();
  for(const f of finance.byBranch){
   if(f.tenantId!==tenantId||!branchIds.includes(f.branchId)||financeByBranch.has(f.branchId))fail("EXEC_SALES_FINANCE_SCOPE_INVALID","Finance settlement scope or uniqueness invalid");
   financeByBranch.set(f.branchId,integer(f.settledIdr,"settledIdr"));
  }
  for(const id of branchIds)totals.settledIdr=add(totals.settledIdr,financeByBranch.get(id)??0,"settledIdr");
  const snapshot={...query,totals,daily:[...daily.values()].sort((a,b)=>a.businessDate.localeCompare(b.businessDate)),transactions,sourceRowCount:rows.length,eligibleSaleCount:transactions.length,financeReconciliation:finance.reconciliation??null,generatedAt:new Date().toISOString()};
  const saved=await fn(deps,"persistKpiSnapshot")(tx,snapshot);
  if(!saved?.id)fail("EXEC_SALES_SNAPSHOT_PERSIST_FAILED","KPI snapshot was not persisted");
  await fn(deps,"appendAudit")(tx,{...scope,action:"executive.sales.snapshot_created",entityType:"executive_sales_snapshots",entityId:saved.id,metadata:{period,startDate,endDate,branchCount:branchIds.length,saleCount:transactions.length,kpiVersion:query.kpiVersion}});
  return Object.freeze({...snapshot,snapshotId:saved.id});
 });
}
