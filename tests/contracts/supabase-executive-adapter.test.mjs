import test from "node:test";
import assert from "node:assert/strict";
import {createSupabaseExecutiveAdapter} from "../../src/supabase-executive-adapter.mjs";
function fake(response){const calls=[];return {calls,client:{rpc:async(name,args)=>{calls.push({name,args});return typeof response==="function"?response(name,args):response;}}};}
test("sales monitor calls one atomic server RPC without trusting client timezone",async()=>{
 const f=fake({data:{snapshot_id:"s1"},error:null}),a=createSupabaseExecutiveAdapter(f.client);
 const r=await a.loadSalesMonitorSnapshot({actorId:"u1",tenantId:"t1",period:"week",startDate:"2026-11-23",endDate:"2026-11-29",branchIds:["b1"]});
 assert.equal(r.snapshot_id,"s1");assert.equal(f.calls.length,1);assert.equal(f.calls[0].name,"executive_sales_monitor_snapshot");
 assert.equal(f.calls[0].args.p_actor_user_id,"u1");assert.deepEqual(f.calls[0].args.p_branch_ids,["b1"]);assert.equal("p_timezone" in f.calls[0].args,false);
});
test("approval list, claim and decision use server-side RPCs",async()=>{
 const f=fake({data:{ok:true},error:null}),a=createSupabaseExecutiveAdapter(f.client);
 await a.listPendingApprovals({actorId:"u1",tenantId:"t1",categories:["procurement"]});
 await a.claimApproval({actorId:"u1",tenantId:"t1",sourceEntity:"purchase_requisition",sourceEntityId:"p1",expectedSourceVersion:7});
 await a.decideApproval({actorId:"u1",tenantId:"t1",approvalId:"a1",decision:"approve",reason:"Reviewed and approved",expectedVersion:2});
 assert.deepEqual(f.calls.map(x=>x.name),["list_pending_approvals","claim_approval","decide_approval"]);
});
test("RPC errors preserve server error code",async()=>{
 const f=fake({data:null,error:{message:"scope denied",code:"42501"}}),a=createSupabaseExecutiveAdapter(f.client);
 await assert.rejects(a.listPendingApprovals({actorId:"u1",tenantId:"t1"}),{code:"42501",message:"scope denied"});
});
test("missing actor and RPC client fail closed",async()=>{
 assert.throws(()=>createSupabaseExecutiveAdapter({}),{code:"EXECUTIVE_RPC_CLIENT_REQUIRED"});
 const a=createSupabaseExecutiveAdapter({rpc:async()=>({data:{},error:null})});
 await assert.rejects(a.loadSalesMonitorSnapshot({tenantId:"t1",period:"day",startDate:"2026-11-28",endDate:"2026-11-28"}),{code:"EXECUTIVE_INPUT_REQUIRED"});
});
