import test from "node:test";
import assert from "node:assert/strict";
import { reconcileHrPayrollFinance } from "../../src/hr-payroll-finance-reconciliation.mjs";
const input={tenantId:"tenant-a",branchId:"branch-a",actorId:"finance-a",payrollRunId:"payroll-a",paymentBatchId:"batch-a",idempotencyKey:"payroll-close-0001"};
const make=(overrides={})=>({withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
 findCloseByIdempotencyKey:async()=>null,
 loadApprovedPayrollRun:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"approved",financeStatus:"posted"}),
 loadPayrollLines:async()=>[{id:"line-a",tenantId:"tenant-a",branchId:"branch-a",payrollRunId:"payroll-a",status:"approved",netPayableIdr:100000}],
 loadPostedFinanceJournal:async()=>({id:"journal-a",tenantId:"tenant-a",branchId:"branch-a",status:"posted",sourcePayrollRunId:"payroll-a",currency:"IDR"}),
 verifyBalancedPayrollJournal:async()=>true,
 loadSettledPayrollPaymentBatch:async()=>({id:"batch-a",tenantId:"tenant-a",branchId:"branch-a",payrollRunId:"payroll-a",status:"settled",
  items:[{payrollLineId:"line-a",status:"settled",amountIdr:100000}]}),
 persistPayrollReconciliation:async()=>({id:"reconciliation-a"}),appendAudit:async()=>{},...overrides});
test("payroll close reconciles approved HR lines, balanced Finance journal and settled provider batch",async()=>{
 const r=await reconcileHrPayrollFinance(input,make());assert.equal(r.status,"reconciled");assert.equal(r.netPayableIdr,100000);assert.equal(r.paidIdr,100000);
});
test("idempotent retry does not create a second reconciliation",async()=>{
 assert.deepEqual(await reconcileHrPayrollFinance(input,make({findCloseByIdempotencyKey:async()=>({id:"old"})})),{status:"duplicate",reconciliationId:"old"});
});
test("rejects unposted payroll, cross-branch journal and unsettled batch",async()=>{
 await assert.rejects(reconcileHrPayrollFinance(input,make({loadApprovedPayrollRun:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"draft",financeStatus:"pending"})})),{code:"HR_PAYROLL_RUN_NOT_POSTED"});
 await assert.rejects(reconcileHrPayrollFinance(input,make({loadPostedFinanceJournal:async()=>({tenantId:"tenant-a",branchId:"branch-b"})})),{code:"HR_PAYROLL_CLOSE_SCOPE_MISMATCH"});
 await assert.rejects(reconcileHrPayrollFinance(input,make({loadSettledPayrollPaymentBatch:async()=>({id:"batch-a",tenantId:"tenant-a",branchId:"branch-a",payrollRunId:"payroll-a",status:"processing",items:[]})})),{code:"HR_PAYROLL_PAYMENT_BATCH_NOT_SETTLED"});
});
test("rejects unbalanced Finance and payment amount mismatch",async()=>{
 await assert.rejects(reconcileHrPayrollFinance(input,make({verifyBalancedPayrollJournal:async()=>false})),{code:"HR_PAYROLL_FINANCE_UNRECONCILED"});
 await assert.rejects(reconcileHrPayrollFinance(input,make({loadSettledPayrollPaymentBatch:async()=>({id:"batch-a",tenantId:"tenant-a",branchId:"branch-a",payrollRunId:"payroll-a",status:"settled",items:[{payrollLineId:"line-a",status:"settled",amountIdr:99000}]})})),{code:"HR_PAYROLL_PAYMENT_AMOUNT_MISMATCH"});
});
test("rejects missing and duplicate payment items",async()=>{
 await assert.rejects(reconcileHrPayrollFinance(input,make({loadSettledPayrollPaymentBatch:async()=>({id:"batch-a",tenantId:"tenant-a",branchId:"branch-a",payrollRunId:"payroll-a",status:"settled",items:[]})})),{code:"HR_PAYROLL_PAYMENT_ITEMS_MISMATCH"});
 await assert.rejects(reconcileHrPayrollFinance(input,make({loadSettledPayrollPaymentBatch:async()=>({id:"batch-a",tenantId:"tenant-a",branchId:"branch-a",payrollRunId:"payroll-a",status:"settled",items:[{payrollLineId:"line-a",status:"settled",amountIdr:100000},{payrollLineId:"line-a",status:"settled",amountIdr:100000}]})})),{code:"HR_PAYROLL_PAYMENT_ITEM_INVALID"});
});
