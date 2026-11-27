/**
 * Finance budget variance and multi-branch consolidated statement builders.
 * All actuals/journals must be closed, posted and reconciled authoritative GL facts.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("FINANCE_REPORT_INPUT_REQUIRED",f);return v.trim();};

/** Compare approved branch budgets with reconciled GL actuals by account/category. */
export function calculateBranchBudgetVariance(input){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId");
 const period=req(input.period,"period");
 if(!Array.isArray(input.budgets)||!Array.isArray(input.actuals))fail("FINANCE_BUDGET_DATA_REQUIRED","Budget and GL actual rows are required");
 const budgetMap=new Map(),actualMap=new Map();
 for(const row of input.budgets){
  if(row.tenantId!==tenantId||row.branchId!==branchId||row.status!=="approved"||row.period!==period)
   fail("FINANCE_BUDGET_NOT_APPROVED","Budget rows must be approved for the same tenant, branch and period");
  const amount=Number(row.amountIdr);
  if(!Number.isSafeInteger(amount)||amount<0)fail("FINANCE_BUDGET_AMOUNT_INVALID","Budget must be non-negative integer IDR");
  budgetMap.set(row.accountCode,(budgetMap.get(row.accountCode)||0)+amount);
 }
 for(const row of input.actuals){
  if(row.tenantId!==tenantId||row.branchId!==branchId||row.period!==period||row.status!=="posted"||row.reconciliationStatus!=="RECONCILED")
   fail("FINANCE_BUDGET_ACTUAL_UNRECONCILED","Actuals must be posted and reconciled in the same period");
  const amount=Number(row.amountIdr);
  if(!Number.isSafeInteger(amount)||amount<0)fail("FINANCE_BUDGET_ACTUAL_INVALID","Actual must be non-negative integer IDR");
  actualMap.set(row.accountCode,(actualMap.get(row.accountCode)||0)+amount);
 }
 const codes=new Set([...budgetMap.keys(),...actualMap.keys()]);
 const rows=[...codes].sort().map(accountCode=>{
  const budget=budgetMap.get(accountCode)||0,actual=actualMap.get(accountCode)||0;
  return Object.freeze({accountCode,budgetIdr:budget,actualIdr:actual,varianceIdr:actual-budget,
   variancePct:budget===0?(actual===0?0:null):Number(((actual-budget)/budget*100).toFixed(2))});
 });
 return Object.freeze({tenantId,branchId,period,rows:Object.freeze(rows),
  totalBudgetIdr:[...budgetMap.values()].reduce((a,b)=>a+b,0),
  totalActualIdr:[...actualMap.values()].reduce((a,b)=>a+b,0),
  totalVarianceIdr:[...actualMap.values()].reduce((a,b)=>a+b,0)-[...budgetMap.values()].reduce((a,b)=>a+b,0)});
}

/** Consolidate closed branch trial balances and eliminate balanced intercompany journal groups. */
export function buildConsolidatedFinancialStatement(input){
 const tenantId=req(input?.tenantId,"tenantId"),period=req(input?.period,"period");
 const branches=input.branches,entries=input.entries;
 if(!Array.isArray(branches)||!branches.length||!Array.isArray(entries))fail("FINANCE_CONSOLIDATION_INPUT_REQUIRED","Branch close records and GL entries are required");
 const branchIds=new Set();
 for(const branch of branches){
  if(branch.tenantId!==tenantId||branch.status!=="closed"||branch.period!==period||branchIds.has(branch.branchId))
   fail("FINANCE_BRANCH_CLOSE_INCOMPLETE","Every branch must be uniquely closed for the same tenant and period");
  branchIds.add(branch.branchId);
 }
 const journalTotals=new Map(),grouped=new Map();
 for(const entry of entries){
  if(entry.tenantId!==tenantId||!branchIds.has(entry.branchId)||entry.period!==period||entry.status!=="posted"||entry.reconciliationStatus!=="RECONCILED")
   fail("FINANCE_CONSOLIDATION_SOURCE_INVALID","Every entry must be posted/reconciled and belong to a closed branch");
  const debit=Number(entry.debitIdr),credit=Number(entry.creditIdr);
  if(!Number.isSafeInteger(debit)||debit<0||!Number.isSafeInteger(credit)||credit<0||debit===credit)
   fail("FINANCE_JOURNAL_LINE_INVALID","Journal lines must have one positive debit or credit side");
  const journal=journalTotals.get(entry.journalId)||{debit:0,credit:0};
  journal.debit+=debit;journal.credit+=credit;journalTotals.set(entry.journalId,journal);
  if(entry.eliminationGroup){
   const rows=grouped.get(entry.eliminationGroup)||[];rows.push(entry);grouped.set(entry.eliminationGroup,rows);
  }
 }
 for(const [journalId,total] of journalTotals)if(total.debit!==total.credit)
  fail("FINANCE_JOURNAL_UNBALANCED",`Journal ${journalId} is not balanced`);
 const eliminated=new Set();
 for(const [groupId,rows] of grouped){
  const branchSet=new Set(rows.map(x=>x.branchId));
  const debit=rows.reduce((s,x)=>s+x.debitIdr,0),credit=rows.reduce((s,x)=>s+x.creditIdr,0);
  if(branchSet.size<2||debit!==credit)fail("FINANCE_INTERCOMPANY_ELIMINATION_INVALID",`Intercompany group ${groupId} is not balanced across branches`);
  for(const row of rows)eliminated.add(row.id);
 }
 const accounts=new Map();
 for(const entry of entries){
  if(eliminated.has(entry.id))continue;
  const row=accounts.get(entry.accountCode)||{accountCode:entry.accountCode,debitIdr:0,creditIdr:0};
  row.debitIdr+=entry.debitIdr;row.creditIdr+=entry.creditIdr;accounts.set(entry.accountCode,row);
 }
 const totals=[...accounts.values()].reduce((s,r)=>({debit:s.debit+r.debitIdr,credit:s.credit+r.creditIdr}),
  {debit:0,credit:0});
 if(totals.debit!==totals.credit)fail("FINANCE_CONSOLIDATED_STATEMENT_UNBALANCED","Consolidated trial balance must balance after eliminations");
 return Object.freeze({tenantId,period,branchCount:branches.length,eliminatedEntryCount:eliminated.size,
  accounts:Object.freeze([...accounts.values()].map(Object.freeze)),totalDebitIdr:totals.debit,totalCreditIdr:totals.credit,
  balanced:true});
}

/** Publish consolidated statement from server-loaded closed branch GL and approved elimination policy. */
export async function publishConsolidatedFinancialStatement(input,deps){
 const s={tenantId:req(input?.tenantId,"tenantId"),actorId:req(input?.actorId,"actorId"),
  idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),action:"finance.consolidated_statement.publish"};
 return deps.withTenantTransaction(s,async tx=>{
  await deps.authorize(tx,s);
  const prior=await deps.findConsolidatedStatementByIdempotencyKey(tx,s);
  if(prior)return Object.freeze({status:"duplicate",statementId:prior.id});
  const branches=await deps.loadClosedBranchPeriods(tx,{...s,period:req(input.period,"period")});
  const entries=await deps.loadReconciledBranchGlEntries(tx,{...s,period:input.period});
  const statement=buildConsolidatedFinancialStatement({tenantId:s.tenantId,period:input.period,branches,entries});
  const saved=await deps.persistConsolidatedStatement(tx,{...s,...statement,sourceRevision:req(input.sourceRevision,"sourceRevision")});
  if(!saved?.id)fail("FINANCE_STATEMENT_PERSIST_FAILED","Consolidated statement was not persisted");
  await deps.appendAudit(tx,{...s,action:"finance.consolidated_statement.published",entityType:"finance_consolidated_statement",
   entityId:saved.id,metadata:{period:input.period,branchCount:statement.branchCount,eliminatedEntryCount:statement.eliminatedEntryCount}});
  return Object.freeze({status:"published",statementId:saved.id,statement});
 });
}
