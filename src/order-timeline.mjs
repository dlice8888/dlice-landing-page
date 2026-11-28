/** Append-only order event contract with monotonic version and idempotent source IDs. */
const transitions={received:["confirmed","cancelled"],confirmed:["preparing","cancelled"],preparing:["ready","cancelled"],ready:["completed","cancelled"],completed:[],cancelled:[]};
export function appendOrderTimelineEvent({orderId,tenantId,branchId,fromStatus,toStatus,actorDomain,actorId,expectedVersion,currentVersion,sourceEventId,occurredAt,existingSourceEventIds=[]}){
 if(!orderId||!tenantId||!branchId||!actorDomain||!sourceEventId)throw new Error("ORDER_TIMELINE_CONTEXT_REQUIRED");
 if(existingSourceEventIds.includes(sourceEventId))return Object.freeze({duplicate:true,append:false,source_event_id:sourceEventId});
 if(expectedVersion!==currentVersion)throw new Error("ORDER_TIMELINE_STALE_VERSION");
 if(!transitions[fromStatus]?.includes(toStatus))throw new Error("ORDER_TIMELINE_TRANSITION_INVALID");
 const domains={received:["pos","online_channel"],confirmed:["branch","system"],preparing:["kitchen","branch"],ready:["kitchen"],completed:["branch","customer"],cancelled:["branch","customer","system"]};
 if(!domains[toStatus]?.includes(actorDomain))throw new Error("ORDER_TIMELINE_ACTOR_FORBIDDEN");
 if(!Number.isFinite(Date.parse(occurredAt)))throw new Error("ORDER_TIMELINE_TIMESTAMP_INVALID");
 return Object.freeze({order_id:orderId,tenant_id:tenantId,branch_id:branchId,from_status:fromStatus,to_status:toStatus,actor_domain:actorDomain,actor_id:actorId||null,source_event_id:sourceEventId,occurred_at:occurredAt,version:currentVersion+1,append_only:true,duplicate:false});
}
