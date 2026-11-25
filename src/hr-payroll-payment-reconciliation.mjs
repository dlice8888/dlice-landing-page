/** Payroll payment settlement reconciliation; matching is not payment execution. */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function reconcilePayrollPayment({payrollRun,paymentBatch,settlements,financeBatch,now=Date.now()}) {
 if(!payrollRun?.id||payrollRun.status!=="approved"||!Number.isSafeInteger(payrollRun.netAmountIdr))fail("APPROVED_PAYROLL_REQUIRED","Approved payroll run with net amount is required");
 if(!paymentBatch?.id||paymentBatch.payrollRunId!==payrollRun.id||paymentBatch.status!=="executed")fail("PAYROLL_PAYMENT_NOT_EXECUTED","Payment batch must be executed");
 if(!Array.isArray(settlements)||!settlements.length)fail("PAYROLL_SETTLEMENTS_REQUIRED","Provider settlement evidence is required");
 if(!financeBatch||financeBatch.sourceId!==payrollRun.id||financeBatch.status!=="posted"||financeBatch.reconciled!==true)fail("PAYROLL_FINANCE_POSTING_NOT_RECONCILED","Finance journal batch must be posted and source reconciled");
 const refs=new Set();let total=0;for(const s of settlements){if(!s.providerReference||refs.has(s.providerReference)||s.status!=="settled"||s.paymentBatchId!==paymentBatch.id||!Number.isSafeInteger(s.amountIdr)||s.amountIdr<=0)fail("PAYROLL_SETTLEMENT_INVALID","Settlement must be final, unique and linked");refs.add(s.providerReference);total+=s.amountIdr;}
 if(total!==payrollRun.netAmountIdr)fail("PAYROLL_PAYMENT_AMOUNT_MISMATCH","Settlements must equal payroll net pay");
 if(paymentBatch.executedAt&&Date.parse(paymentBatch.executedAt)>now)fail("PAYROLL_PAYMENT_TIME_INVALID","Payment timestamp is in the future");
 return Object.freeze({payrollRunId:payrollRun.id,paymentBatchId:paymentBatch.id,settlementCount:settlements.length,settledAmountIdr:total,status:"reconciled"});
}
