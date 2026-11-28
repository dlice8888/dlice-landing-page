/** Refund/void policy checks; posting/reversal must remain atomic and idempotent server operations. */
export function validateRefundRequest({saleId,branchId,requestedBranchId,paidAmountIdr,previouslyRefundedIdr,refundAmountIdr,reason,requestedBy,approvedBy,separationOfDuties=true,returnItems=[],soldQuantities={}}) {
  if(!saleId||!branchId||branchId!==requestedBranchId)throw new Error("refund_branch_mismatch");
  for(const [v,n] of [[paidAmountIdr,"paid_amount"],[previouslyRefundedIdr,"previous_refunds"],[refundAmountIdr,"refund_amount"]])if(!Number.isSafeInteger(v)||v<0)throw new Error(n+"_invalid");
  if(refundAmountIdr===0||previouslyRefundedIdr+refundAmountIdr>paidAmountIdr)throw new Error("refund_exceeds_remaining_paid_amount");
  if(typeof reason!=="string"||reason.trim().length<8)throw new Error("refund_reason_required");
  if(!requestedBy)throw new Error("refund_actor_required");
  if(separationOfDuties&&approvedBy===requestedBy)throw new Error("refund_self_approval_forbidden");
  const returned=returnItems.map(item=>{
    if(!item?.saleItemId||!Number.isInteger(item.quantity)||item.quantity<1)throw new Error("return_item_invalid");
    const sold=soldQuantities[item.saleItemId];
    if(!Number.isInteger(sold)||item.quantity>sold)throw new Error("return_quantity_exceeds_sold");
    return Object.freeze({sale_item_id:item.saleItemId,quantity:item.quantity,restock:item.restock===true});
  });
  return Object.freeze({sale_id:saleId,branch_id:branchId,amount_idr:refundAmountIdr,reason:reason.trim().slice(0,500),return_items:Object.freeze(returned)});
}
export function assertRefundProcessable({status,idempotencyKey,approvalRequired,approved,actorUserId,requestedBy}) {
  if(status!=="approved"&&status!=="requested")throw new Error("refund_not_processable");
  if(approvalRequired&&approved!==true)throw new Error("refund_approval_required");
  if(approvalRequired&&actorUserId===requestedBy)throw new Error("refund_self_approval_forbidden");
  if(typeof idempotencyKey!=="string"||idempotencyKey.trim().length<16)throw new Error("refund_idempotency_key_required");
  return Object.freeze({idempotency_key:idempotencyKey.trim(),process_once:true});
}
