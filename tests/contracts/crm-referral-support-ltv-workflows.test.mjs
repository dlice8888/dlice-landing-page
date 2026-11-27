import test from "node:test";
import assert from "node:assert/strict";
import {
 evaluateReferralQualification, awardQualifiedReferral, createCustomerSupportCase,
 buildCustomerLifetimeMetrics, refreshCustomerLifetimeSnapshot,
} from "../../src/crm-referral-support-ltv-workflows.mjs";

const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"crm-a",idempotencyKey:"crm-flow-0001"};
const common=(overrides={})=>({
 withTenantTransaction:async(_scope,fn)=>fn({tx:true}),
 authorize:async(_tx,s)=>{assert.equal(s.tenantId,"tenant-a");},
 appendAudit:async(_tx,e)=>{assert.ok(e.action.startsWith("crm."));},
 ...overrides,
});
const qualifyingSale={id:"sale-first",tenantId:"tenant-a",customerId:"customer-b",status:"paid",
 reconciliationStatus:"RECONCILED",isFirstPaidSale:true,refunded:false,chargeback:false,netSaleIdr:150000};

test("referral qualification requires a first paid reconciled net sale",()=>{
 const result=evaluateReferralQualification({tenantId:"tenant-a",referrerId:"customer-a",referredCustomerId:"customer-b",
  referrerTenantId:"tenant-a",referredTenantId:"tenant-a",minimumNetSaleIdr:100000,qualifyingSale});
 assert.equal(result.eligible,true);assert.equal(result.sourceSaleId,"sale-first");
});
test("referral qualification rejects self-referral, cross-tenant and refunded sale",()=>{
 assert.throws(()=>evaluateReferralQualification({tenantId:"tenant-a",referrerId:"same",referredCustomerId:"same",
  referrerTenantId:"tenant-a",referredTenantId:"tenant-a",qualifyingSale}),{code:"CRM_REFERRAL_SELF_REFERRAL_DENIED"});
 assert.throws(()=>evaluateReferralQualification({tenantId:"tenant-a",referrerId:"a",referredCustomerId:"b",
  referrerTenantId:"tenant-a",referredTenantId:"tenant-b",qualifyingSale}),{code:"CRM_REFERRAL_TENANT_MISMATCH"});
 assert.equal(evaluateReferralQualification({tenantId:"tenant-a",referrerId:"a",referredCustomerId:"b",
  referrerTenantId:"tenant-a",referredTenantId:"tenant-a",qualifyingSale:{...qualifyingSale,refunded:true}}).eligible,false);
});
test("referral reward is persisted once from authoritative identity and first sale",async()=>{
 const deps=common({
  findReferralRewardByIdempotencyKey:async()=>null,
  loadReferralForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",referrerCustomerId:"customer-a",referredCustomerId:"customer-b",minimumNetSaleIdr:100000}),
  loadReferralCustomerIdentities:async()=>({referrerId:"customer-a",referredCustomerId:"customer-b",referrerTenantId:"tenant-a",referredTenantId:"tenant-a"}),
  loadFirstPaidSaleForCustomer:async()=>qualifyingSale,
  persistReferralReward:async()=>({id:"reward-a"}),
 });
 const result=await awardQualifiedReferral({...base,referralId:"referral-a"},deps);
 assert.deepEqual(result,{status:"awarded",rewardId:"reward-a",sourceSaleId:"sale-first"});
});
test("support case requires consent and an approved SLA policy",async()=>{
 const deps=common({
  findSupportCaseByIdempotencyKey:async()=>null,
  loadCustomerIdentityForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"customer-a"}),
  loadSupportContactConsent:async()=>({supportContactAllowed:true}),
  loadApprovedSupportSlaPolicy:async()=>({status:"approved",firstResponseMinutes:30,resolutionMinutes:240}),
  persistCustomerSupportCase:async(_tx,row)=>{assert.equal(row.firstResponseDueMinutes,30);return{id:"case-a"};},
 });
 const result=await createCustomerSupportCase({...base,customerId:"customer-a",subject:"Order issue",
  description:"Missing item in delivery",severity:"high"},deps);
 assert.deepEqual(result,{status:"created",caseId:"case-a",firstResponseDueMinutes:30});
});
test("support case refuses missing consent before persistence",async()=>{
 let persisted=false;
 const deps=common({findSupportCaseByIdempotencyKey:async()=>null,
  loadCustomerIdentityForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"customer-a"}),
  loadSupportContactConsent:async()=>({supportContactAllowed:false}),
  persistCustomerSupportCase:async()=>{persisted=true;}});
 await assert.rejects(createCustomerSupportCase({...base,customerId:"customer-a",subject:"Help",
  description:"Need assistance",severity:"normal"},deps),{code:"CRM_SUPPORT_CONTACT_CONSENT_REQUIRED"});
 assert.equal(persisted,false);
});
test("LTV counts only reconciled paid net transactions and excludes refunds",()=>{
 const metrics=buildCustomerLifetimeMetrics({tenantId:"tenant-a",customerId:"customer-a",transactions:[
  {id:"s1",tenantId:"tenant-a",customerId:"customer-a",status:"paid",reconciliationStatus:"RECONCILED",netSaleIdr:10000,paidAt:"2026-11-01T10:00:00Z"},
  {id:"s2",tenantId:"tenant-a",customerId:"customer-a",status:"paid",reconciliationStatus:"RECONCILED",netSaleIdr:20000,paidAt:"2026-11-02T10:00:00Z"},
  {id:"s3",tenantId:"tenant-a",customerId:"customer-a",status:"refunded",netSaleIdr:5000,paidAt:"2026-11-03T10:00:00Z"},
 ]});
 assert.equal(metrics.orderCount,2);assert.equal(metrics.totalNetRevenueIdr,30000);
 assert.equal(metrics.averageOrderValueIdr,15000);assert.equal(metrics.repeatCustomer,true);
});
test("LTV rejects unreconciled and duplicate transaction sources",()=>{
 const row={id:"s1",tenantId:"tenant-a",customerId:"customer-a",status:"paid",reconciliationStatus:"PENDING",netSaleIdr:100,paidAt:"2026-11-01T10:00:00Z"};
 assert.throws(()=>buildCustomerLifetimeMetrics({tenantId:"tenant-a",customerId:"customer-a",transactions:[row]}),
  {code:"CRM_LTV_UNRECONCILED_SOURCE"});
 const good={...row,reconciliationStatus:"RECONCILED"};
 assert.throws(()=>buildCustomerLifetimeMetrics({tenantId:"tenant-a",customerId:"customer-a",transactions:[good,good]}),
  {code:"CRM_LTV_DUPLICATE_TRANSACTION"});
});
test("LTV refresh uses authorized customer and authoritative source adapter",async()=>{
 const deps=common({
  loadCustomerIdentityForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"customer-a"}),
  loadReconciledCustomerTransactions:async()=>[{id:"s1",tenantId:"tenant-a",customerId:"customer-a",status:"paid",
   reconciliationStatus:"RECONCILED",netSaleIdr:12000,paidAt:"2026-11-01T10:00:00Z"}],
  persistCustomerLifetimeSnapshot:async(_tx,row)=>{assert.equal(row.totalNetRevenueIdr,12000);return{id:"ltv-a"};},
 });
 const result=await refreshCustomerLifetimeSnapshot({...base,customerId:"customer-a",sourceRevision:"tenant-a:crm:v1"},deps);
 assert.equal(result.status,"refreshed");assert.equal(result.snapshotId,"ltv-a");
});
