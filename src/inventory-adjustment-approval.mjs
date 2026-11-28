/** Dual-control stock adjustment policy with immutable audit linkage. */
export function validateInventoryAdjustment({tenantId,branchId,itemId,quantity,direction,reason,requestedBy,approvedBy,thresholdQuantity,sourceEvidenceId,idempotencyKey}){
 if(!tenantId||!branchId||!itemId||!requestedBy||!Number.isFinite(quantity)||quantity<=0||!["in","out"].includes(direction))throw new Error("INVENTORY_ADJUSTMENT_INPUT_INVALID");
 if(typeof reason!=="string"||reason.trim().length<8)throw new Error("INVENTORY_ADJUSTMENT_REASON_REQUIRED");
 if(!Number.isFinite(thresholdQuantity)||thresholdQuantity<0)throw new Error("INVENTORY_ADJUSTMENT_THRESHOLD_INVALID");
 const requiresApproval=quantity>thresholdQuantity;
 if(requiresApproval&&(!approvedBy||approvedBy===requestedBy))throw new Error("INVENTORY_ADJUSTMENT_DUAL_CONTROL_REQUIRED");
 if(typeof idempotencyKey!=="string"||idempotencyKey.trim().length<16)throw new Error("INVENTORY_ADJUSTMENT_IDEMPOTENCY_REQUIRED");
 if(!sourceEvidenceId)throw new Error("INVENTORY_ADJUSTMENT_EVIDENCE_REQUIRED");
 return Object.freeze({tenant_id:tenantId,branch_id:branchId,item_id:itemId,quantity,direction,reason:reason.trim().slice(0,500),requested_by:requestedBy,approved_by:approvedBy||null,requires_approval:requiresApproval,evidence_id:sourceEvidenceId,idempotency_key:idempotencyKey.trim(),audit_required:true});
}
