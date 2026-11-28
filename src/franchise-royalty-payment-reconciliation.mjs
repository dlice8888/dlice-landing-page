/**
 * Reconciles franchise royalty payment to a signed-off royalty statement.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function reconcileFranchiseRoyaltyPayment({statement,payment,settlement}) {
 if(!statement?.id||statement.status!=="approved"||!statement.agreementId||!statement.financialCloseId)fail("APPROVED_ROYALTY_STATEMENT_REQUIRED","Royalty statement must be approved and linked to agreement and financial close");
 if(!payment?.id||payment.status!=="succeeded"||payment.statementId!==statement.id||!payment.providerReference)fail("ROYALTY_PAYMENT_NOT_CONFIRMED","Successful provider payment reference is required");
 if(!settlement||settlement.status!=="reconciled"||settlement.providerReference!==payment.providerReference)fail("ROYALTY_SETTLEMENT_NOT_RECONCILED","Provider settlement must reconcile to payment");
 if(!Number.isSafeInteger(statement.royaltyIdr)||statement.royaltyIdr<0||!Number.isSafeInteger(payment.amountIdr)||payment.amountIdr!==statement.royaltyIdr||settlement.settledAmountIdr!==payment.amountIdr)fail("ROYALTY_PAYMENT_AMOUNT_MISMATCH","Paid and settled amount must equal approved royalty");
 return Object.freeze({statementId:statement.id,paymentId:payment.id,providerReference:payment.providerReference,royaltyIdr:statement.royaltyIdr,status:"settled",idempotencyKey:`franchise-royalty-settlement:${statement.id}:${payment.id}`});
}
