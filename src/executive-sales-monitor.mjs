/**
 * D01-F02: Executive sales monitor application boundary.
 * All authorization, branch timezone/cutoff calculation, source aggregation,
 * Finance links, snapshot persistence and audit writes execute in one SQL RPC.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const required=(v,name)=>{if(typeof v!=="string"||!v.trim())fail("EXEC_SALES_INPUT_REQUIRED",name);return v.trim();};
const validDate=(v,name)=>{
 if(typeof v!=="string"||!/^\\d{4}-\\d{2}-\\d{2}$/.test(v))fail("EXEC_SALES_DATE_INVALID",name);
 const d=new Date(v+"T00:00:00.000Z");
 if(Number.isNaN(d.getTime())||d.toISOString().slice(0,10)!==v)fail("EXEC_SALES_DATE_INVALID",name);
 return v;
};
const adapter=(deps,name)=>{if(typeof deps?.[name]!=="function")fail("EXEC_SALES_ADAPTER_REQUIRED",name);return deps[name];};
const periods=new Set(["day","week","month"]);
const moneyKeys=["gross_idr","discount_idr","refund_idr","net_sales_idr","matched_settlement_idr"];
const safeAmount=(value,key)=>{
 const n=Number(value);
 if(!Number.isSafeInteger(n)||n<0)fail("EXEC_SALES_RECONCILIATION_INVALID",key);
 return n;
};
const sum=(rows,key,refundKey)=>{
 return rows.reduce((total,row)=>total+safeAmount(refundKey?row[refundKey]:row[key],key),0);
};
function assertAggregateParity(result){
 const daily=result.daily,transactions=result.transactions,totals=result.totals;
 for(const key of moneyKeys){
  const dailyKey=key==="refund_idr"?"refund_idr":key;
  const transactionKey=key==="refund_idr"?"processed_refund_idr":key;
  if(sum(daily,dailyKey)!==safeAmount(totals[key],key)||
     sum(transactions,transactionKey)!==safeAmount(totals[key],key))
   fail("EXEC_SALES_RECONCILIATION_MISMATCH",key+" does not reconcile across totals, daily and source transactions");
 }
 if(transactions.length!==safeAmount(totals.transaction_count,"transaction_count"))
  fail("EXEC_SALES_RECONCILIATION_MISMATCH","transaction_count does not match source transaction rows");
}
export async function getExecutiveSalesMonitor(input,deps){
 const actorId=required(input?.actorId,"actorId"),tenantId=required(input?.tenantId,"tenantId");
 const period=input?.period??"day";
 if(!periods.has(period))fail("EXEC_SALES_PERIOD_INVALID","period must be day, week or month");
 const startDate=validDate(input?.startDate,"startDate"),endDate=validDate(input?.endDate??startDate,"endDate");
 if(endDate<startDate)fail("EXEC_SALES_RANGE_INVALID","endDate precedes startDate");
 const branchIds=input?.branchIds;
 if(branchIds!==undefined&&(!Array.isArray(branchIds)||branchIds.some(x=>typeof x!=="string"||!x.trim())||new Set(branchIds).size!==branchIds.length))
  fail("EXEC_SALES_BRANCH_FILTER_INVALID","branchIds must be unique non-empty IDs");
 const result=await adapter(deps,"loadSalesMonitorSnapshot")({actorId,tenantId,period,startDate,endDate,branchIds:branchIds??null});
 if(!result||typeof result!=="object"||!result.snapshot_id||result.tenant_id!==tenantId||
    result.formula_version!=="sales-net-v1"||!result.totals||!Array.isArray(result.daily)||
    !Array.isArray(result.transactions)||!result.finance_reconciliation||!result.payment_reconciliation||
    (result.period_type!==undefined&&result.period_type!==period)||
    (result.period_start!==undefined&&result.period_start!==startDate)||
    (result.period_end!==undefined&&result.period_end!==endDate))
  fail("EXEC_SALES_SNAPSHOT_INVALID","Server returned an incomplete or mismatched snapshot");
 if(!Number.isSafeInteger(Number(result.payment_reconciliation.tender_mismatch_count))||Number(result.payment_reconciliation.tender_mismatch_count)<0)
  fail("EXEC_SALES_PAYMENT_RECONCILIATION_INVALID","tender_mismatch_count");
 for(const key of [...moneyKeys,"transaction_count"])
  if(!Number.isSafeInteger(Number(result.totals[key]))||Number(result.totals[key])<0)
   fail("EXEC_SALES_TOTAL_INVALID",key);
 assertAggregateParity(result);
 const allowedBranches=branchIds?new Set(branchIds):null;
 for(const row of result.transactions){
  if(!row||!row.sale_id||!row.branch_id||!row.business_date||
     (allowedBranches&&!allowedBranches.has(row.branch_id))||
     row.business_date<startDate||row.business_date>endDate)
   fail("EXEC_SALES_SOURCE_SCOPE_INVALID","Source transaction is outside requested branch/date scope");
 }
 return Object.freeze(result);
}
