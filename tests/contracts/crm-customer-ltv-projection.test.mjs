import test from "node:test";
import assert from "node:assert/strict";
import { rebuildCustomerLtvSnapshot } from "../../src/crm-customer-ltv-projection.mjs";
const input={tenantId:"tenant-a",actorId:"crm-a",customerId:"customer-a",idempotencyKey:"ltv-rebuild-0001"};
const make=(overrides={})=>({withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
 loadCustomerIdentityForUpdate:async()=>({tenantId:"tenant-a",id:"customer-a",status:"active"}),
 loadMarketingConsent:async()=>({tenantId:"tenant-a",customerId:"customer-a",purpose:"marketing",status:"granted",revokedAt:null}),
 findLtvSnapshotByIdempotencyKey:async()=>null,
 loadReconciledFinancialCloses:async()=>[{tenantId:"tenant-a",id:"close-a",customerId:"customer-a",status:"reconciled",netSalesIdr:100000}],
 loadProcessedRefunds:async()=>[{tenantId:"tenant-a",id:"refund-a",customerId:"customer-a",financialCloseId:"close-a",status:"processed",amountIdr:20000}],
 loadImmutableLoyaltyLedger:async()=>[{tenantId:"tenant-a",id:"earn-a",customerId:"customer-a",immutable:true,pointsDelta:100},{tenantId:"tenant-a",id:"reverse-a",customerId:"customer-a",immutable:true,pointsDelta:-20}],
 computeSourceRevision:async()=>"sha256:source-a",persistCustomerLtvSnapshot:async()=>({id:"snapshot-a"}),appendAudit:async()=>{},...overrides});
test("LTV nets processed refunds and immutable loyalty; consent gates campaign eligibility",async()=>{
 const r=await rebuildCustomerLtvSnapshot(input,make());assert.equal(r.lifetimeValueIdr,80000);assert.equal(r.netLoyaltyPoints,80);assert.equal(r.marketingEligible,true);
});
test("revoked consent disables campaigns without deleting financial LTV",async()=>{
 const r=await rebuildCustomerLtvSnapshot(input,make({loadMarketingConsent:async()=>({tenantId:"tenant-a",customerId:"customer-a",purpose:"marketing",status:"revoked",revokedAt:"2026-11-01"})}));
 assert.equal(r.lifetimeValueIdr,80000);assert.equal(r.marketingEligible,false);
});
test("idempotent retry does not create another snapshot",async()=>{
 assert.deepEqual(await rebuildCustomerLtvSnapshot(input,make({findLtvSnapshotByIdempotencyKey:async()=>({id:"snapshot-old"})})),{status:"duplicate",snapshotId:"snapshot-old"});
});
test("rejects unreconciled closes, cross-tenant sources, pending refunds and mutable loyalty",async()=>{
 await assert.rejects(rebuildCustomerLtvSnapshot(input,make({loadReconciledFinancialCloses:async()=>[{tenantId:"tenant-a",id:"c",customerId:"customer-a",status:"pending",netSalesIdr:1}]})),{code:"CRM_LTV_CLOSE_UNRECONCILED"});
 await assert.rejects(rebuildCustomerLtvSnapshot(input,make({loadProcessedRefunds:async()=>[{tenantId:"tenant-b"}]})),{code:"CRM_LTV_TENANT_SCOPE_MISMATCH"});
 await assert.rejects(rebuildCustomerLtvSnapshot(input,make({loadProcessedRefunds:async()=>[{tenantId:"tenant-a",id:"r",customerId:"customer-a",financialCloseId:"close-a",status:"pending",amountIdr:1}]})),{code:"CRM_LTV_REFUND_UNRECONCILED"});
 await assert.rejects(rebuildCustomerLtvSnapshot(input,make({loadImmutableLoyaltyLedger:async()=>[{tenantId:"tenant-a",customerId:"customer-a",immutable:false,pointsDelta:1}]})),{code:"CRM_LTV_LOYALTY_SOURCE_INVALID"});
});
test("rejects refunds above sales and inactive customer identity",async()=>{
 await assert.rejects(rebuildCustomerLtvSnapshot(input,make({loadProcessedRefunds:async()=>[{tenantId:"tenant-a",id:"r",customerId:"customer-a",financialCloseId:"close-a",status:"processed",amountIdr:120000}]})),{code:"CRM_LTV_REFUNDS_EXCEED_SALES"});
 await assert.rejects(rebuildCustomerLtvSnapshot(input,make({loadCustomerIdentityForUpdate:async()=>({tenantId:"tenant-a",id:"customer-a",status:"merged"})})),{code:"CRM_LTV_CUSTOMER_INACTIVE"});
});
