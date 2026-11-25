/**
 * Reconciles supplier AP payments against a posted AP journal and provider settlement.
 * This module never initiates a bank transfer or marks an unreconciled payment paid.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function reconcileSupplierPayment({invoice,apJournal,payment,providerSettlement,previouslyReconciledAmountIdr=0}) {
 if(!invoice?.id||invoice.status!=="approved"||!apJournal?.id||apJournal.sourceId!==invoice.id||apJournal.status!=="posted")fail("POSTED_AP_JOURNAL_REQUIRED","Supplier payment requires an approved invoice and posted AP journal");
 if(apJournal.tenantId!==invoice.tenantId||apJournal.branchId!==invoice.branchId)fail("AP_JOURNAL_SCOPE_MISMATCH","AP journal must match invoice tenant and branch");
 for(const [k,v] of Object.entries({invoiceTotal:invoice.totalIdr,previouslyReconciledAmountIdr}))if(!Number.isSafeInteger(v)||v<0)fail("AP_PAYMENT_AMOUNT_INVALID",k);
 if(!payment?.id||payment.status!=="succeeded"||payment.invoiceId!==invoice.id||payment.providerReference==null)fail("SUPPLIER_PAYMENT_NOT_CONFIRMED","Payment provider must confirm a successful payment with a stable reference");
 if(!providerSettlement||providerSettlement.status!=="reconciled"||providerSettlement.paymentReference!==payment.providerReference)fail("SUPPLIER_SETTLEMENT_NOT_RECONCILED","Provider settlement must reconcile to the payment reference");
 const amountIdr=payment.amountIdr,settledIdr=providerSettlement.settledAmountIdr;
 if(!Number.isSafeInteger(amountIdr)||amountIdr<=0||!Number.isSafeInteger(settledIdr)||settledIdr!==amountIdr)fail("SUPPLIER_PAYMENT_SETTLEMENT_MISMATCH","Payment amount and settled amount must match");
 const paidToDate=previouslyReconciledAmountIdr+amountIdr;
 if(!Number.isSafeInteger(paidToDate)||paidToDate>invoice.totalIdr)fail("SUPPLIER_OVERPAYMENT","Reconciled payments exceed invoice total");
 return Object.freeze({invoiceId:invoice.id,paymentId:payment.id,providerReference:payment.providerReference,paidThisPaymentIdr:amountIdr,paidToDateIdr:paidToDate,outstandingIdr:invoice.totalIdr-paidToDate,status:paidToDate===invoice.totalIdr?"settled":"partially_settled",idempotencyKey:`supplier-payment-reconcile:${invoice.id}:${payment.id}`});
}
