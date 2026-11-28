/** Cancellation and customer-history authorization/compensation contract. */
export function validateOrderCancellation({order,actor,customerId,reason,alreadyCancelled=false,refundRequired=false,refundIdempotencyKey,compensationAdaptersReady=false}){
 if(!order?.id||!actor?.user_id)throw new Error("ORDER_CANCEL_CONTEXT_REQUIRED");
 if(actor.kind==="customer"&&order.customer_id!==customerId)throw new Error("ORDER_HISTORY_CUSTOMER_FORBIDDEN");
 if(actor.kind==="staff"&&!actor.allowed_branch_ids?.includes(order.branch_id))throw new Error("ORDER_CANCEL_BRANCH_FORBIDDEN");
 if(alreadyCancelled||order.order_status==="cancelled")throw new Error("ORDER_ALREADY_CANCELLED");
 if(!["received","confirmed","preparing","ready"].includes(order.order_status))throw new Error("ORDER_CANCEL_STATE_FORBIDDEN");
 if(typeof reason!=="string"||reason.trim().length<8)throw new Error("ORDER_CANCEL_REASON_REQUIRED");
 if(order.payment_status==="paid"&&(!refundRequired||!compensationAdaptersReady||typeof refundIdempotencyKey!=="string"||refundIdempotencyKey.trim().length<16))throw new Error("ORDER_CANCEL_REFUND_COMPENSATION_REQUIRED");
 return Object.freeze({order_id:order.id,branch_id:order.branch_id,requested_by:actor.user_id,reason:reason.trim().slice(0,500),refund_required:order.payment_status==="paid",requires_inventory_compensation:order.fulfillment_status==="preparing"||order.fulfillment_status==="ready",idempotency_key:refundIdempotencyKey||null});
}
export function buildCustomerOrderHistory({orders,customerId,actor}){
 if(actor?.kind!=="customer"||!actor.user_id||!customerId||actor.user_id!==customerId)throw new Error("ORDER_HISTORY_CUSTOMER_FORBIDDEN");
 return (orders||[]).filter(o=>o.customer_id===customerId).sort((a,b)=>Date.parse(b.created_at)-Date.parse(a.created_at)).map(o=>Object.freeze({id:o.id,order_number:o.order_number,created_at:o.created_at,order_status:o.order_status,payment_status:o.payment_status,fulfillment_status:o.fulfillment_status,refund_status:o.refund_status||null}));
}
