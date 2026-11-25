/** Supplier payment and AP settlement reconciliation after payment execution. */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function reconcileSupplierPayment({invoice,payment,settlements,apJournal}) {
 if(!invoice?.id||invoice.status!=="approved"||invoice.matchStatus!=="matched")fail("APPROVED_MATCHED_INVOICE_REQUIRED","Approved matched invoice required");
 if(!payment?.id||payment.invoiceId!==invoice.id||payment.status!=="executed")fail("SUPPLIER_PAYMENT_NOT_EXECUTED","Payment must have executed");
 if(!apJournal||apJournal.sourceId!==invoice.id||apJournal.status!=="posted"||apJournal.reconciled!==true)fail("AP_JOURNAL_NOT_RECONCILED","AP journal must be posted and reconciled");
 if(!Array.isArray(settlements)||!settlements.length)fail("SUPPLIER_SETTLEMENTS_REQUIRED","Final supplier settlement evidence required");
 const seen=new Set();let total=0;for(const s of settlements){if(!s.reference||seen.has(s.reference)||s.paymentId!==payment.id||s.status!=="settled"||!Number.isSafeInteger(s.amountIdr)||s.amountIdr<=0)fail("SUPPLIER_SETTLEMENT_INVALID","Settlement must be unique, final and linked");seen.add(s.reference);total+=s.amountIdr;}
 if(total!==invoice.totalIdr||payment.amountIdr!==invoice.totalIdr)fail("SUPPLIER_PAYMENT_AMOUNT_MISMATCH","Payment and settlement must equal approved invoice amount");
 return Object.freeze({invoiceId:invoice.id,paymentId:payment.id,settlementCount:settlements.length,settledAmountIdr:total,status:"reconciled"});
}
