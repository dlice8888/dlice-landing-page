/**
 * Tenant-governed integration connector, health and catalog synchronization workflows.
 * Credentials are secret references only and are never returned to callers.
 */
const fail=(code,message)=>{const error=new Error(message);error.code=code;throw error;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("INTEGRATION_INPUT_REQUIRED",f);return v.trim();};
const adapter=(deps,name)=>{if(typeof deps?.[name]!=="function")fail("INTEGRATION_ADAPTER_REQUIRED",name);return deps[name];};
const scope=(input,action)=>({tenantId:req(input?.tenantId,"tenantId"),branchId:input?.branchId==null?null:req(input.branchId,"branchId"),
 actorId:req(input?.actorId,"actorId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),action});
const txScope=(deps,s,fn)=>adapter(deps,"withTenantTransaction")(s,async tx=>{
 if(!tx)fail("INTEGRATION_TRANSACTION_REQUIRED","Database transaction required");
 await adapter(deps,"authorize")(tx,s);return fn(tx);
});
const assertTenant=(row,s,name)=>{if(!row||row.tenantId!==s.tenantId||(s.branchId&&row.branchId!==s.branchId))fail("INTEGRATION_SCOPE_MISMATCH",name);};

/** Approve/resolve connector metadata without exposing credential material. */
export async function resolveApprovedConnector(input,deps){
 const s=scope(input,"integrations.connector.resolve"),providerKey=req(input.providerKey,"providerKey");
 return txScope(deps,s,async tx=>{
  const config=await adapter(deps,"loadApprovedConnectorConfig")(tx,{...s,providerKey});
  assertTenant(config,s,"connector");
  if(config.status!=="approved"||config.enabled!==true)fail("INTEGRATION_CONNECTOR_NOT_APPROVED","Connector must be approved and enabled");
  if(!config.credentialSecretReference||typeof config.credentialSecretReference!=="string")fail("INTEGRATION_SECRET_REFERENCE_REQUIRED","A vault secret reference is required");
  const requested=Array.isArray(input.capabilities)?input.capabilities:[];
  const allowed=new Set(config.approvedCapabilities||[]);
  if(requested.some(cap=>!allowed.has(cap)))fail("INTEGRATION_CAPABILITY_NOT_APPROVED","Requested provider capability is not approved");
  const resolved=await adapter(deps,"resolveVaultSecretReference")(tx,{tenantId:s.tenantId,secretReference:config.credentialSecretReference});
  if(!resolved?.available)fail("INTEGRATION_SECRET_UNAVAILABLE","Approved secret reference is unavailable");
  return Object.freeze({connectorId:config.id,providerKey,capabilities:Object.freeze(requested),
   credentialAvailable:true});
 });
}

/** Classify provider health from persisted observations and queue telemetry. */
export function evaluateIntegrationHealth(input){
 const lastSuccess=Date.parse(input.lastSuccessAt),now=Date.parse(input.now);
 const errorRate=Number(input.errorRatePct),queueLag=Number(input.queueLagMinutes);
 const staleAfter=Number(input.staleAfterMinutes??30),maxError=Number(input.maxErrorRatePct??5),maxLag=Number(input.maxQueueLagMinutes??15);
 if(!Number.isFinite(now)||!Number.isFinite(errorRate)||!Number.isFinite(queueLag)||errorRate<0||errorRate>100||queueLag<0||
    !Number.isFinite(staleAfter)||staleAfter<=0||!Number.isFinite(maxError)||maxError<0||!Number.isFinite(maxLag)||maxLag<0)
  fail("INTEGRATION_HEALTH_METRIC_INVALID","Health telemetry is invalid");
 const stale=!Number.isFinite(lastSuccess)||now-lastSuccess>staleAfter*60000;
 const unhealthy=stale||errorRate>maxError||queueLag>maxLag;
 const degraded=!unhealthy&&(errorRate>0||queueLag>0);
 return Object.freeze({status:unhealthy?"unhealthy":degraded?"degraded":"healthy",stale,errorRatePct:errorRate,
  queueLagMinutes:queueLag,alertRequired:unhealthy||degraded});
}

/** Persist health observation and create a durable alert when provider health is degraded. */
export async function recordIntegrationHealth(input,deps){
 const s=scope(input,"integrations.health.record"),connectorId=req(input.connectorId,"connectorId");
 return txScope(deps,s,async tx=>{
  const connector=await adapter(deps,"loadConnectorForUpdate")(tx,{...s,connectorId});assertTenant(connector,s,"connector");
  const telemetry=await adapter(deps,"loadAuthoritativeIntegrationHealthTelemetry")(tx,{...s,connectorId});
  if(!telemetry||telemetry.tenantId!==s.tenantId)fail("INTEGRATION_HEALTH_TELEMETRY_SCOPE_INVALID","Health telemetry must be loaded from tenant-scoped persisted observations");
  const health=evaluateIntegrationHealth(telemetry);
  const saved=await adapter(deps,"persistIntegrationHealthObservation")(tx,{...s,connectorId,...health,
   checkedAt:req(telemetry.now,"telemetry.now")});
  if(!saved?.id)fail("INTEGRATION_HEALTH_PERSIST_FAILED","Health observation was not persisted");
  let alertId=null;
  if(health.alertRequired){
   const alert=await adapter(deps,"upsertIntegrationHealthAlert")(tx,{...s,connectorId,healthObservationId:saved.id,status:health.status});
   if(!alert?.id)fail("INTEGRATION_HEALTH_ALERT_FAILED","Degraded integration must create or update a durable alert");
   alertId=alert.id;
  }
  await adapter(deps,"appendAudit")(tx,{...s,action:"integrations.health.recorded",entityType:"integration_health_observation",
   entityId:saved.id,metadata:{status:health.status,alertId}});
  return Object.freeze({status:health.status,observationId:saved.id,alertId});
 });
}

/** Validate a catalog sync batch before any write; duplicate external keys fail closed. */
export function prepareCatalogSyncBatch(input){
 const tenantId=req(input?.tenantId,"tenantId"),source=req(input?.source,"source");
 if(!Array.isArray(input.records)||!input.records.length)fail("INTEGRATION_CATALOG_BATCH_EMPTY","Catalog batch must contain records");
 const seen=new Set(),records=[];
 for(const row of input.records){
  if(row.tenantId!==tenantId)fail("INTEGRATION_SCOPE_MISMATCH","Catalog row belongs to another tenant");
  const externalId=req(row.externalId,"externalId"),name=req(row.name,"name"),sku=req(row.sku,"sku");
  if(seen.has(externalId))fail("INTEGRATION_CATALOG_DUPLICATE_EXTERNAL_ID","Duplicate external ID in batch");
  seen.add(externalId);
  const price=Number(row.priceIdr);
  if(!Number.isSafeInteger(price)||price<0)fail("INTEGRATION_CATALOG_PRICE_INVALID","Price must be a non-negative integer IDR");
  records.push(Object.freeze({tenantId,externalId,name,sku,priceIdr:price,active:row.active!==false}));
 }
 return Object.freeze({tenantId,source,sourceRevision:req(input.sourceRevision,"sourceRevision"),
  conflictPolicy:input.conflictPolicy??"reject",records:Object.freeze(records)});
}

/** Apply catalog sync atomically, with a durable checkpoint and no silent conflicts. */
export async function applyCatalogSyncBatch(input,deps){
 const s=scope(input,"integrations.catalog_sync.apply"),importBatchId=req(input.importBatchId,"importBatchId");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findCatalogSyncByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",syncId:prior.id});
  const verified=await adapter(deps,"loadVerifiedCatalogImportBatch")(tx,{...s,importBatchId});
  assertTenant(verified,s,"verifiedImportBatch");
  const batch=prepareCatalogSyncBatch(verified);
  if(!["reject","update_if_newer"].includes(batch.conflictPolicy))fail("INTEGRATION_CONFLICT_POLICY_INVALID","Unsupported conflict policy");
  const source=await adapter(deps,"loadApprovedCatalogSource")(tx,{...s,source:batch.source});
  assertTenant(source,s,"catalogSource");
  if(source.status!=="approved"||source.enabled!==true)fail("INTEGRATION_CATALOG_SOURCE_NOT_APPROVED","Catalog source must be approved");
  const conflicts=await adapter(deps,"findCatalogSyncConflicts")(tx,{...s,records:batch.records,conflictPolicy:batch.conflictPolicy});
  if(!Array.isArray(conflicts))fail("INTEGRATION_CONFLICT_CHECK_REQUIRED","Conflict detection must return an array");
  if(conflicts.length&&batch.conflictPolicy==="reject")fail("INTEGRATION_CATALOG_CONFLICTS_FOUND","Catalog conflicts must be resolved before applying");
  const applied=await adapter(deps,"applyCatalogSyncRecordsAtomically")(tx,{...s,batch,conflicts});
  if(!applied?.syncId||applied.appliedCount!==batch.records.length)fail("INTEGRATION_CATALOG_APPLY_INCOMPLETE","All catalog records must commit atomically");
  await adapter(deps,"persistCatalogSyncCheckpoint")(tx,{...s,syncId:applied.syncId,sourceRevision:batch.sourceRevision});
  await adapter(deps,"appendAudit")(tx,{...s,action:"integrations.catalog_sync.applied",entityType:"integration_catalog_sync",
   entityId:applied.syncId,metadata:{recordCount:applied.appliedCount,sourceRevision:batch.sourceRevision}});
  return Object.freeze({status:"applied",syncId:applied.syncId,appliedCount:applied.appliedCount});
 });
}
