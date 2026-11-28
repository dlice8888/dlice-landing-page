import test from "node:test";
import assert from "node:assert/strict";
import { rebuildCustomerLtvSnapshot } from "../../src/crm-customer-ltv-projection.mjs";

const input={tenantId:"tenant-a",actorId:"crm-a",customerId:"customer-a",idempotencyKey:"ltv-rebuild-0001"};
const base=()=>({
 withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
 loadCustomerIdentityForUpdate:async()=>({tenantId:"tenant-a",id:"customer-a",status:"active"}),
 loadMarketingConsent:async()=>({tenantId:"tenant-a",customerId:"customer-a",purpose:"marketing",status:"granted",revokedAt:null}),
 findLtvSnapshotByIdempotencyKey:async()=>null,
 loadReconciledFinancialCloses:async()=>[{tenantId:"tenant-a",id:"close-a",customerId:"customer-a",status:"reconciled",netSalesIdr:100000}],
 loadProcessedRefunds:async()=>[{tenantId:"tenant-a",id:"refund-a",customerId:"customer-a",financialCloseId:"close-a",status:"processed",amountIdr:20000}],
 loadImmutableLoyaltyLedger:async()=>[{tenantId:"tenant-a",id:"earn-a",customerId:"customer-a",immutable:true,pointsDelta:100},{tenantId:"tenant-a",id:"reverse-a",customerId:"customer-a",immutable:true,pointsDelta:-20}],
 computeSourceRevision:async()=>"sha256:source-a",
 persistCustomerLtvSnapshot:async(_tx,row)=>{base.last=row;return{id:"snapshot-a"};},
 appendAudit:async()=>{},
});

test("LTV nets processed refunds and immutable loyalty entries, consent gates campaigns",async()=>{
 const deps=base();const result=await rebuildCustomerLtvSnapshot(input,deps);
 assert.equal(result.lifetimeValueIdr,80000);assert.equal(result.processedRefundsIdr,20000);
 assert.equal(result.netLoyaltyPoints,80);assert.equal(result.marketingEligible,true);
 assert.equal(base.last.currency,"IDR");
});

test("financial LTV remains calculable when marketing consent is revoked",async()=>{
 const deps={...base(),loadMarketingConsent:async()=>({tenantId:"tenant-a",customerId:"customer-a",purpose:"marketing",status:"revoked",revokedAt:"2026-11-01"})};
 const result=await rebuildCustomerLtvSnapshot(input,deps);assert.equal(result.lifetimeValueIdr,80000);assert.equal(result.marketingEligible,false);
});

test("idempotent retry does not create a second snapshot",async()=>{
 const deps={...base(),findLtvSnapshotByIdempotencyKey:async()=>({id:"snapshot-old"})};
 assert.deepEqual(await rebuildCustomerLtvSnapshot(input,deps),{status:"duplicate",snapshotId:"snapshot-old"});
});

test("rejects unreconciled sales, cross-tenant data, unprocessed refunds and invalid loyalty rows",async()=>{
 await assert.rejects(rebuildCustomerLtvSnapshot(input,{...base(),loadReconciledFinancialCloses:async()=>[{tenantId:"tenant-a",id:"close-a",customerId:"customer-a",status:"pending",netSalesIdr:1}]}),{code:"CRM_LTV_CLOSE_UNRECONCILED"});
 await assert.rejects(rebuildCustomerLtvSnapshot(input,{...base(),loadProcessedRefunds:async()=>[{tenantId:"tenant-b"}]}),{code:"CRM_LTV_TENANT_SCOPE_MISMATCH"});
 await assert.rejects(rebuildCustomerLtvSnapshot(input,{...base(),loadProcessedRefunds:async()=>[{tenantId:"tenant-a",id:"refund-a",customerId:"customer-a",financialCloseId:"close-a",status:"pending",amountIdr:1}]}),{code:"CRM_LTV_REFUND_UNRECONCILED"});
 await assert.rejects(rebuildCustomerLtvSnapshot(input,{...base(),loadImmutableLoyaltyLedger:async()=>[{tenantId:"tenant-a",customerId:"customer-a",immutable:false,pointsDelta:1}]}),{code:"CRM_LTV_LOYALTY_SOURCE_INVALID"});
});

test("rejects refunds above paid net sales and inactive customer identities",async()=>{
 await assert.rejects(rebuildCustomerLtvSnapshot(input,{...base(),loadProcessedRefunds:async()=>[{tenantId:"tenant-a",id:"refund-a",customerId:"customer-a",financialCloseId:"close-a",status:"processed",amountIdr:120000}]}),{code:"CRM_LTV_REFUNDS_EXCEED_SALES"});
 await assert.rejects(rebuildCustomerLtvSnapshot(input,{...base(),loadCustomerIdentityForUpdate:async()=>({tenantId:"tenant-a",id:"customer-a",status:"merged"})}),{code:"CRM_LTV_CUSTOMER_INACTIVE"});
});
