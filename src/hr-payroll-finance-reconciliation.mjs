/**
 * HR Payroll -> Finance -> payout reconciliation close.
 * No beneficiary PII or provider secrets are accepted or returned here.
 * All persistence adapters must share the supplied tenant transaction.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const required=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("HR_PAYROLL_CLOSE_INPUT_REQUIRED",f);return v.trim();};
const adapter=(d,n)=>{if(typeof d?.[n]!=="function")fail("HR_PAYROLL_CLOSE_ADAPTER_REQUIRED",n);return d[n];};
const money=(v,f)=>{if(!Number.isSafeInteger(v)||v<0)fail("HR_PAYROLL_CLOSE_AMOUNT_INVALID",f);return v;};
const sum=(rows,pick,field)=>rows.reduce((a,r)=>{const n=a+money(pick(r),field);if(!Number.isSafeInteger(n))fail("HR_PAYROLL_CLOSE_OVERFLOW",field);return n;},0);
const scoped=(r,s,f)=>{if(!r||r.tenantId!==s.tenantId||r.branchId!==s.branchId)fail("HR_PAYROLL_CLOSE_SCOPE_MISMATCH",f);};

/** Required tx adapters: authorize, findCloseByIdempotencyKey, loadApprovedPayrollRun,
 * loadPayrollLines, loadPostedFinanceJournal, verifyBalancedPayrollJournal,
 * loadSettledPayrollPaymentBatch, persistPayrollReconciliation, appendAudit.
 */
export async function reconcileHrPayrollFinance(input,deps){
 const scope=Object.freeze({tenantId:required(input?.tenantId,"tenantId"),branchId:required(input?.branchId,"branchId"),
  actorId:required(input?.actorId,"actorId"),payrollRunId:required(input?.payrollRunId,"payrollRunId"),
  paymentBatchId:required(input?.paymentBatchId,"paymentBatchId"),idempotencyKey:required(input?.idempotencyKey,"idempotencyKey"),
  action:"hr.payroll.finance.reconcile"});
 return adapter(deps,"withTenantTransaction")(scope,async(tx)=>{
  if(!tx)fail("HR_PAYROLL_CLOSE_TRANSACTION_REQUIRED","A database transaction is required");
  await adapter(deps,"authorize")(tx,scope);
  const prior=await adapter(deps,"findCloseByIdempotencyKey")(tx,scope);
  if(prior)return Object.freeze({status:"duplicate",reconciliationId:prior.id});
  const run=await adapter(deps,"loadApprovedPayrollRun")(tx,scope);scoped(run,scope,"payrollRun");
  if(run.status!=="approved"||run.financeStatus!=="posted")fail("HR_PAYROLL_RUN_NOT_POSTED","Payroll run must be approved and posted to Finance");
  const lines=await adapter(deps,"loadPayrollLines")(tx,scope);
  if(!Array.isArray(lines)||lines.length===0)fail("HR_PAYROLL_LINES_MISSING","Payroll run requires payroll lines");
  const lineIds=new Set();
  for(const line of lines){
   scoped(line,scope,"payrollLine");
   if(line.payrollRunId!==scope.payrollRunId||line.status!=="approved")fail("HR_PAYROLL_LINE_NOT_APPROVED","Every payroll line must be approved and belong to the run");
   if(lineIds.has(line.id))fail("HR_PAYROLL_DUPLICATE_LINE","Duplicate payroll line");lineIds.add(line.id);
  }
  const netPayableIdr=sum(lines,line=>line.netPayableIdr,"payrollLine.netPayableIdr");
  const journal=await adapter(deps,"loadPostedFinanceJournal")(tx,scope);
  scoped(journal,scope,"financeJournal");
  if(journal.status!=="posted"||journal.sourcePayrollRunId!==scope.payrollRunId||journal.currency!=="IDR")
   fail("HR_PAYROLL_FINANCE_JOURNAL_INVALID","Finance journal must be posted for this payroll run in IDR");
  if(await adapter(deps,"verifyBalancedPayrollJournal")(tx,{...scope,journalId:journal.id,expectedAmountIdr:netPayableIdr})!==true)
   fail("HR_PAYROLL_FINANCE_UNRECONCILED","Finance journal is not independently balanced to payroll payable");
  const batch=await adapter(deps,"loadSettledPayrollPaymentBatch")(tx,scope);
  scoped(batch,scope,"paymentBatch");
  if(batch.id!==scope.paymentBatchId||batch.status!=="settled"||batch.payrollRunId!==scope.payrollRunId)
   fail("HR_PAYROLL_PAYMENT_BATCH_NOT_SETTLED","Payment batch must be settled for this payroll run");
  const items=batch.items;
  if(!Array.isArray(items))fail("HR_PAYROLL_PAYMENT_ITEMS_MISMATCH","Every payroll line needs one settled payment item");
  const paidByLine=new Map();
  for(const item of items){
   if(item.status!=="settled"||!lineIds.has(item.payrollLineId)||paidByLine.has(item.payrollLineId))
    fail("HR_PAYROLL_PAYMENT_ITEM_INVALID","Payment items must be unique, settled and mapped to payroll lines");
   money(item.amountIdr,"paymentItem.amountIdr");paidByLine.set(item.payrollLineId,item.amountIdr);
  }
  if(items.length!==lines.length)fail("HR_PAYROLL_PAYMENT_ITEMS_MISMATCH","Every payroll line needs one settled payment item");
  for(const line of lines)if(paidByLine.get(line.id)!==line.netPayableIdr)
   fail("HR_PAYROLL_PAYMENT_AMOUNT_MISMATCH","Settled payment must equal approved net payable per line");
  const paidIdr=sum(items,item=>item.amountIdr,"paymentItem.amountIdr");
  if(paidIdr!==netPayableIdr)fail("HR_PAYROLL_PAYMENT_TOTAL_MISMATCH","Settled batch total differs from payroll net payable");
  const result=await adapter(deps,"persistPayrollReconciliation")(tx,{...scope,journalId:journal.id,
   netPayableIdr,paidIdr,payrollLineCount:lines.length,currency:"IDR"});
  if(!result?.id)fail("HR_PAYROLL_RECONCILIATION_PERSIST_FAILED","Payroll reconciliation was not persisted");
  await adapter(deps,"appendAudit")(tx,{...scope,action:"hr.payroll.finance.reconciled",
   entityType:"hr_payroll_reconciliations",entityId:result.id,metadata:{journalId:journal.id,paymentBatchId:batch.id,
    netPayableIdr,paidIdr,payrollLineCount:lines.length}});
  return Object.freeze({status:"reconciled",reconciliationId:result.id,journalId:journal.id,
   paymentBatchId:batch.id,netPayableIdr,paidIdr,payrollLineCount:lines.length});
 });
}
