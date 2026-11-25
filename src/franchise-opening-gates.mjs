/**
 * Franchise approval/provisioning gate. All evidence must be loaded by the
 * server; this module does not provision tenant or branch records.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
export function evaluateFranchiseOpening({application,territoryChecks,dueDiligence,contract,openingGates,verifications}) {
 if(!application?.id||application.status!=="approved")fail("APPLICATION_NOT_APPROVED","Franchise application must be approved");
 if(!Array.isArray(territoryChecks)||territoryChecks.length===0||territoryChecks.some(x=>x.status!=="clear"||!x.checkedAt))fail("TERRITORY_CONFLICT_UNRESOLVED","Every territory overlap check must be clear and timestamped");
 if(!Array.isArray(dueDiligence)||dueDiligence.length===0||dueDiligence.some(x=>x.status!=="passed"||!x.evidenceRef||!x.reviewedBy))fail("DUE_DILIGENCE_INCOMPLETE","All due diligence checks need pass status, evidence and reviewer");
 if(!contract||contract.status!=="signed"||!contract.version||!contract.documentHash||!contract.signedAt||!contract.signatoryId)fail("SIGNED_CONTRACT_REQUIRED","A versioned, hash-identified signed contract is required");
 if(!Array.isArray(openingGates)||openingGates.length===0||openingGates.some(x=>x.status!=="passed"||!x.evidenceRef||!x.completedBy))fail("OPENING_GATES_INCOMPLETE","All opening gates must pass with evidence");
 if(!Array.isArray(verifications)||verifications.length===0||verifications.some(x=>x.status!=="verified"||!x.verifiedBy||x.verifiedBy===x.completedBy))fail("INDEPENDENT_VERIFICATION_REQUIRED","Opening evidence requires independent verification");
 return Object.freeze({applicationId:application.id,contractVersion:contract.version,contractHash:contract.documentHash,openingEligible:true,provisioningStatus:"awaiting_authorized_platform_provisioning"});
}
