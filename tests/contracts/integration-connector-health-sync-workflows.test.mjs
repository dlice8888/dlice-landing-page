import test from "node:test";
import assert from "node:assert/strict";
import {
 resolveApprovedConnector,evaluateIntegrationHealth,recordIntegrationHealth,
 prepareCatalogSyncBatch,applyCatalogSyncBatch,
} from "../../src/integration-connector-health-sync-workflows.mjs";

const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"integration-admin",idempotencyKey:"integration-flow-0001"};
const common=(overrides={})=>({
 withTenantTransaction:async(_s,fn)=>fn({tx:true}),
 authorize:async(_tx,s)=>{assert.equal(s.tenantId,"tenant-a");},
 appendAudit:async(_tx,e)=>{assert.ok(e.action.startsWith("integrations."));},
 ...overrides,
});
const verifiedBatch={tenantId:"tenant-a",branchId:"branch-a",source:"catalog-provider-a",sourceRevision:"rev-42",conflictPolicy:"reject",
 records:[{tenantId:"tenant-a",externalId:"sku-1",name:"Flour",sku:"FLR-1",priceIdr:12000}]};

test("connector resolution requires approved capabilities and a vault secret reference without returning it",async()=>{
 const deps=common({
  loadApprovedConnectorConfig:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"connector-a",status:"approved",enabled:true,
   credentialSecretReference:"vault://tenant-a/provider-a",approvedCapabilities:["catalog.read","orders.write"]}),
  resolveVaultSecretReference:async(_tx,row)=>{assert.equal(row.secretReference,"vault://tenant-a/provider-a");return{available:true};},
 });
 const result=await resolveApprovedConnector({...base,providerKey:"provider-a",capabilities:["catalog.read"]},deps);
 assert.deepEqual(result,{connectorId:"connector-a",providerKey:"provider-a",capabilities:["catalog.read"],credentialAvailable:true});
 assert.equal("credentialSecretReference" in result,false);
});
test("connector resolution rejects unapproved capabilities",async()=>{
 const deps=common({loadApprovedConnectorConfig:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"connector-a",
  status:"approved",enabled:true,credentialSecretReference:"vault://secret",approvedCapabilities:["catalog.read"]})});
 await assert.rejects(resolveApprovedConnector({...base,providerKey:"provider-a",capabilities:["payments.write"]},deps),
  {code:"INTEGRATION_CAPABILITY_NOT_APPROVED"});
});
test("integration health distinguishes healthy degraded and unhealthy providers",()=>{
 const healthy=evaluateIntegrationHealth({lastSuccessAt:"2026-11-27T09:55:00Z",now:"2026-11-27T10:00:00Z",errorRatePct:0,queueLagMinutes:0});
 assert.equal(healthy.status,"healthy");assert.equal(healthy.alertRequired,false);
 const degraded=evaluateIntegrationHealth({lastSuccessAt:"2026-11-27T09:55:00Z",now:"2026-11-27T10:00:00Z",errorRatePct:2,queueLagMinutes:1});
 assert.equal(degraded.status,"degraded");assert.equal(degraded.alertRequired,true);
 const unhealthy=evaluateIntegrationHealth({lastSuccessAt:"2026-11-27T09:00:00Z",now:"2026-11-27T10:00:00Z",errorRatePct:1,queueLagMinutes:1});
 assert.equal(unhealthy.status,"unhealthy");
});
test("health recording uses persisted authoritative telemetry and opens a durable alert",async()=>{
 const deps=common({
  loadConnectorForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"connector-a"}),
  loadAuthoritativeIntegrationHealthTelemetry:async()=>({tenantId:"tenant-a",lastSuccessAt:"2026-11-27T09:00:00Z",
   now:"2026-11-27T10:00:00Z",errorRatePct:1,queueLagMinutes:1}),
  persistIntegrationHealthObservation:async(_tx,row)=>{assert.equal(row.status,"unhealthy");return{id:"health-a"};},
  upsertIntegrationHealthAlert:async(_tx,row)=>{assert.equal(row.healthObservationId,"health-a");return{id:"alert-a"};},
 });
 const result=await recordIntegrationHealth({...base,connectorId:"connector-a"},deps);
 assert.deepEqual(result,{status:"unhealthy",observationId:"health-a",alertId:"alert-a"});
});
test("catalog import batch rejects duplicate external keys and cross-tenant rows",()=>{
 assert.throws(()=>prepareCatalogSyncBatch({...verifiedBatch,records:[...verifiedBatch.records,...verifiedBatch.records]}),
  {code:"INTEGRATION_CATALOG_DUPLICATE_EXTERNAL_ID"});
 assert.throws(()=>prepareCatalogSyncBatch({...verifiedBatch,records:[{...verifiedBatch.records[0],tenantId:"tenant-b"}]}),
  {code:"INTEGRATION_SCOPE_MISMATCH"});
});
test("catalog sync applies only verified approved source batches atomically",async()=>{
 const deps=common({
  findCatalogSyncByIdempotencyKey:async()=>null,
  loadVerifiedCatalogImportBatch:async()=>verifiedBatch,
  loadApprovedCatalogSource:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"approved",enabled:true}),
  findCatalogSyncConflicts:async()=>[],
  applyCatalogSyncRecordsAtomically:async(_tx,row)=>{assert.equal(row.batch.records.length,1);return{syncId:"sync-a",appliedCount:1};},
  persistCatalogSyncCheckpoint:async(_tx,row)=>{assert.equal(row.sourceRevision,"rev-42");},
 });
 const result=await applyCatalogSyncBatch({...base,importBatchId:"import-a"},deps);
 assert.deepEqual(result,{status:"applied",syncId:"sync-a",appliedCount:1});
});
test("catalog sync rejects conflicts before any mutation",async()=>{
 let applied=false;
 const deps=common({
  findCatalogSyncByIdempotencyKey:async()=>null,loadVerifiedCatalogImportBatch:async()=>verifiedBatch,
  loadApprovedCatalogSource:async()=>({tenantId:"tenant-a",branchId:"branch-a",status:"approved",enabled:true}),
  findCatalogSyncConflicts:async()=>[{externalId:"sku-1",reason:"stale"}],
  applyCatalogSyncRecordsAtomically:async()=>{applied=true;return{syncId:"sync",appliedCount:1};},
 });
 await assert.rejects(applyCatalogSyncBatch({...base,importBatchId:"import-a"},deps),{code:"INTEGRATION_CATALOG_CONFLICTS_FOUND"});
 assert.equal(applied,false);
});
