import test from "node:test";
import assert from "node:assert/strict";
import {
 calculateProductionUsageVariance,assertApprovedRecipeVersionParity,evaluateBranchOpeningReadiness,
 reconcileProviderSettlement,publishProductionUsageVariance,openReadyBranch,publishProviderSettlementReconciliation,
} from "../../src/blocked-acceptance-remediation-workflows.mjs";

const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"manager-a",idempotencyKey:"blocked-flow-0001"};

test("production variance reconciles theoretical recipe usage to actual posted stock movements",()=>{
 const result=calculateProductionUsageVariance({tenantId:"tenant-a",branchId:"branch-a",
  theoretical:[{tenantId:"tenant-a",branchId:"branch-a",recipeStatus:"approved",itemId:"flour",quantity:10,unitCostIdr:1000}],
  actual:[{tenantId:"tenant-a",branchId:"branch-a",status:"posted",reconciliationStatus:"RECONCILED",itemId:"flour",quantity:12,unitCostIdr:1000}]});
 assert.equal(result.totalVarianceCostIdr,2000);assert.equal(result.rows[0].varianceQuantity,2);
});
test("production variance rejects unreconciled actuals",()=>{
 assert.throws(()=>calculateProductionUsageVariance({tenantId:"tenant-a",branchId:"branch-a",
  theoretical:[{tenantId:"tenant-a",branchId:"branch-a",recipeStatus:"approved",itemId:"flour",quantity:10,unitCostIdr:1000}],
  actual:[{tenantId:"tenant-a",branchId:"branch-a",status:"posted",reconciliationStatus:"PENDING",itemId:"flour",quantity:12,unitCostIdr:1000}]}),
  {code:"PRODUCTION_VARIANCE_ACTUAL_UNRECONCILED"});
});
test("POS and production must use the same approved recipe version and snapshot hash",()=>{
 const sale={tenantId:"tenant-a",branchId:"branch-a",productId:"meal-a",recipeStatus:"approved",recipeVersion:3,
  recipeSnapshotHash:"sha256:abc12345",soldAt:"2026-11-27T10:00:00Z",recipeEffectiveFrom:"2026-11-01T00:00:00Z"};
 const batch={tenantId:"tenant-a",branchId:"branch-a",productId:"meal-a",recipeStatus:"approved",recipeVersion:3,
  recipeSnapshotHash:"sha256:abc12345"};
 assert.equal(assertApprovedRecipeVersionParity({tenantId:"tenant-a",saleLine:sale,productionBatch:batch}).status,"matched");
 assert.throws(()=>assertApprovedRecipeVersionParity({tenantId:"tenant-a",saleLine:sale,
  productionBatch:{...batch,recipeVersion:2}}),{code:"RECIPE_VERSION_PARITY_FAILED"});
});
test("branch opening readiness requires every mandatory approved and verified evidence item",()=>{
 const checks=[{key:"cash",mandatory:true,status:"approved",evidenceReference:"private://cash",evidenceVerified:true},
  {key:"kitchen",mandatory:true,status:"pending",evidenceReference:null,evidenceVerified:false},
  {key:"staffing",mandatory:false,status:"pending"}];
 const result=evaluateBranchOpeningReadiness({branchStatus:"closed",checks});
 assert.equal(result.ready,false);assert.deepEqual(result.missing,["kitchen"]);
 const ready=evaluateBranchOpeningReadiness({branchStatus:"closed",checks:[checks[0],{key:"kitchen",mandatory:true,status:"approved",
  evidenceReference:"private://kitchen",evidenceVerified:true}]});
 assert.equal(ready.nextOperatingStatus,"open");
});
test("provider settlement reconciles approved fee schedule, net payout and matched bank statement",()=>{
 const result=reconcileProviderSettlement({tenantId:"tenant-a",branchId:"branch-a",
  settlement:{tenantId:"tenant-a",branchId:"branch-a",provider:"provider-a",status:"settled",reconciliationStatus:"RECONCILED",
   grossIdr:100000,feeIdr:2500,netIdr:97500},
  feeSchedule:{tenantId:"tenant-a",branchId:"branch-a",status:"approved",provider:"provider-a",currency:"IDR",feeBasisPoints:250,fixedFeeIdr:0,toleranceIdr:100},
  bank:{tenantId:"tenant-a",branchId:"branch-a",status:"matched",reconciliationStatus:"RECONCILED",amountIdr:97500}});
 assert.equal(result.status,"matched");assert.equal(result.expectedFeeIdr,2500);
});
test("provider settlement reports fee variance and rejects unapproved fee schedule",()=>{
 const facts={tenantId:"tenant-a",branchId:"branch-a",
  settlement:{tenantId:"tenant-a",branchId:"branch-a",provider:"provider-a",status:"settled",reconciliationStatus:"RECONCILED",
   grossIdr:100000,feeIdr:3000,netIdr:97000},
  feeSchedule:{status:"approved",provider:"provider-a",currency:"IDR",feeBasisPoints:250,fixedFeeIdr:0,toleranceIdr:100},
  bank:{tenantId:"tenant-a",branchId:"branch-a",status:"matched",reconciliationStatus:"RECONCILED",amountIdr:97000}};
 assert.equal(reconcileProviderSettlement(facts).status,"variance");
 assert.throws(()=>reconcileProviderSettlement({...facts,feeSchedule:{...facts.feeSchedule,status:"draft"}}),
  {code:"SETTLEMENT_FEE_SCHEDULE_NOT_APPROVED"});
});
test("opening branch changes operating status only after authoritative readiness and audit",async()=>{
 const deps={
  withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
  loadBranchForOpeningUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",operatingStatus:"closed"}),
  loadAuthoritativeOpeningChecks:async()=>[{key:"cash",mandatory:true,status:"approved",evidenceReference:"private://cash",evidenceVerified:true}],
  transitionBranchOperatingStatus:async()=>({id:"event-a",operatingStatus:"open"}),appendAudit:async()=>{},
 };
 const result=await openReadyBranch(base,deps);
 assert.deepEqual(result,{status:"open",branchId:"branch-a"});
});
test("provider settlement reconciliation persists authoritative variance and audit",async()=>{
 const deps={
  withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
  findProviderSettlementReconciliationByIdempotencyKey:async()=>null,
  loadProviderSettlementReconciliationFacts:async()=>({tenantId:"tenant-a",branchId:"branch-a",
   settlement:{tenantId:"tenant-a",branchId:"branch-a",provider:"provider-a",status:"settled",reconciliationStatus:"RECONCILED",
    grossIdr:100000,feeIdr:2500,netIdr:97500},
   feeSchedule:{status:"approved",provider:"provider-a",currency:"IDR",feeBasisPoints:250,fixedFeeIdr:0,toleranceIdr:100},
   bankStatement:{tenantId:"tenant-a",branchId:"branch-a",status:"matched",reconciliationStatus:"RECONCILED",amountIdr:97500}}),
  persistProviderSettlementReconciliation:async()=>({id:"reconciliation-a"}),appendAudit:async()=>{},
 };
 const result=await publishProviderSettlementReconciliation({...base,settlementId:"settlement-a"},deps);
 assert.equal(result.status,"matched");assert.equal(result.reconciliationId,"reconciliation-a");
});
