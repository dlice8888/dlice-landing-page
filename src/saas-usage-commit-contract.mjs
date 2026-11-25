/**
 * Usage metering contract. Call only after an authoritative business
 * transaction has committed. Persistence and entitlement locking belong in
 * a DB RPC with a unique tenant+idempotency constraint.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
export function buildCommittedUsageEvent({operation,tenantId,sourceType,sourceId,idempotencyKey,committedAt,units,entitlement}) {
 if(!operation||!tenantId||!sourceType||!sourceId||!idempotencyKey)fail("USAGE_SOURCE_REQUIRED","Committed operation and stable source identity are required");
 if(operation.status!=="committed"||!operation.commitRef||!operation.actorId)fail("AUTHORITATIVE_COMMIT_REQUIRED","Usage may only be metered after an authoritative commit");
 if(operation.tenantId!==tenantId||operation.sourceType!==sourceType||operation.sourceId!==sourceId)fail("USAGE_SCOPE_MISMATCH","Usage source does not match committed operation");
 if(!Number.isSafeInteger(units)||units<=0)fail("USAGE_UNITS_INVALID","Usage units must be a positive integer");
 if(!entitlement||entitlement.status!=="active"||!entitlement.features?.includes(operation.featureKey))fail("ENTITLEMENT_DENIED","Tenant entitlement does not permit this operation");
 const at=new Date(committedAt);if(Number.isNaN(at.getTime())||at>new Date())fail("USAGE_TIMESTAMP_INVALID","Usage timestamp must be a valid committed time");
 return Object.freeze({tenantId,featureKey:operation.featureKey,sourceType,sourceId,idempotencyKey,units,committedAt:at.toISOString(),commitRef:operation.commitRef,actorId:operation.actorId,entitlementVersion:entitlement.version,status:"ready_for_atomic_metering"});
}
