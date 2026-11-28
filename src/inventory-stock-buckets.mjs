/** Available/reserved/in-transit/blocked bucket invariants. */
export function reconcileStockBuckets({onHand,available,reserved,inTransit,blocked}){
 const values=[onHand,available,reserved,inTransit,blocked];if(!values.every(x=>Number.isFinite(x)&&x>=0))throw new Error("STOCK_BUCKET_VALUE_INVALID");
 if(Math.abs(onHand-(available+reserved+inTransit+blocked))>0.000001)throw new Error("STOCK_BUCKET_TOTAL_MISMATCH");
 return Object.freeze({on_hand:onHand,available,reserved,in_transit:inTransit,blocked,reconciled:true});
}
export function buildStockReservation({quantity,available,stockVersion,expectedVersion,idempotencyKey}){
 if(!Number.isFinite(quantity)||quantity<=0||!Number.isFinite(available)||quantity>available)throw new Error("STOCK_RESERVATION_UNAVAILABLE");
 if(stockVersion!==expectedVersion)throw new Error("STOCK_RESERVATION_STALE_VERSION");
 if(typeof idempotencyKey!=="string"||idempotencyKey.trim().length<16)throw new Error("STOCK_RESERVATION_IDEMPOTENCY_REQUIRED");
 return Object.freeze({quantity,expected_version:expectedVersion,idempotency_key:idempotencyKey.trim(),atomic:true});
}
