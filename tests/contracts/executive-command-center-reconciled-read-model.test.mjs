import test from "node:test";
import assert from "node:assert/strict";
import { buildExecutiveCommandCenterReadModel } from "../../src/executive-command-center-reconciled-read-model.mjs";
const asOf="2026-11-28T10:00:00.000Z";
const sources=()=>Object.fromEntries(["pos","finance","inventory","delivery","hr","kds"].map(name=>[name,{status:"reconciled",revision:name+"-rev",asOf}]));
const fact=(branchId,overrides={})=>({tenantId:"tenant-a",branchId,sources:sources(),netSalesIdr:100000,foodCostIdr:30000,
 wasteIdr:2000,openOrders:2,deliveryBreaches:1,stockoutCount:0,kdsBacklog:1,labourCoveragePct:95,cashVarianceIdr:0,...overrides});
const make=(branches, facts, overrides={})=>({withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorizeGroupRead:async()=>{},
 loadActiveBranches:async()=>branches,loadReconciledBranchCommandFacts:async()=>facts,
 persistReadModelSnapshot:async()=>({id:"ecc-snapshot-a"}),appendAudit:async()=>{},...overrides});
const input={tenantId:"tenant-a",actorId:"owner-a",asOf,expectedBranchCount:2};
test("aggregates only reconciled fresh source facts and reports scale coverage",async()=>{
 const r=await buildExecutiveCommandCenterReadModel(input,make([{tenantId:"tenant-a",id:"b1"},{tenantId:"tenant-a",id:"b2"}],[fact("b1"),fact("b2")]));
 assert.equal(r.status,"complete");assert.equal(r.totals.netSalesIdr,200000);assert.equal(r.reconciledBranchCount,2);assert.equal(r.scaleCoveragePct,100);
});
test("missing or stale sources yield partial coverage, never fabricated group totals",async()=>{
 const stale=fact("b2");stale.sources.finance.asOf="2026-11-28T08:00:00.000Z";
 const r=await buildExecutiveCommandCenterReadModel(input,make([{tenantId:"tenant-a",id:"b1"},{tenantId:"tenant-a",id:"b2"}],[fact("b1"),stale]));
 assert.equal(r.status,"partial");assert.equal(r.reconciledBranchCount,1);assert.equal(r.totals.netSalesIdr,100000);assert.equal(r.sourceGaps.length,1);
});
test("150-branch target stays partial until all active branches and target scale are covered",async()=>{
 const branches=[{tenantId:"tenant-a",id:"b1"}];
 const r=await buildExecutiveCommandCenterReadModel({...input,expectedBranchCount:150},make(branches,[fact("b1")]));
 assert.equal(r.status,"partial");assert.equal(r.scaleCoveragePct,0.67);
});
test("rejects cross-tenant branches, facts and duplicate branch rows",async()=>{
 await assert.rejects(buildExecutiveCommandCenterReadModel(input,make([{tenantId:"tenant-b",id:"b1"}],[])),{code:"ECC_BRANCH_SCOPE_MISMATCH"});
 await assert.rejects(buildExecutiveCommandCenterReadModel(input,make([{tenantId:"tenant-a",id:"b1"}],[{...fact("b1"),tenantId:"tenant-b"}])),{code:"ECC_FACT_SCOPE_MISMATCH"});
 await assert.rejects(buildExecutiveCommandCenterReadModel(input,make([{tenantId:"tenant-a",id:"b1"}],[fact("b1"),fact("b1")])),{code:"ECC_DUPLICATE_BRANCH_FACT"});
});
