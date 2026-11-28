/** KDS dispatch and station-scoped ticket claiming contract. */
export function dispatchKitchenTicket({order,items,stations,branchId,idempotencyKey}){
 if(!order?.id||order.branch_id!==branchId||!Array.isArray(items)||!items.length)throw new Error("KDS_SOURCE_ORDER_INVALID");
 if(typeof idempotencyKey!=="string"||idempotencyKey.trim().length<16)throw new Error("KDS_IDEMPOTENCY_REQUIRED");
 const active=(stations||[]).filter(s=>s.branch_id===branchId&&s.is_active===true);
 const tickets=[];
 for(const item of items){const station=active.find(s=>(s.product_ids||[]).includes(item.product_id)||(s.category_ids||[]).includes(item.category_id));if(!station)throw new Error("KDS_STATION_NOT_CONFIGURED");tickets.push(Object.freeze({order_id:order.id,branch_id:branchId,station_id:station.id,sale_item_id:item.id,quantity:item.quantity,status:"waiting",source_version:order.version}));}
 return Object.freeze({idempotency_key:idempotencyKey.trim(),tickets:Object.freeze(tickets)});
}
export function claimKitchenTicket({ticket,actor,assignedStationIds,expectedVersion}){
 if(!ticket?.id||ticket.status!=="waiting")throw new Error("KDS_TICKET_NOT_WAITING");
 if(!actor?.user_id||!assignedStationIds?.includes(ticket.station_id)||actor.branch_id!==ticket.branch_id)throw new Error("KDS_STATION_SCOPE_FORBIDDEN");
 if(ticket.version!==expectedVersion)throw new Error("KDS_TICKET_STALE_VERSION");
 return Object.freeze({ticket_id:ticket.id,claimed_by:actor.user_id,expected_version:expectedVersion,next_status:"in_progress"});
}
