import test from "node:test";
import assert from "node:assert/strict";
import {getExecutiveSalesMonitor} from "../../src/executive-sales-monitor.mjs";
import {claimApproval,decideApproval} from "../../src/executive-approval-center.mjs";

const salesDeps=(overrides={})=>({
 withTenantTransaction:(_scope,fn)=>fn({}),
 authorizeExecutiveRead:async()=>{},
 resolveAuthorizedBranches:async()=>[{id:"b1",tenantId:"t1",timezone:"Asia/Jakarta"}],
 loadPaidSales:async()=>[
  {id:"s1",tenantId:"t1",branchId:"b1",paymentStatus:"paid",paidAt:"2026-11-27T17:30:00.000Z",subtotalIdr:10000,discountIdr:1000,totalIdr:9000,transactionCode:"DLC-1"},
  {id:"s2",tenantId:"t1",branchId:"b1",paymentStatus:"pending",paidAt:null,subtotalIdr:5000,discountIdr:0,totalIdr:5000}
 ],
 loadProcessedRefunds:async()=>[{id:"r1",tenantId:"t1",branchId:"b1",saleId:"s1",status:"processed",amountIdr:2000}],
 loadSettlementFacts:async()=>[{tenantId:"t1",branchId:"b1",saleId:"s1",status:"matched",matchedAmountIdr:9000}],
 appendAudit:async()=>{},...overrides
});
test("sales monitor uses branch-local paid date and processed refunds",async()=>{
 const result=await getExecutiveSalesMonitor({actorId:"u1",tenantId:"t1",businessDate:"2026-11-28",period:"day"},salesDeps());
 assert.equal(result.grossSalesIdr,10000);
 assert.equal(result.discountIdr,1000);
 assert.equal(result.refundIdr,2000);
 assert.equal(result.netSalesIdr,7000);
 assert.equal(result.paidTransactionCount,1);
});
test("sales monitor excludes pending payment and rejects duplicate source rows",async()=>{
 const d=salesDeps({loadPaidSales:async()=>[{id:"x",tenantId:"t1",branchId:"b1",paymentStatus:"paid",paidAt:"2026-11-28T01:00:00Z",subtotalIdr:1,discountIdr:0,totalIdr:1},{id:"x",tenantId:"t1",branchId:"b1",paymentStatus:"paid",paidAt:"2026-11-28T01:00:00Z",subtotalIdr:1,discountIdr:0,totalIdr:1}]});
 await assert.rejects(()=>getExecutiveSalesMonitor({actorId:"u1",tenantId:"t1",businessDate:"2026-11-28"},d),{code:"EXEC_SALES_DUPLICATE_SALE"});
});
test("sales monitor rejects cross-tenant source rows",async()=>{
 const d=salesDeps({loadPaidSales:async()=>[{id:"x",tenantId:"t2",branchId:"b1",paymentStatus:"paid",paidAt:"2026-11-28T01:00:00Z",subtotalIdr:1,discountIdr:0,totalIdr:1}]});
 await assert.rejects(()=>getExecutiveSalesMonitor({actorId:"u1",tenantId:"t1",businessDate:"2026-11-28"},d),{code:"EXEC_SALES_SOURCE_SCOPE_MISMATCH"});
});
test("approval claim rejects stale optimistic version",async()=>{
 const deps={withTenantTransaction:(_s,fn)=>fn({}),resolveApprovalScope:async()=>({branchIds:["b1"]}),authorizeApprovalClaim:async()=>{},lockApprovalInboxItem:async()=>({tenantId:"t1",branchId:"b1",version:3,status:"pending"}),persistApprovalClaim:async()=>{throw Error("must not persist");},appendApprovalAudit:async()=>{}};
 await assert.rejects(()=>claimApproval({actorId:"u1",tenantId:"t1",approvalId:"a1",expectedVersion:2,idempotencyKey:"claim-12345678"},deps),{code:"EXEC_APPROVAL_STALE_VERSION"});
});
test("approval decision rejects self-approval",async()=>{
 const deps={withTenantTransaction:(_s,fn)=>fn({}),resolveApprovalScope:async()=>({branchIds:["b1"]}),lockApprovalInboxItem:async()=>({tenantId:"t1",branchId:"b1",version:4,status:"claimed",claimedBy:"u1",createdBy:"u1",sourceVersion:1}),resolveApprovalPolicy:async()=>({allowed:true,approverId:"u1",forbidSelfApproval:true}),assertSourceEntityVersion:async()=>{},persistApprovalDecision:async()=>{throw Error("must not persist");},applySourceEntityDecisionOnce:async()=>{},appendApprovalAudit:async()=>{}};
 await assert.rejects(()=>decideApproval({actorId:"u1",tenantId:"t1",approvalId:"a1",expectedVersion:4,idempotencyKey:"decision-123456",decision:"approved",reason:"Reviewed supporting documents"},deps),{code:"EXEC_APPROVAL_SELF_APPROVAL_DENIED"});
});
