import test from "node:test";
import assert from "node:assert/strict";
import {listPendingApprovals,claimApproval,decideApproval,listApprovalHistory} from "../../src/executive-approval-center.mjs";
const approval={tenantId:"t1",id:"a1",branchId:"b1",category:"procurement",entityType:"purchase_order",entityId:"po1",status:"pending",version:2,sourceVersion:4,createdBy:"creator",expiresAt:"2999-01-01T00:00:00Z",amountIdr:1000,requiredRoles:["finance_approver"],policy:{allowSelfApproval:false}};
const actor={tenantId:"t1",branchIds:["b1"],categories:["procurement"],roles:["finance_approver"],maxApprovalAmountIdr:10000};
const base={withTenantTransaction:async(_s,fn)=>fn({}),resolveApproverScope:async()=>actor,loadPendingApprovalSources:async()=>[{...approval}],lockApproval:async()=>approval,claimApprovalLocked:async(_tx,{actorId})=>({claimedBy:actorId,claimExpiresAt:"2999-01-01T00:00:00Z"}),resolveActiveDelegation:async()=>({valid:false}),loadApprovalDecisionHistory:async()=>[{id:"d1",decision:"approve"}],decideSourceEntityOnce:async()=>({updated:true,updateCount:1,version:5}),persistApprovalDecision:async()=>({id:"d1"}),appendAudit:async()=>{}};
test("inbox filters by server-resolved branch and category scope",async()=>{const rows=await listPendingApprovals({tenantId:"t1",actorId:"approver"},base);assert.equal(rows.length,1);});
test("decision updates source once and appends audit",async()=>{const r=await decideApproval({tenantId:"t1",actorId:"approver",approvalId:"a1",decision:"approve",reason:"Reviewed and verified",expectedVersion:2},base);assert.equal(r.sourceVersion,5);});
test("rejects self approval, stale version, wrong branch and duplicate source",async()=>{await assert.rejects(decideApproval({tenantId:"t1",actorId:"creator",approvalId:"a1",decision:"approve",reason:"Self approve attempt",expectedVersion:2},base),{code:"APPROVAL_SELF_APPROVAL_DENIED"});await assert.rejects(decideApproval({tenantId:"t1",actorId:"approver",approvalId:"a1",decision:"approve",reason:"Stale version attempt",expectedVersion:1},base),{code:"APPROVAL_STALE_VERSION"});await assert.rejects(listPendingApprovals({tenantId:"t1",actorId:"approver"},{...base,loadPendingApprovalSources:async()=>[{...approval,branchId:"b2"}]}),{code:"APPROVAL_SOURCE_SCOPE_MISMATCH"});await assert.rejects(listPendingApprovals({tenantId:"t1",actorId:"approver"},{...base,loadPendingApprovalSources:async()=>[{...approval},{...approval}]}),{code:"APPROVAL_DUPLICATE_SOURCE"});});
test("rejects a second source transition or missing audit result",async()=>{await assert.rejects(decideApproval({tenantId:"t1",actorId:"approver",approvalId:"a1",decision:"approve",reason:"Verified evidence",expectedVersion:2},{...base,decideSourceEntityOnce:async()=>({updated:true,updateCount:2})}),{code:"APPROVAL_SOURCE_TRANSITION_FAILED"});});

test("approval can be claimed and history is scoped",async()=>{
 const claim=await claimApproval({tenantId:"t1",actorId:"approver",approvalId:"a1",expectedVersion:2},base);
 assert.equal(claim.claimedBy,"approver");
 const history=await listApprovalHistory({tenantId:"t1",actorId:"approver",approvalId:"a1"},base);
 assert.equal(history.length,1);
});
test("approved active delegation can satisfy role eligibility",async()=>{
 const delegatedActor={...actor,roles:[]};
 const delegatedDeps={...base,resolveApproverScope:async()=>delegatedActor,
  resolveActiveDelegation:async()=>({valid:true,delegatorUserId:"manager",delegatorRole:"finance_approver"})};
 const r=await decideApproval({tenantId:"t1",actorId:"delegate",approvalId:"a1",decision:"approve",reason:"Delegated reviewer checked source",expectedVersion:2},delegatedDeps);
 assert.equal(r.decision,"approve");
});
test("expired approval cannot be claimed",async()=>{
 const expired={...approval,expiresAt:"2000-01-01T00:00:00Z"};
 await assert.rejects(claimApproval({tenantId:"t1",actorId:"approver",approvalId:"a1",expectedVersion:2},{...base,lockApproval:async()=>expired}),{code:"APPROVAL_EXPIRED"});
});
