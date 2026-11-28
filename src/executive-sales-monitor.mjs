/**
 * D01-F02: Executive sales monitor application boundary.
 * All authorization, branch timezone/cutoff calculation, source aggregation,
 * Finance links, snapshot persistence and audit writes execute in one SQL RPC.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const required=(v,name)=>{if(typeof v!=="string"||!v.trim())fail("EXEC_SALES_INPUT_REQUIRED",name);return v.trim();};
const validDate=(v,name)=>{
 if(typeof v!=="string"||!/^\d{4}-\d{2}-\d{2}$/.test(v))fail("EXEC_SALES_DATE_INVALID",name);
 const d=new Date(v+"T00:00:00.000Z");
 if(Number.isNaN(d.getTime())||d.toISOString().slice(0,10)!==v)fail("EXEC_SALES_DATE_INVALID",name);
 return v;
};
const adapter=(deps,name)=>{if(typeof deps?.[name]!=="function")fail("EXEC_SALES_ADAPTER_REQUIRED",name);return deps[name];};
const periods=new Set(["day","week","month"]);
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
    !Array.isArray(result.transactions)||!result.finance_reconciliation||!result.payment_reconciliation)
  fail("EXEC_SALES_SNAPSHOT_INVALID","Server returned an incomplete or mismatched snapshot");
 if(!Number.isSafeInteger(Number(result.payment_reconciliation.tender_mismatch_count))||Number(result.payment_reconciliation.tender_mismatch_count)<0)\n  fail("EXEC_SALES_PAYMENT_RECONCILIATION_INVALID","tender_mismatch_count");\n for(const key of ["gross_idr","discount_idr","refund_idr","net_sales_idr","matched_settlement_idr","transaction_count"])
  if(!Number.isSafeInteger(Number(result.totals[key]))||Number(result.totals[key])<0)
   fail("EXEC_SALES_TOTAL_INVALID",key);
 return Object.freeze(result);
}
