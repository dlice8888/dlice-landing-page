/**
 * Final blocked acceptance work: recipe/production parity, waste variance,
 * branch opening readiness and payment provider settlement fee reconciliation.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("ACCEPTANCE_INPUT_REQUIRED",f);return v.trim();};
const adapter=(d,n)=>{if(typeof d?.[n]!=="function")fail("ACCEPTANCE_ADAPTER_REQUIRED",n);return d[n];};
const scope=(i,a)=>({tenantId:req(i?.tenantId,"tenantId"),branchId:req(i?.branchId,"branchId"),
 actorId:req(i?.actorId,"actorId"),idempotencyKey:req(i?.idempotencyKey,"idempotencyKey"),action:a});
const txScope=(d,s,fn)=>adapter(d,"withTenantTransaction")(s,async tx=>{
 if(!tx)fail("ACCEPTANCE_TRANSACTION_REQUIRED","Database transaction required");
 await adapter(d,"authorize")(tx,s);return fn(tx);
});
const assertScope=(r,s,n)=>{if(!r||r.tenantId!==s.tenantId||r.branchId!==s.branchId)fail("ACCEPTANCE_SCOPE_MISMATCH",n);};

/** Compare theoretical recipe consumption with posted, reconciled stock consumption. */
export function calculateProductionUsageVariance(input){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId");
 if(!Array.isArray(input.theoretical)||!Array.isArray(input.actual)||!input.theoretical.length)
  fail("PRODUCTION_VARIANCE_INPUT_REQUIRED","Theoretical recipe and actual stock rows are required");
 const expected=new Map(),actual=new Map();
 for(const row of input.theoretical){
  if(row.tenantId!==tenantId||row.branchId!==branchId||row.recipeStatus!=="approved")
   fail("PRODUCTION_VARIANCE_RECIPE_INVALID","Theoretical usage must come from approved same-branch recipe version");
  const quantity=Number(row.quantity),cost=Number(row.unitCostIdr);
  if(!Number.isFinite(quantity)||quantity<0||!Number.isSafeInteger(cost)||cost<0)fail("PRODUCTION_VARIANCE_VALUE_INVALID","Theoretical quantity/cost invalid");
  const prior=expected.get(row.itemId)||{quantity:0,cost:0};
  prior.quantity+=quantity;prior.cost+=quantity*cost;expected.set(row.itemId,prior);
 }
 for(const row of input.actual){
  if(row.tenantId!==tenantId||row.branchId!==branchId||row.status!=="posted"||row.reconciliationStatus!=="RECONCILED")
   fail("PRODUCTION_VARIANCE_ACTUAL_UNRECONCILED","Actual usage must be posted and reconciled");
  const quantity=Number(row.quantity),cost=Number(row.unitCostIdr);
  if(!Number.isFinite(quantity)||quantity<0||!Number.isSafeInteger(cost)||cost<0)fail("PRODUCTION_VARIANCE_VALUE_INVALID","Actual quantity/cost invalid");
  const prior=actual.get(row.itemId)||{quantity:0,cost:0};
  prior.quantity+=quantity;prior.cost+=quantity*cost;actual.set(row.itemId,prior);
 }
 const itemIds=new Set([...expected.keys(),...actual.keys()]);
 const rows=[...itemIds].sort().map(itemId=>{
  const e=expected.get(itemId)||{quantity:0,cost:0},a=actual.get(itemId)||{quantity:0,cost:0};
  return Object.freeze({itemId,theoreticalQuantity:Number(e.quantity.toFixed(6)),actualQuantity:Number(a.quantity.toFixed(6)),
   varianceQuantity:Number((a.quantity-e.quantity).toFixed(6)),theoreticalCostIdr:Math.round(e.cost),actualCostIdr:Math.round(a.cost),
   varianceCostIdr:Math.round(a.cost-e.cost)});
 });
 return Object.freeze({tenantId,branchId,rows:Object.freeze(rows),
  totalTheoreticalCostIdr:rows.reduce((s,r)=>s+r.theoreticalCostIdr,0),
  totalActualCostIdr:rows.reduce((s,r)=>s+r.actualCostIdr,0),
  totalVarianceCostIdr:rows.reduce((s,r)=>s+r.varianceCostIdr,0)});
}

/** Enforce that POS and production consume the same immutable approved recipe version. */
export function assertApprovedRecipeVersionParity(input){
 const sale=input.saleLine,batch=input.productionBatch;
 if(!sale||!batch||sale.tenantId!==input.tenantId||batch.tenantId!==input.tenantId||
  sale.branchId!==batch.branchId||sale.productId!==batch.productId)
  fail("RECIPE_VERSION_PARITY_SCOPE_MISMATCH","Sale and production batch must match tenant, branch and product");
 if(sale.recipeStatus!=="approved"||batch.recipeStatus!=="approved"||
  !sale.recipeVersion||sale.recipeVersion!==batch.recipeVersion||
  sale.recipeSnapshotHash!==batch.recipeSnapshotHash)
  fail("RECIPE_VERSION_PARITY_FAILED","POS and production must use the same approved recipe version and immutable snapshot hash");
 const soldAt=Date.parse(sale.soldAt),effectiveFrom=Date.parse(sale.recipeEffectiveFrom);
 if(!Number.isFinite(soldAt)||!Number.isFinite(effectiveFrom)||effectiveFrom>soldAt)
  fail("RECIPE_VERSION_NOT_EFFECTIVE_AT_SALE","Recipe version must be effective at sale time");
 return Object.freeze({status:"matched",recipeVersion:sale.recipeVersion,recipeSnapshotHash:sale.recipeSnapshotHash});
}

/** Opening readiness requires every mandatory approved check with verified evidence. */
export function evaluateBranchOpeningReadiness(input){
 const checks=input.checks;
 if(!Array.isArray(checks)||!checks.length)fail("BRANCH_OPENING_CHECKS_REQUIRED","Opening checklist is required");
 const missing=checks.filter(c=>c.mandatory===true&&
  (c.status!=="approved"||!c.evidenceReference||c.evidenceVerified!==true)).map(c=>c.key);
 const branchStatus=input.branchStatus;
 if(branchStatus!=="closed"&&branchStatus!=="opening")fail("BRANCH_OPENING_STATUS_INVALID","Branch must be closed or opening");
 return Object.freeze({ready:missing.length===0,status:missing.length?"not_ready":"ready",
  missing:Object.freeze(missing),nextOperatingStatus:missing.length?branchStatus:"open"});
}

/** Compare provider settlement gross/fee/net to approved fee schedule and bank statement. */
export function reconcileProviderSettlement(input){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId");
 const settlement=input.settlement,schedule=input.feeSchedule,bank=input.bankStatement;
 if(!settlement||!schedule||!bank||settlement.tenantId!==tenantId||settlement.branchId!==branchId||
  bank.tenantId!==tenantId||bank.branchId!==branchId)fail("SETTLEMENT_RECONCILIATION_SCOPE_INVALID","Settlement, fee schedule and bank facts must match tenant/branch");
 if(schedule.status!=="approved"||schedule.provider!==settlement.provider||schedule.currency!=="IDR")
  fail("SETTLEMENT_FEE_SCHEDULE_NOT_APPROVED","Approved provider fee schedule is required");
 if(settlement.status!=="settled"||settlement.reconciliationStatus!=="RECONCILED"||
  bank.status!=="matched"||bank.reconciliationStatus!=="RECONCILED")
  fail("SETTLEMENT_SOURCE_UNRECONCILED","Provider settlement and bank statement must be reconciled");
 const gross=Number(settlement.grossIdr),actualFee=Number(settlement.feeIdr),actualNet=Number(settlement.netIdr);
 const fixed=Number(schedule.fixedFeeIdr??0),bps=Number(schedule.feeBasisPoints??0),tolerance=Number(schedule.toleranceIdr??0);
 if([gross,actualFee,actualNet,fixed,bps,tolerance].some(n=>!Number.isSafeInteger(n)||n<0)||bps>10000)
  fail("SETTLEMENT_FEE_VALUE_INVALID","Settlement fee amounts and basis points are invalid");
 const expectedFee=Math.round(gross*bps/10000)+fixed,expectedNet=gross-expectedFee;
 const bankAmount=Number(bank.amountIdr);
 if(!Number.isSafeInteger(bankAmount)||bankAmount<0)fail("SETTLEMENT_BANK_AMOUNT_INVALID","Bank matched amount must be integer IDR");
 const feeVariance=actualFee-expectedFee,netVariance=actualNet-expectedNet,bankVariance=bankAmount-actualNet;
 const matched=Math.abs(feeVariance)<=tolerance&&netVariance===0&&bankVariance===0;
 return Object.freeze({status:matched?"matched":"variance",provider:settlement.provider,grossIdr:gross,
  expectedFeeIdr:expectedFee,actualFeeIdr:actualFee,feeVarianceIdr:feeVariance,expectedNetIdr:expectedNet,
  actualNetIdr:actualNet,bankAmountIdr:bankAmount,bankVarianceIdr:bankVariance});
}

/** Persist production variance with manager review and explicit corrective action. */
export async function publishProductionUsageVariance(input,deps){
 const s=scope(input,"production.usage_variance.publish"),productionRunId=req(input.productionRunId,"productionRunId");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findProductionVarianceByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",varianceId:prior.id});
  const facts=await adapter(deps,"loadTheoreticalAndActualUsageForUpdate")(tx,{...s,productionRunId});
  assertScope(facts,s,"productionUsage");
  const variance=calculateProductionUsageVariance({tenantId:s.tenantId,branchId:s.branchId,
   theoretical:facts.theoretical,actual:facts.actual});
  const saved=await adapter(deps,"persistProductionUsageVariance")(tx,{...s,productionRunId,...variance});
  if(!saved?.id)fail("PRODUCTION_VARIANCE_PERSIST_FAILED","Variance report was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"production.usage_variance.published",entityType:"production_usage_variance",entityId:saved.id});
  return Object.freeze({status:"published",varianceId:saved.id,variance});
 });
}

/** Open a branch only after all checks are approved; transition and audit in one transaction. */
export async function openReadyBranch(input,deps){
 const s=scope(input,"branch.opening.complete"),branchId=s.branchId;
 return txScope(deps,s,async tx=>{
  const branch=await adapter(deps,"loadBranchForOpeningUpdate")(tx,s);assertScope(branch,s,"branch");
  const checks=await adapter(deps,"loadAuthoritativeOpeningChecks")(tx,s);
  const readiness=evaluateBranchOpeningReadiness({branchStatus:branch.operatingStatus,checks});
  if(!readiness.ready)fail("BRANCH_OPENING_NOT_READY","Mandatory opening checks are incomplete or unverified");
  const saved=await adapter(deps,"transitionBranchOperatingStatus")(tx,{...s,branchId,from:branch.operatingStatus,to:"open"});
  if(!saved?.id||saved.operatingStatus!=="open")fail("BRANCH_OPENING_TRANSITION_FAILED","Branch operating status was not opened");
  await adapter(deps,"appendAudit")(tx,{...s,action:"branch.opening.completed",entityType:"branch",entityId:branchId});
  return Object.freeze({status:"open",branchId});
 });
}

/** Publish fee/settlement variance from server-loaded provider and bank evidence. */
export async function publishProviderSettlementReconciliation(input,deps){
 const s=scope(input,"finance.provider_settlement.reconcile"),settlementId=req(input.settlementId,"settlementId");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findProviderSettlementReconciliationByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",reconciliationId:prior.id});
  const facts=await adapter(deps,"loadProviderSettlementReconciliationFacts")(tx,{...s,settlementId});
  assertScope(facts,s,"settlementFacts");
  const result=reconcileProviderSettlement({tenantId:s.tenantId,branchId:s.branchId,
   settlement:facts.settlement,feeSchedule:facts.feeSchedule,bankStatement:facts.bankStatement});
  const saved=await adapter(deps,"persistProviderSettlementReconciliation")(tx,{...s,settlementId,...result});
  if(!saved?.id)fail("SETTLEMENT_RECONCILIATION_PERSIST_FAILED","Provider settlement reconciliation was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"finance.provider_settlement.reconciled",entityType:"finance_provider_settlement_reconciliation",
   entityId:saved.id,metadata:{status:result.status,feeVarianceIdr:result.feeVarianceIdr,bankVarianceIdr:result.bankVarianceIdr}});
  return Object.freeze({status:result.status,reconciliationId:saved.id,result});
 });
}
