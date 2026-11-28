/** Blind cycle count variance review and single-post command. */
export function calculateCycleCountVariance({sessionId,itemId,bookQuantity,countedQuantity,expectedVersion,currentVersion,approvedBy,createdBy,threshold,reason}){
 if(!sessionId||!itemId||![bookQuantity,countedQuantity,threshold].every(Number.isFinite)||bookQuantity<0||countedQuantity<0||threshold<0)throw new Error("CYCLE_COUNT_INPUT_INVALID");
 if(expectedVersion!==currentVersion)throw new Error("CYCLE_COUNT_STALE_VERSION");
 const variance=countedQuantity-bookQuantity,requiresApproval=Math.abs(variance)>threshold;
 if(requiresApproval&&(!approvedBy||approvedBy===createdBy))throw new Error("CYCLE_COUNT_DUAL_CONTROL_REQUIRED");
 if(requiresApproval&&(typeof reason!=="string"||reason.trim().length<8))throw new Error("CYCLE_COUNT_REASON_REQUIRED");
 return Object.freeze({session_id:sessionId,item_id:itemId,book_quantity:bookQuantity,counted_quantity:countedQuantity,variance,requires_approval:requiresApproval,approved_by:approvedBy||null,post_once:true});
}
