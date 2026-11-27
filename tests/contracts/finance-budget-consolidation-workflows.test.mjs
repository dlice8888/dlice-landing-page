import test from "node:test";
import assert from "node:assert/strict";
import {calculateBranchBudgetVariance,buildConsolidatedFinancialStatement,publishConsolidatedFinancialStatement}
 from "../../src/finance-budget-consolidation-workflows.mjs";

test("branch budget variance compares approved budget with reconciled posted GL actuals",()=>{
 const result=calculateBranchBudgetVariance({tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",
  budgets:[
   {tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",status:"approved",accountCode:"food_cost",amountIdr:500000},
   {tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",status:"approved",accountCode:"labor",amountIdr:200000},
  ],
  actuals:[
   {tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",status:"posted",reconciliationStatus:"RECONCILED",accountCode:"food_cost",amountIdr:550000},
   {tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",status:"posted",reconciliationStatus:"RECONCILED",accountCode:"labor",amountIdr:180000},
  ]});
 assert.equal(result.totalBudgetIdr,700000);assert.equal(result.totalActualIdr,730000);
 assert.equal(result.totalVarianceIdr,30000);assert.equal(result.rows[0].varianceIdr,50000);
});
test("budget variance rejects unapproved budgets and unreconciled actuals",()=>{
 assert.throws(()=>calculateBranchBudgetVariance({tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",
  budgets:[{tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",status:"draft",accountCode:"food",amountIdr:100}],
  actuals:[]}),{code:"FINANCE_BUDGET_NOT_APPROVED"});
 assert.throws(()=>calculateBranchBudgetVariance({tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",budgets:[],
  actuals:[{tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",status:"posted",reconciliationStatus:"PENDING",accountCode:"food",amountIdr:100}]}),
  {code:"FINANCE_BUDGET_ACTUAL_UNRECONCILED"});
});
const branches=[{tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",status:"closed"},
 {tenantId:"tenant-a",branchId:"branch-b",period:"2026-11",status:"closed"}];
const entries=[
 {id:"a1",journalId:"j-a1",tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",status:"posted",reconciliationStatus:"RECONCILED",accountCode:"cash",debitIdr:100,creditIdr:0},
 {id:"a2",journalId:"j-a1",tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",status:"posted",reconciliationStatus:"RECONCILED",accountCode:"sales",debitIdr:0,creditIdr:100},
 {id:"b1",journalId:"j-b1",tenantId:"tenant-a",branchId:"branch-b",period:"2026-11",status:"posted",reconciliationStatus:"RECONCILED",accountCode:"expense",debitIdr:20,creditIdr:0},
 {id:"b2",journalId:"j-b1",tenantId:"tenant-a",branchId:"branch-b",period:"2026-11",status:"posted",reconciliationStatus:"RECONCILED",accountCode:"cash",debitIdr:0,creditIdr:20},
 {id:"a3",journalId:"j-a2",tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",status:"posted",reconciliationStatus:"RECONCILED",accountCode:"due_from",debitIdr:50,creditIdr:0,eliminationGroup:"ic-1"},
 {id:"a4",journalId:"j-a2",tenantId:"tenant-a",branchId:"branch-a",period:"2026-11",status:"posted",reconciliationStatus:"RECONCILED",accountCode:"intercompany_revenue",debitIdr:0,creditIdr:50},
 {id:"b3",journalId:"j-b2",tenantId:"tenant-a",branchId:"branch-b",period:"2026-11",status:"posted",reconciliationStatus:"RECONCILED",accountCode:"intercompany_expense",debitIdr:50,creditIdr:0},
 {id:"b4",journalId:"j-b2",tenantId:"tenant-a",branchId:"branch-b",period:"2026-11",status:"posted",reconciliationStatus:"RECONCILED",accountCode:"due_to",debitIdr:0,creditIdr:50,eliminationGroup:"ic-1"},
];

test("consolidated statement validates branch closes, balances journals and eliminates intercompany balances",()=>{
 const result=buildConsolidatedFinancialStatement({tenantId:"tenant-a",period:"2026-11",branches,entries});
 assert.equal(result.branchCount,2);assert.equal(result.eliminatedEntryCount,2);
 assert.equal(result.totalDebitIdr,170);assert.equal(result.totalCreditIdr,170);assert.equal(result.balanced,true);
 assert.equal(result.accounts.some(x=>x.accountCode==="due_from"),false);
});
test("consolidated statement rejects incomplete branch close and unbalanced journal",()=>{
 assert.throws(()=>buildConsolidatedFinancialStatement({tenantId:"tenant-a",period:"2026-11",
  branches:[{...branches[0],status:"open"}],entries:[]}),{code:"FINANCE_BRANCH_CLOSE_INCOMPLETE"});
 const broken=entries.map(x=>x.id==="a2"?{...x,creditIdr:99}:x);
 assert.throws(()=>buildConsolidatedFinancialStatement({tenantId:"tenant-a",period:"2026-11",branches,entries:broken}),
  {code:"FINANCE_JOURNAL_UNBALANCED"});
});
test("consolidated statement rejects unbalanced intercompany elimination groups",()=>{
 const broken=entries.map(x=>x.id==="b4"?{...x,eliminationGroup:"ic-2"}:x);
 assert.throws(()=>buildConsolidatedFinancialStatement({tenantId:"tenant-a",period:"2026-11",branches,entries:broken}),
  {code:"FINANCE_INTERCOMPANY_ELIMINATION_INVALID"});
});
test("consolidated statement publication loads closed periods and reconciled GL",async()=>{
 const deps={
  withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
  findConsolidatedStatementByIdempotencyKey:async()=>null,
  loadClosedBranchPeriods:async()=>branches,loadReconciledBranchGlEntries:async()=>entries,
  persistConsolidatedStatement:async(_tx,row)=>{assert.equal(row.balanced,true);return{id:"statement-a"};},
  appendAudit:async()=>{},
 };
 const result=await publishConsolidatedFinancialStatement({tenantId:"tenant-a",actorId:"cfo-a",idempotencyKey:"fin-close-1",
  period:"2026-11",sourceRevision:"gl-close-v1"},deps);
 assert.equal(result.status,"published");assert.equal(result.statementId,"statement-a");
});
