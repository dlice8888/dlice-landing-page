import test from "node:test";
import assert from "node:assert/strict";
import {createExecutivePersistenceRepository} from "../../src/executive-persistence-repository.mjs";

test("snapshot persistence binds actor and tenant and returns durable id",async()=>{
 const calls=[];
 const repo=createExecutivePersistenceRepository({tenantId:"tenant-a",actorId:"user-a",serviceClient:{rpc:async(name,args)=>{calls.push({name,args});return {data:{id:"snap-1",status:"complete"},error:null};}}});
 const saved=await repo.persistSnapshot({periodStart:"2026-11-28",periodEnd:"2026-11-28",asOf:"2026-11-28T08:00:00Z",formulaVersion:1,expectedBranchCount:1,activeBranchCount:1,reconciledBranchCount:1,status:"complete",totals:{netSalesIdr:100},branches:[{branchId:"branch-a"}],sourceGaps:[],idempotencyKey:"snapshot-0001"});
 assert.equal(saved.id,"snap-1");
 assert.equal(calls[0].args.p_tenant_id,"tenant-a");
 assert.equal(calls[0].args.p_actor_user_id,"user-a");
 assert.equal(calls[0].args.p_formula_version,1);
});

test("claim uses optimistic version and idempotency key",async()=>{
 let call;
 const repo=createExecutivePersistenceRepository({tenantId:"tenant-a",actorId:"user-a",serviceClient:{rpc:async(name,args)=>{call={name,args};return {data:{approval_id:"approval-1",version:3},error:null};}}});
 const result=await repo.claimApproval({approvalId:"approval-1",expectedVersion:2,idempotencyKey:"claim-key-0001"});
 assert.equal(call.name,"executive_claim_approval");
 assert.equal(call.args.p_expected_version,2);
 assert.equal(call.args.p_idempotency_key,"claim-key-0001");
 assert.equal(result.version,3);
});

test("claim rejects a missing optimistic version before RPC",async()=>{
 let called=false;
 const repo=createExecutivePersistenceRepository({tenantId:"tenant-a",actorId:"user-a",serviceClient:{rpc:async()=>{called=true;return {data:{},error:null};}}});
 await assert.rejects(repo.claimApproval({approvalId:"approval-1",expectedVersion:-1,idempotencyKey:"claim-key-0001"}),{code:"EXEC_PERSIST_VERSION_INVALID"});
 assert.equal(called,false);
});

test("snapshot RPC errors remain fail-closed",async()=>{
 const repo=createExecutivePersistenceRepository({tenantId:"tenant-a",actorId:"user-a",serviceClient:{rpc:async()=>({data:null,error:{code:"42501",message:"denied"}})}});
 await assert.rejects(repo.persistSnapshot({periodStart:"2026-11-28",periodEnd:"2026-11-28",asOf:"2026-11-28T08:00:00Z",formulaVersion:1,expectedBranchCount:1,activeBranchCount:1,reconciledBranchCount:1,status:"complete",totals:{},branches:[],sourceGaps:[],idempotencyKey:"snapshot-0001"}),{code:"42501"});
});
