/**
 * Server-side post-commit usage metering coordinator.
 * Metering failure is surfaced for durable retry/outbox handling; it never
 * converts an uncommitted operation into billable usage.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export async function recordUsageAfterAuthoritativeCommit({operationResult,tenantId,entitlementKey,quantity=1,sourceEntity,sourceId,idempotencyKey,occurredAt,recordUsage}) {
 if(!operationResult||operationResult.committed!==true||!operationResult.commitId)fail("AUTHORITATIVE_COMMIT_REQUIRED","Usage can only be metered after an authoritative commit");
 if(!tenantId||!entitlementKey||!sourceEntity||!sourceId||!idempotencyKey||!occurredAt)fail("USAGE_SOURCE_IDENTITY_REQUIRED","Tenant, entitlement, source and idempotency identities are required");
 if(!Number.isSafeInteger(quantity)||quantity<=0)fail("USAGE_QUANTITY_INVALID","Usage quantity must be a positive integer");
 if(typeof recordUsage!=="function")fail("USAGE_METER_ADAPTER_REQUIRED","Server-side saas_record_usage adapter is required");
 try {
  const result=await recordUsage({tenantId,entitlementKey,quantity,sourceEntity,sourceId,idempotencyKey,occurredAt,metadata:{commitId:operationResult.commitId}});
  if(!result||!result.usage_event_id)fail("USAGE_METER_RESULT_INVALID","Usage RPC did not return a persisted event id");
  return Object.freeze({metered:true,usageEventId:result.usage_event_id,duplicate:result.duplicate===true,commitId:operationResult.commitId});
 } catch(error) {
  error.meteringRetryRequired=true;
  error.authoritativeCommitId=operationResult.commitId;
  throw error;
 }
}
