/**
 * Validates supplier return and credit-note candidates against received quantity
 * and an approved invoice. No AP posting or supplier payment is performed.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function buildSupplierReturnCreditNote({invoice,invoiceLine,receivedQuantity,previouslyReturnedQuantity,returnQuantity,unitPriceIdr,reason,approvedBy,receivedBy}) {
 if(!invoice?.id||invoice.status!=="approved"||invoice.matchStatus!=="matched")fail("APPROVED_MATCHED_INVOICE_REQUIRED","Return must reference an approved matched supplier invoice");
 if(!invoiceLine?.id||invoiceLine.invoiceId!==invoice.id)fail("INVOICE_LINE_SCOPE_MISMATCH","Return line must belong to invoice");
 for(const [k,v] of Object.entries({receivedQuantity,previouslyReturnedQuantity,returnQuantity}))if(!Number.isSafeInteger(v)||v<0)fail("RETURN_QUANTITY_INVALID",k);
 if(returnQuantity<=0||previouslyReturnedQuantity+returnQuantity>receivedQuantity)fail("RETURN_EXCEEDS_RECEIVED_QUANTITY","Return quantity exceeds net received quantity");
 if(!Number.isSafeInteger(unitPriceIdr)||unitPriceIdr<=0||typeof reason!=="string"||reason.trim().length<5)fail("RETURN_EVIDENCE_REQUIRED","Unit price and reason are required");
 if(!approvedBy||approvedBy===receivedBy)fail("INDEPENDENT_RETURN_APPROVER_REQUIRED","Return approver must differ from receiver");
 const creditAmountIdr=returnQuantity*unitPriceIdr;
 if(!Number.isSafeInteger(creditAmountIdr)||creditAmountIdr<=0)fail("CREDIT_NOTE_AMOUNT_INVALID","Credit note amount is invalid");
 return Object.freeze({tenantId:invoice.tenantId,branchId:invoice.branchId,supplierId:invoice.supplierId,invoiceId:invoice.id,invoiceLineId:invoiceLine.id,returnQuantity,unitPriceIdr,creditAmountIdr,reason:reason.trim(),approvedBy,status:"approved_pending_ap_credit",paymentStatus:"not_paid",idempotencyKey:`supplier-return:${invoice.id}:${invoiceLine.id}:${previouslyReturnedQuantity+returnQuantity}`});
}
