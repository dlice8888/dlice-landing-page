import test from "node:test";
import assert from "node:assert/strict";
import { closeBranchMaintenanceCost } from "../../src/branch-operations-costing-integration.mjs";

const scope={tenantId:"tenant-a",branchId:"branch-a",actorId:"finance-a",workOrderId:"wo-a",idempotencyKey:"cost-close-0001"};
const makeDeps=(overrides={})=>{
 const calls=[];
 const deps={
  withTenantTransaction:async(_scope,fn)=>fn({tx:true}),
  authorize:async()=>{},
  findCostCloseByIdempotencyKey:async()=>null,
  loadWorkOrderForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"completed",approvedExternalCostIdr:5000}),
  loadInventoryIssuesForWorkOrder:async()=>[{id:"issue-a",tenantId:"tenant-a",branchId:"branch-a",reconciled:true,valuationSource:"approved_grn",receiptId:"grn-a",extendedCostIdr:12000}],
  loadApprovedProcurementReceipts:async()=>[{id:"grn-a",tenantId:"tenant-a",branchId:"branch-a",status:"approved",reconciled:true}],
  loadApprovedLabourEntries:async()=>[{id:"labour-a",tenantId:"tenant-a",branchId:"branch-a",approvalStatus:"approved",reconciled:true,costIdr:8000}],
  computeSourceRevision:async()=> "rev-a",
  persistMaintenanceCostClose:async(_tx,row)=>{calls.push(["persist",row]);return{id:"close-a"};},
  postMaintenanceFinanceJournal:async(_tx,row)=>{calls.push(["journal",row]);return{id:"journal-a"};},
  verifyPostedBalancedJournal:async(_tx,row)=>{calls.push(["verify",row]);return true;},
  appendAudit:async(_tx,row)=>calls.push(["audit",row]),
  ...overrides,
 };
 return {deps,calls};
};

test("maintenance cost is derived from reconciled inventory, GRN, HR labour and approved external costs",async()=>{
 const {deps,calls}=makeDeps();
 const result=await closeBranchMaintenanceCost(scope,deps);
 assert.deepEqual(result,{status:"closed",costCloseId:"close-a",journalId:"journal-a",totalCostIdr:25000});
 assert.equal(calls.find(x=>x[0]==="persist")[1].inventoryCostIdr,12000);
 assert.equal(calls.find(x=>x[0]==="persist")[1].labourCostIdr,8000);
 assert.equal(calls.find(x=>x[0]==="journal")[1].totalCostIdr,25000);
 assert.equal(calls.filter(x=>x[0]==="audit").length,1);
});

test("idempotent retry returns existing close without duplicate journal",async()=>{
 const {deps,calls}=makeDeps({findCostCloseByIdempotencyKey:async()=>({id:"close-old",journalId:"journal-old"})});
 const result=await closeBranchMaintenanceCost(scope,deps);
 assert.deepEqual(result,{status:"duplicate",costCloseId:"close-old",journalId:"journal-old"});
 assert.equal(calls.length,0);
});

test("rejects cross-branch sources and unvalued inventory",async()=>{
 const cross=makeDeps({loadInventoryIssuesForWorkOrder:async()=>[{tenantId:"tenant-a",branchId:"branch-b"}]});
 await assert.rejects(closeBranchMaintenanceCost(scope,cross.deps),{code:"BRANCH_COST_SCOPE_MISMATCH"});
 const unvalued=makeDeps({loadInventoryIssuesForWorkOrder:async()=>[{tenantId:"tenant-a",branchId:"branch-a",reconciled:false,valuationSource:"current_price",extendedCostIdr:12000}]});
 await assert.rejects(closeBranchMaintenanceCost(scope,unvalued.deps),{code:"BRANCH_COST_INVENTORY_UNRECONCILED"});
});

test("rejects unapproved labour, missing GRN evidence and unbalanced Finance journal",async()=>{
 const labour=makeDeps({loadApprovedLabourEntries:async()=>[{tenantId:"tenant-a",branchId:"branch-a",approvalStatus:"pending",reconciled:false,costIdr:1}]});
 await assert.rejects(closeBranchMaintenanceCost(scope,labour.deps),{code:"BRANCH_COST_LABOUR_UNAPPROVED"});
 const grn=makeDeps({loadApprovedProcurementReceipts:async()=>[]});
 await assert.rejects(closeBranchMaintenanceCost(scope,grn.deps),{code:"BRANCH_COST_GRN_EVIDENCE_MISSING"});
 const finance=makeDeps({verifyPostedBalancedJournal:async()=>false});
 await assert.rejects(closeBranchMaintenanceCost(scope,finance.deps),{code:"BRANCH_COST_FINANCE_UNRECONCILED"});
});

test("requires completed work order and safe integer IDR amounts",async()=>{
 const pending=makeDeps({loadWorkOrderForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"scheduled"})});
 await assert.rejects(closeBranchMaintenanceCost(scope,pending.deps),{code:"BRANCH_COST_WORK_ORDER_NOT_READY"});
 const invalid=makeDeps({loadWorkOrderForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"completed",approvedExternalCostIdr:1.5})});
 await assert.rejects(closeBranchMaintenanceCost(scope,invalid.deps),{code:"BRANCH_COST_AMOUNT_INVALID"});
});
