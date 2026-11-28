/**
 * Royalty statement candidate from a reconciled financial close and effective agreement.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function calculateFranchiseRoyalty({agreement,financialClose,statementPeriodStart,statementPeriodEnd}) {
 if(!agreement?.id||agreement.status!=="active"||!agreement.version||!agreement.signedAt)fail("ACTIVE_SIGNED_AGREEMENT_REQUIRED","Active signed agreement version is required");
 const start=Date.parse(statementPeriodStart),end=Date.parse(statementPeriodEnd),from=Date.parse(agreement.effectiveFrom),to=agreement.effectiveTo?Date.parse(agreement.effectiveTo):Infinity;
 if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start||from>start||to<end)fail("AGREEMENT_PERIOD_MISMATCH","Agreement must cover the complete royalty period");
 if(!financialClose||financialClose.status!=="reconciled"||financialClose.tenantId!==agreement.tenantId||financialClose.franchiseId!==agreement.franchiseId||financialClose.periodStart>statementPeriodStart||financialClose.periodEnd<statementPeriodEnd||!financialClose.financeJournalBatchId||financialClose.sourceReconciliationStatus!=="reconciled")fail("RECONCILED_FRANCHISE_NET_SALES_REQUIRED","Royalty requires reconciled source and Finance net sales for the full period");
 if(!Number.isSafeInteger(financialClose.netSalesIdr)||financialClose.netSalesIdr<0||!Number.isInteger(agreement.royaltyRateBps)||agreement.royaltyRateBps<0||agreement.royaltyRateBps>10000)fail("ROYALTY_INPUT_INVALID","Net sales and approved royalty basis points are required");
 const royaltyIdr=Math.floor(financialClose.netSalesIdr*agreement.royaltyRateBps/10000);
 return Object.freeze({tenantId:agreement.tenantId,franchiseId:agreement.franchiseId,agreementId:agreement.id,agreementVersion:agreement.version,periodStart:statementPeriodStart,periodEnd:statementPeriodEnd,financialCloseId:financialClose.id,netSalesIdr:financialClose.netSalesIdr,royaltyRateBps:agreement.royaltyRateBps,royaltyIdr,status:"draft",paymentStatus:"not_paid",idempotencyKey:`franchise-royalty:${agreement.tenantId}:${agreement.id}:${agreement.version}:${statementPeriodStart}:${statementPeriodEnd}`});
}
