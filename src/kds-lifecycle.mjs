/** Kitchen item lifecycle with receiver acknowledgement at handover. */
const next={waiting:["in_progress"],in_progress:["ready"],ready:["handed_over"],handed_over:[],cancelled:[]};
export function transitionKitchenItem({item,actor,assignedStationIds,toStatus,expectedVersion,eventId,receiverUserId,acknowledged=false,now}){
 if(!item?.id||!actor?.user_id||!eventId)throw new Error("KDS_TRANSITION_CONTEXT_REQUIRED");
 if(item.version!==expectedVersion)throw new Error("KDS_TRANSITION_STALE_VERSION");
 if(!next[item.status]?.includes(toStatus))throw new Error("KDS_TRANSITION_INVALID");
 if(!assignedStationIds?.includes(item.station_id)||actor.branch_id!==item.branch_id)throw new Error("KDS_STATION_SCOPE_FORBIDDEN");
 if(toStatus==="handed_over"&&(!receiverUserId||receiverUserId===actor.user_id||acknowledged!==true))throw new Error("KDS_HANDOVER_ACK_REQUIRED");
 if(!Number.isFinite(Date.parse(now)))throw new Error("KDS_TRANSITION_TIMESTAMP_INVALID");
 return Object.freeze({item_id:item.id,from_status:item.status,to_status:toStatus,actor_user_id:actor.user_id,receiver_user_id:receiverUserId||null,event_id:eventId,version:expectedVersion+1,occurred_at:now,append_only:true});
}
