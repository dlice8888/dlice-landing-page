/**
 * Tenant-wide CRM customer LTV projection from reconciled financial-close,
 * processed-refund and immutable loyalty-ledger sources.
 * Financial LTV is independent of marketing consent; consent only gates campaigns.
 */
const fail=(code,message)=>{const error=new Error(message);error.code=code;throw error;};
const required=(value,field)=>{if(typeof value!=="string"||!value.trim())fail("CRM_LTV_INPUT_REQUIRED",field);return value.trim();};
const adapter=(deps,name)=>{if(typeof deps?.[name]!=="function")fail("CRM_LTV_ADAPTER_REQUIRED",name);return deps[name];};
const amount=(value,field)=>{if(!Number.isSafeInteger(value)||value<0)fail("CRM_LTV_AMOUNT_INVALID",field);return value;};
const sum=(rows,pick,field)=>rows.reduce((total,row)=>{const next=total+amount(pick(row),field);if(!Number.isSafeInteger(next))fail("CRM_LTV_AMOUNT_OVERFLOW",field);return next;},0);
const assertTenant=(row,tenantId,field)=>{if(!row||row.tenantId!==tenantId)fail("CRM_LTV_TENANT_SCOPE_MISMATCH",field);};

/** Required tx adapters: authorize, identity, consent, idempotency, reconciled closes,
 * processed refunds, immutable loyalty ledger, source revision, snapshot persistence,
 * audit append. All adapters must share the supplied transaction.
 */
export async function rebuildCustomerLtvSnapshot(input,deps){
 const scope=Object.freeze({tenantId:required(input?.tenantId,"tenantId"),actorId:required(input?.actorId,"actorId"),
  customerId:required(input?.customerId,"customerId"),idempotencyKey:required(input?.idempotencyKey,"idempotencyKey"),
  action:"crm.customer.ltv.rebuild"});
 return adapter(deps,"withTenantTransaction")(scope,async(tx)=>{
  if(!tx)fail("CRM_LTV_TRANSACTION_REQUIRED","A database transaction is required");
  await adapter(deps,"authorize")(tx,scope);
  const prior=await adapter(deps,"findLtvSnapshotByIdempotencyKey")(tx,scope);
  if(prior)return Object.freeze({status:"duplicate",snapshotId:prior.id});
  const customer=await adapter(deps,"loadCustomerIdentityForUpdate")(tx,scope);
  assertTenant(customer,scope.tenantId,"customer");
  if(customer.status!=="active")fail("CRM_LTV_CUSTOMER_INACTIVE","Customer identity must be active");
  const closes=await adapter(deps,"loadReconciledFinancialCloses")(tx,scope);
  const refunds=await adapter(deps,"loadProcessedRefunds")(tx,scope);
  const loyalty=await adapter(deps,"loadImmutableLoyaltyLedger")(tx,scope);
  const consent=await adapter(deps,"loadMarketingConsent")(tx,{...scope,purpose:"marketing"});
  for(const [rows,name] of [[closes,"financialCloses"],[refunds,"refunds"],[loyalty,"loyaltyLedger"]]){
   if(!Array.isArray(rows))fail("CRM_LTV_SOURCE_INVALID",name);
   for(const row of rows)assertTenant(row,scope.tenantId,name);
  }
  const closeIds=new Set();
  for(const close of closes){
   if(close.status!=="reconciled"||close.customerId!==scope.customerId)fail("CRM_LTV_CLOSE_UNRECONCILED","Every close must be reconciled for this customer");
   if(closeIds.has(close.id))fail("CRM_LTV_DUPLICATE_CLOSE","Duplicate financial close source");
   closeIds.add(close.id);amount(close.netSalesIdr,"financialClose.netSalesIdr");
  }
  const refundIds=new Set();
  for(const refund of refunds){
   if(refund.status!=="processed"||refund.customerId!==scope.customerId||!closeIds.has(refund.financialCloseId))
    fail("CRM_LTV_REFUND_UNRECONCILED","Refund must be processed and linked to a reconciled close");
   if(refundIds.has(refund.id))fail("CRM_LTV_DUPLICATE_REFUND","Duplicate refund source");
   refundIds.add(refund.id);amount(refund.amountIdr,"refund.amountIdr");
  }
  for(const entry of loyalty){
   if(entry.customerId!==scope.customerId||entry.immutable!==true||!Number.isSafeInteger(entry.pointsDelta))
    fail("CRM_LTV_LOYALTY_SOURCE_INVALID","Loyalty source must be an immutable customer ledger entry");
  }
  const grossEligibleSalesIdr=sum(closes,row=>row.netSalesIdr,"financialClose.netSalesIdr");
  const processedRefundsIdr=sum(refunds,row=>row.amountIdr,"refund.amountIdr");
  if(processedRefundsIdr>grossEligibleSalesIdr)fail("CRM_LTV_REFUNDS_EXCEED_SALES","Processed refunds exceed eligible sales");
  const lifetimeValueIdr=grossEligibleSalesIdr-processedRefundsIdr;
  const netLoyaltyPoints=loyalty.reduce((total,row)=>total+row.pointsDelta,0);
  if(!Number.isSafeInteger(netLoyaltyPoints))fail("CRM_LTV_POINTS_OVERFLOW","netLoyaltyPoints");
  const marketingEligible=consent?.tenantId===scope.tenantId&&consent.customerId===scope.customerId&&
   consent.purpose==="marketing"&&consent.status==="granted"&&consent.revokedAt==null;
  const sourceRevision=required(await adapter(deps,"computeSourceRevision")(tx,scope,{closes,refunds,loyalty,consent}),"sourceRevision");
  const snapshot=await adapter(deps,"persistCustomerLtvSnapshot")(tx,{...scope,currency:"IDR",
   grossEligibleSalesIdr,processedRefundsIdr,lifetimeValueIdr,reconciledOrderCount:closes.length,
   netLoyaltyPoints,marketingEligible,sourceRevision});
  if(!snapshot?.id)fail("CRM_LTV_PERSIST_FAILED","LTV snapshot was not persisted");
  await adapter(deps,"appendAudit")(tx,{...scope,action:"crm.customer.ltv.snapshot_created",
   entityType:"crm_customer_ltv_snapshots",entityId:snapshot.id,
   metadata:{lifetimeValueIdr,reconciledOrderCount:closes.length,marketingEligible,sourceRevision}});
  return Object.freeze({status:"created",snapshotId:snapshot.id,lifetimeValueIdr,processedRefundsIdr,
   reconciledOrderCount:closes.length,netLoyaltyPoints,marketingEligible,sourceRevision});
 });
}
