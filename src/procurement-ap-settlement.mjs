/**
 * Supplier AP settlement reconciliation gate. Three-way match/approval alone
 * never constitutes payment or settlement.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const money=(n,k)=>{if(!Number.isSafeInteger(n)||n<0)fail("AP_AMOUNT_INVALID",k);return n;};
export function reconcileSupplierPayment({invoice,approval,journal,payment,bankSettlement,creditNotes=[]}) {
 if(!invoice?.id||invoice.status!=="approved")fail("APPROVED_INVOICE_REQUIRED","Invoice must be approved after three-way match");
 if(!approval?.approvedBy||approval.approvedBy===invoice.createdBy||!approval.approvedAt)fail("INDEPENDENT_AP_APPROVAL_REQUIRED","AP approval must be independent from invoice creator");
 if(!journal||journal.status!=="posted"||journal.sourceId!==invoice.id||journal.debitIdr!==journal.creditIdr||!journal.batchId)fail("AP_JOURNAL_NOT_POSTED","Balanced posted AP journal batch is required");
 if(!payment||payment.status!=="executed"||!payment.providerReference||!payment.executedAt)fail("PAYMENT_NOT_EXECUTED","Executed payment with provider reference is required");
 if(!bankSettlement||bankSettlement.status!=="reconciled"||bankSettlement.paymentReference!==payment.providerReference||!bankSettlement.reconciledAt)fail("SUPPLIER_SETTLEMENT_NOT_RECONCILED","Bank/provider settlement must reconcile to executed payment");
 const invoiceAmount=money(invoice.totalIdr,"invoice.totalIdr");
 for(const note of creditNotes){if(note.invoiceId!==invoice.id||note.status!=="approved"||!note.id)fail("CREDIT_NOTE_NOT_APPROVED","Every credit note must be approved and linked");money(note.amountIdr,"creditNote.amountIdr");}
 const credits=creditNotes.reduce((s,x)=>s+x.amountIdr,0);
 if(credits>invoiceAmount)fail("CREDIT_NOTES_EXCEED_INVOICE","Credit notes exceed invoice total");
 const payable=invoiceAmount-credits;
 if(money(payment.amountIdr,"payment.amountIdr")!==payable||money(bankSettlement.amountIdr,"bankSettlement.amountIdr")!==payable)fail("AP_PAYMENT_AMOUNT_MISMATCH","Payment and settlement must equal invoice less approved credit notes");
 return Object.freeze({invoiceId:invoice.id,payableIdr:payable,creditNotesIdr:credits,journalBatchId:journal.batchId,paymentReference:payment.providerReference,settlementId:bankSettlement.id,status:"reconciled"});
}
