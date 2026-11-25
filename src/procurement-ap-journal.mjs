/**
 * Three-way matched supplier invoice -> balanced AP journal draft.
 * No payment is initiated and no invoice is considered settled here.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
const acct=(x,k)=>{if(typeof x!=="string"||!x.trim())fail("AP_ACCOUNT_MAPPING_REQUIRED",k);return x.trim();};
const money=(x,k)=>{if(!Number.isSafeInteger(x)||x<=0)fail("AP_AMOUNT_INVALID",k);return x;};
export function buildSupplierInvoiceApJournal({invoice,lines,accountMapping,idempotencyKey}) {
 if(!invoice?.id||!invoice.tenantId||!invoice.branchId||invoice.status!=="approved"||invoice.matchStatus!=="matched")fail("APPROVED_MATCHED_INVOICE_REQUIRED","Invoice must be approved after clean three-way match");
 if(!Array.isArray(lines)||!lines.length||lines.some(l=>l.matchStatus!=="matched"))fail("THREE_WAY_MATCH_LINES_REQUIRED","All invoice lines must be matched");
 if(!idempotencyKey||idempotencyKey.length<8)fail("AP_IDEMPOTENCY_KEY_REQUIRED","Stable AP idempotency key is required");
 const mapping=accountMapping??{},expense=acct(mapping.inventoryOrExpense,"inventoryOrExpense"),ap=acct(mapping.accountsPayable,"accountsPayable");
 const journalLines=[];let total=0;
 for(const l of lines){const amountIdr=money(l.lineTotalIdr,"lineTotalIdr");total+=amountIdr;journalLines.push({lineNo:journalLines.length+1,accountCode:expense,side:"debit",amountIdr,sourceLineId:l.id});}
 if(total!==invoice.totalIdr)fail("AP_INVOICE_TOTAL_MISMATCH","Matched invoice line total differs from invoice header total");
 journalLines.push({lineNo:journalLines.length+1,accountCode:ap,side:"credit",amountIdr:total,sourceLineId:null});
 const debit=journalLines.filter(l=>l.side==="debit").reduce((s,l)=>s+l.amountIdr,0),credit=journalLines.filter(l=>l.side==="credit").reduce((s,l)=>s+l.amountIdr,0);
 if(debit!==credit)fail("AP_JOURNAL_UNBALANCED","AP journal debits and credits must balance");
 return Object.freeze({sourceType:"procurement_supplier_invoice",sourceId:invoice.id,tenantId:invoice.tenantId,branchId:invoice.branchId,idempotencyKey,currency:"IDR",debitTotalIdr:debit,creditTotalIdr:credit,status:"draft",paymentStatus:"not_paid",settlementStatus:"not_reconciled",requiresOpenFiscalPeriod:true,requiresIndependentFinanceApproval:true,lines:Object.freeze(journalLines.map(Object.freeze))});
}
