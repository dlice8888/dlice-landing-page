/**
 * CRM referral, customer support and lifetime-value workflows.
 * Source transactions and customer identity must be server-resolved and tenant-scoped.
 */
const fail=(code,message)=>{const error=new Error(message);error.code=code;throw error;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("CRM_WORKFLOW_INPUT_REQUIRED",f);return v.trim();};
const adapter=(deps,name)=>{if(typeof deps?.[name]!=="function")fail("CRM_WORKFLOW_ADAPTER_REQUIRED",name);return deps[name];};
const scope=(input,action)=>({tenantId:req(input?.tenantId,"tenantId"),branchId:input?.branchId==null?null:req(input.branchId,"branchId"),
 actorId:req(input?.actorId,"actorId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),action});
const txScope=(deps,s,fn)=>adapter(deps,"withTenantTransaction")(s,async tx=>{
 if(!tx)fail("CRM_WORKFLOW_TRANSACTION_REQUIRED","Database transaction required");
 await adapter(deps,"authorize")(tx,s);return fn(tx);
});
const assertTenant=(r,s,name)=>{if(!r||r.tenantId!==s.tenantId||(s.branchId&&r.branchId!==s.branchId))fail("CRM_WORKFLOW_SCOPE_MISMATCH",name);};

/** A referral reward is eligible only after a reconciled first paid net sale. */
export function evaluateReferralQualification(input){
 const tenantId=req(input?.tenantId,"tenantId"),referrerId=req(input?.referrerId,"referrerId"),referredId=req(input?.referredCustomerId,"referredCustomerId");
 if(referrerId===referredId)fail("CRM_REFERRAL_SELF_REFERRAL_DENIED","A customer cannot refer themselves");
 if(input.referrerTenantId!==tenantId||input.referredTenantId!==tenantId)fail("CRM_REFERRAL_TENANT_MISMATCH","Both customer identities must belong to the same tenant");
 const sale=input.qualifyingSale;
 if(!sale||sale.tenantId!==tenantId||sale.customerId!==referredId||sale.status!=="paid"||sale.reconciliationStatus!=="RECONCILED"||
    sale.isFirstPaidSale!==true||sale.refunded===true||sale.chargeback===true) {
  return Object.freeze({eligible:false,reason:"QUALIFYING_FIRST_PAID_RECONCILED_SALE_REQUIRED"});
 }
 const minimum=Number(input.minimumNetSaleIdr??0),net=Number(sale.netSaleIdr);
 if(!Number.isSafeInteger(minimum)||minimum<0||!Number.isSafeInteger(net)||net<minimum){
  return Object.freeze({eligible:false,reason:"REFERRAL_MINIMUM_NET_SALE_NOT_MET"});
 }
 return Object.freeze({eligible:true,tenantId,referrerId,referredCustomerId:referredId,sourceSaleId:req(sale.id,"sale.id"),netSaleIdr:net});
}

/** Persist a referral reward once; the source sale and identities are loaded by trusted adapters. */
export async function awardQualifiedReferral(input,deps){
 const s=scope(input,"crm.referral.award"),referralId=req(input.referralId,"referralId");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findReferralRewardByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",rewardId:prior.id});
  const referral=await adapter(deps,"loadReferralForUpdate")(tx,{...s,referralId});assertTenant(referral,s,"referral");
  const identities=await adapter(deps,"loadReferralCustomerIdentities")(tx,{...s,referral});
  if(!identities||identities.referrerId!==referral.referrerCustomerId||identities.referredCustomerId!==referral.referredCustomerId||
     identities.referrerTenantId!==s.tenantId||identities.referredTenantId!==s.tenantId)fail("CRM_REFERRAL_IDENTITY_INVALID","Referral customer identities must be verified in tenant scope");
  const sale=await adapter(deps,"loadFirstPaidSaleForCustomer")(tx,{...s,customerId:referral.referredCustomerId});
  const decision=evaluateReferralQualification({tenantId:s.tenantId,referrerId:referral.referrerCustomerId,
    referredCustomerId:referral.referredCustomerId,referrerTenantId:identities.referrerTenantId,
    referredTenantId:identities.referredTenantId,minimumNetSaleIdr:referral.minimumNetSaleIdr,qualifyingSale:sale});
  if(!decision.eligible)return Object.freeze({status:"ineligible",reason:decision.reason});
  const saved=await adapter(deps,"persistReferralReward")(tx,{...s,referralId,...decision});
  if(!saved?.id)fail("CRM_REFERRAL_REWARD_PERSIST_FAILED","Referral reward was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"crm.referral.reward_awarded",entityType:"crm_referral_reward",entityId:saved.id,
   metadata:{sourceSaleId:decision.sourceSaleId,netSaleIdr:decision.netSaleIdr}});
  return Object.freeze({status:"awarded",rewardId:saved.id,sourceSaleId:decision.sourceSaleId});
}

/** Create a support case using a server-verified customer identity and SLA policy. */
export async function createCustomerSupportCase(input,deps){
 const s=scope(input,"crm.support_case.create"),customerId=req(input.customerId,"customerId");
 const subject=req(input.subject,"subject"),description=req(input.description,"description"),severity=input.severity;
 if(!["low","normal","high","urgent"].includes(severity))fail("CRM_SUPPORT_SEVERITY_INVALID","Unsupported support severity");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findSupportCaseByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",caseId:prior.id});
  const customer=await adapter(deps,"loadCustomerIdentityForUpdate")(tx,{...s,customerId});
  assertTenant(customer,s,"customer");
  const consent=await adapter(deps,"loadSupportContactConsent")(tx,{...s,customerId});
  if(!consent?.supportContactAllowed)fail("CRM_SUPPORT_CONTACT_CONSENT_REQUIRED","Valid support-contact consent is required");
  const policy=await adapter(deps,"loadApprovedSupportSlaPolicy")(tx,{...s,severity});
  if(!policy||policy.status!=="approved"||!Number.isFinite(policy.firstResponseMinutes)||policy.firstResponseMinutes<=0)
   fail("CRM_SUPPORT_SLA_POLICY_REQUIRED","Approved SLA policy is required");
  const saved=await adapter(deps,"persistCustomerSupportCase")(tx,{...s,customerId,subject,description,severity,
   firstResponseDueMinutes:policy.firstResponseMinutes,resolutionDueMinutes:policy.resolutionMinutes??null,status:"open"});
  if(!saved?.id)fail("CRM_SUPPORT_CASE_PERSIST_FAILED","Support case was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"crm.support_case.created",entityType:"crm_support_case",entityId:saved.id,
   metadata:{severity,firstResponseMinutes:policy.firstResponseMinutes}});
  return Object.freeze({status:"created",caseId:saved.id,firstResponseDueMinutes:policy.firstResponseMinutes});
 });
}

/** Calculate LTV from deduplicated, reconciled paid transactions only. */
export function buildCustomerLifetimeMetrics(input){
 const tenantId=req(input?.tenantId,"tenantId"),customerId=req(input?.customerId,"customerId");
 if(!Array.isArray(input.transactions))fail("CRM_LTV_TRANSACTIONS_REQUIRED","Authoritative transaction list is required");
 const seen=new Set(),valid=[];
 for(const sale of input.transactions){
  if(!sale||sale.tenantId!==tenantId||sale.customerId!==customerId)fail("CRM_LTV_SCOPE_MISMATCH","All transactions must match the customer tenant scope");
  if(!sale.id||seen.has(sale.id))fail("CRM_LTV_DUPLICATE_TRANSACTION","Duplicate or missing source transaction ID");
  seen.add(sale.id);
  if(sale.status==="refunded"||sale.status==="voided"||sale.chargeback===true)continue;
  if(sale.status!=="paid"||sale.reconciliationStatus!=="RECONCILED")fail("CRM_LTV_UNRECONCILED_SOURCE","Only reconciled paid transactions may contribute to LTV");
  const net=Number(sale.netSaleIdr);
  if(!Number.isSafeInteger(net)||net<0)fail("CRM_LTV_NET_SALE_INVALID","Net sale must be a non-negative integer IDR");
  const date=Date.parse(sale.paidAt);
  if(!Number.isFinite(date))fail("CRM_LTV_PAID_DATE_INVALID","paidAt must be a valid timestamp");
  valid.push({id:sale.id,net,date});
 }
 valid.sort((a,b)=>a.date-b.date);
 const orderCount=valid.length,totalNetRevenueIdr=valid.reduce((sum,x)=>sum+x.net,0);
 const first=valid[0]?.date??null,last=valid.at(-1)?.date??null;
 return Object.freeze({tenantId,customerId,orderCount,totalNetRevenueIdr,
  averageOrderValueIdr:orderCount?Math.round(totalNetRevenueIdr/orderCount):0,
  repeatCustomer:orderCount>1,firstPurchaseAt:first?new Date(first).toISOString():null,
  lastPurchaseAt:last?new Date(last).toISOString():null});
}

/** Persist a recomputed LTV snapshot from authoritative tenant-scoped transactions. */
export async function refreshCustomerLifetimeSnapshot(input,deps){
 const s=scope(input,"crm.customer_ltv.refresh"),customerId=req(input.customerId,"customerId");
 return txScope(deps,s,async tx=>{
  const customer=await adapter(deps,"loadCustomerIdentityForUpdate")(tx,{...s,customerId});assertTenant(customer,s,"customer");
  const transactions=await adapter(deps,"loadReconciledCustomerTransactions")(tx,{...s,customerId});
  const metrics=buildCustomerLifetimeMetrics({tenantId:s.tenantId,customerId,transactions});
  const snapshot=await adapter(deps,"persistCustomerLifetimeSnapshot")(tx,{...s,...metrics,sourceRevision:req(input.sourceRevision,"sourceRevision")});
  if(!snapshot?.id)fail("CRM_LTV_SNAPSHOT_PERSIST_FAILED","LTV snapshot was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"crm.customer_ltv.refreshed",entityType:"crm_customer_ltv_snapshot",entityId:snapshot.id,
   metadata:{orderCount:metrics.orderCount,totalNetRevenueIdr:metrics.totalNetRevenueIdr}});
  return Object.freeze({status:"refreshed",snapshotId:snapshot.id,...metrics});
 });
}
