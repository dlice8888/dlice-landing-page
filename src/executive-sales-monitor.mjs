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
const moneyKeys=["gross_idr","discount_idr","refund_idr","net_sales_idr","matched_settlement_idr"];
const safeAmount=(value,key)=>{
 const n=Number(value);
 if(!Number.isSafeInteger(n)||n<0)fail("EXEC_SALES_RECONCILIATION_INVALID",key);
 return n;
};
const sum=(rows,key,refundKey)=>{
 return rows.reduce((total,row)=>{
  const next=total+safeAmount(refundKey?row[refundKey]:row[key],key);
  if(!Number.isSafeInteger(next))fail("EXEC_SALES_RECONCILIATION_INVALID",key+" aggregate exceeds safe integer range");
  return next;
 },0);
};
function expectedBusinessDate(paidAt,timezone,cutoff){
 const instant=new Date(paidAt);
 if(!Number.isFinite(instant.getTime()))fail("EXEC_SALES_SOURCE_TIMESTAMP_INVALID","paid_at");
 let parts;
 try{parts=new Intl.DateTimeFormat("en-GB",{timeZone:timezone,year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit",second:"2-digit",hourCycle:"h23"}).formatToParts(instant);}
 catch{fail("EXEC_SALES_SOURCE_TIMEZONE_INVALID","timezone");}
 const p=Object.fromEntries(parts.filter(x=>x.type!=="literal").map(x=>[x.type,Number(x.value)]));
 const match=typeof cutoff==="string"&&/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/.exec(cutoff);
 if(!match)fail("EXEC_SALES_SOURCE_CUTOFF_INVALID","cutoff_time");
 const [hour,minute,second=0]=cutoff.split(":").map(Number);
 const localAsUtc=Date.UTC(p.year,p.month-1,p.day,p.hour,p.minute,p.second);
 return new Date(localAsUtc-((hour*3600+minute*60+second)*1000)).toISOString().slice(0,10);
}
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
 const payment=result.payment_reconciliation,finance=result.finance_reconciliation;
 const countFields=["sale_count","tender_mismatch_count","legacy_paid_at_count"];
 for(const key of countFields)if(!Number.isSafeInteger(Number(payment[key]))||Number(payment[key])<0)
  fail("EXEC_SALES_PAYMENT_RECONCILIATION_INVALID",key);
 const financeCountFields=["sale_count","sale_without_journal_count","linked_journal_entry_count",
  "refunds_without_journal_count","sale_journal_mismatch_count","refund_journal_mismatch_count"];
 for(const key of financeCountFields)if(!Number.isSafeInteger(Number(finance[key]))||Number(finance[key])<0)
  fail("EXEC_SALES_FINANCE_RECONCILIATION_INVALID",key);
 for(const key of ["sale_journal_amount_idr","refund_journal_amount_idr"])
  if(!Number.isSafeInteger(Number(finance[key]))||Number(finance[key])<0)
   fail("EXEC_SALES_FINANCE_RECONCILIATION_INVALID",key);
 for(const key of [...moneyKeys,"transaction_count"])
  if(!Number.isSafeInteger(Number(result.totals[key]))||Number(result.totals[key])<0)
   fail("EXEC_SALES_TOTAL_INVALID",key);
 if(Number(payment.sale_count)!==Number(result.totals.transaction_count)||
    Number(finance.sale_count)!==Number(result.totals.transaction_count))
  fail("EXEC_SALES_RECONCILIATION_MISMATCH","Payment and Finance source sale counts must equal POS source transactions");
 assertAggregateParity(result);
 const reconciliationStatus=Number(payment.tender_mismatch_count)===0&&Number(payment.legacy_paid_at_count)===0&&
  Number(finance.sale_without_journal_count)===0&&Number(finance.refunds_without_journal_count)===0&&
  Number(finance.sale_journal_mismatch_count)===0&&Number(finance.refund_journal_mismatch_count)===0&&finance.status==="reconciled"
  ?"source_reconciled":"reconciliation_incomplete";
 const allowedBranches=branchIds?new Set(branchIds):null;
 for(const row of result.transactions){
  if(!row||!row.sale_id||!row.branch_id||!row.business_date)
   fail("EXEC_SALES_SOURCE_SCOPE_INVALID","Source transaction identity and business date are required");
  // Recompute from the immutable payment timestamp and the branch policy snapshot.
  // Never trust a client-supplied timezone or a stored business_date without provenance.
  const computedBusinessDate=expectedBusinessDate(row.paid_at,row.timezone,row.cutoff_time);
  const policyVersion=Number(row.business_day_policy_version);
  const legacyBackfill=row.paid_at_source==="legacy_created_at_backfill";
  // Historical paid rows may have been backfilled before a branch policy existed.
  // Keep them visible for reconciliation, but never treat them as fully proven:
  // the snapshot's legacy_paid_at_count forces reconciliation_incomplete.
  if(!Number.isSafeInteger(policyVersion)||policyVersion<0||
     (legacyBackfill&&policyVersion!==0)||(!legacyBackfill&&policyVersion<1))
   fail("EXEC_SALES_SOURCE_CUTOFF_INVALID","A valid branch cutoff policy version or explicit legacy backfill provenance is required");
  if(row.business_date!==computedBusinessDate)
   fail("EXEC_SALES_BUSINESS_DATE_MISMATCH","Stored business date differs from branch timezone/cutoff calculation");
  if((allowedBranches&&!allowedBranches.has(row.branch_id))||row.business_date<startDate||row.business_date>endDate)
   fail("EXEC_SALES_SOURCE_SCOPE_INVALID","Source transaction is outside requested branch/date scope");
 }
 return Object.freeze({...result,reconciliation_status:reconciliationStatus});
}
