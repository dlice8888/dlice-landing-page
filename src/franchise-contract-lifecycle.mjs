/** Immutable franchise contract version and renewal/closure policy. */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function validateFranchiseContractVersion({agreement,previousVersion,signature,actor,now=Date.now()}) {
 if(!agreement?.franchiseId||!Number.isSafeInteger(agreement.version)||agreement.version<1||!agreement.documentHash||!agreement.effectiveFrom||!agreement.effectiveTo)fail("FRANCHISE_CONTRACT_VERSION_INVALID","Version, franchise, hash and effective dates required");
 const start=Date.parse(agreement.effectiveFrom),end=Date.parse(agreement.effectiveTo);if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start)fail("FRANCHISE_CONTRACT_DATES_INVALID","Invalid contract dates");
 if(previousVersion&&(agreement.version!==previousVersion.version+1||agreement.previousDocumentHash!==previousVersion.documentHash))fail("FRANCHISE_CONTRACT_CHAIN_INVALID","Version must extend prior immutable document hash");
 if(!signature?.signedAt||!signature.signerId||!signature.signatureEvidenceHash||signature.signerId===actor?.reviewerId)fail("FRANCHISE_INDEPENDENT_SIGNATURE_REVIEW_REQUIRED","Signature evidence and independent reviewer required");
 return Object.freeze({status:start>now?"scheduled":end<=now?"expired":"active",version:agreement.version});
}
export function evaluateFranchiseClosure({franchise,openObligations,finalRoyaltyReconciliation,tenantExport,retentionPolicy,approvedBy}) {
 if(!franchise?.id||franchise.status!=="active")fail("ACTIVE_FRANCHISE_REQUIRED","Only active franchise can enter closure");
 if((openObligations??[]).some(x=>x.status!=="settled"&&x.status!=="waived"))fail("FRANCHISE_OBLIGATIONS_OPEN","Obligations must be settled or waived");
 if(!finalRoyaltyReconciliation||finalRoyaltyReconciliation.status!=="reconciled"||!finalRoyaltyReconciliation.paid)fail("FINAL_ROYALTY_PAYMENT_REQUIRED","Final royalty must be paid and reconciled");
 if(!tenantExport?.completedAt||!tenantExport?.checksum||!retentionPolicy?.approved||!approvedBy)fail("FRANCHISE_CLOSURE_EVIDENCE_REQUIRED","Export, retention and independent approval required");
 return Object.freeze({franchiseId:franchise.id,status:"eligible_for_closure",exportChecksum:tenantExport.checksum});
}
