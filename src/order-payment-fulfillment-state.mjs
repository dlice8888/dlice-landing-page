/** Independent order, payment and fulfilment state machines. */
const transitions={
 order:{received:["confirmed","cancelled"],confirmed:["preparing","cancelled"],preparing:["ready","cancelled"],ready:["completed","cancelled"],completed:[],cancelled:[]},
 payment:{unpaid:["pending","cancelled"],pending:["paid","failed","cancelled"],failed:["pending","cancelled"],paid:["refunded","partially_refunded"],partially_refunded:["refunded"],refunded:[],cancelled:[]},
 fulfillment:{unassigned:["queued","cancelled"],queued:["accepted","cancelled"],accepted:["preparing","failed","cancelled"],preparing:["ready","failed","cancelled"],ready:["dispatched","fulfilled","cancelled"],dispatched:["fulfilled","failed"],failed:["queued","cancelled"],fulfilled:[],cancelled:[]}
};
const owner={order:new Set(["order_service","branch_manager","supervisor"]),payment:new Set(["payment_service","trusted_provider","finance"]),fulfillment:new Set(["kitchen","delivery","branch_manager","supervisor"])};
export function assertLifecycleTransition({axis,from,to,actorDomain,expectedVersion,currentVersion,eventId}) {
  if(!Object.hasOwn(transitions,axis))throw new Error("lifecycle_axis_invalid");
  if(!transitions[axis][from]?.includes(to))throw new Error("lifecycle_transition_invalid");
  if(!owner[axis].has(actorDomain))throw new Error("lifecycle_actor_forbidden");
  if(!eventId||typeof eventId!=="string")throw new Error("lifecycle_event_id_required");
  if(expectedVersion!==currentVersion)throw new Error("lifecycle_stale_version");
  return Object.freeze({axis,from,to,event_id:eventId,append_only:true});
}
export function assertLifecycleConsistency({orderStatus,paymentStatus,fulfillmentStatus}) {
  if(paymentStatus==="paid"&&orderStatus==="cancelled"&&fulfillmentStatus!=="cancelled"&&fulfillmentStatus!=="failed")throw new Error("paid_cancelled_order_requires_compensation");
  if(paymentStatus==="refunded"&&orderStatus!=="cancelled")throw new Error("refunded_order_must_be_cancelled_or_exceptioned");
  if(fulfillmentStatus==="fulfilled"&&orderStatus!=="completed")throw new Error("fulfilled_order_must_be_completed");
  return true;
}
export const LIFECYCLE_TRANSITIONS=Object.freeze(transitions);
