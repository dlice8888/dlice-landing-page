/**
 * Deterministic franchise territory and opening-gate policy helpers.
 * The caller must load authoritative, tenant-scoped records and persist audit events.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
const norm=v=>String(v??"").normalize("NFKC").trim().toLocaleLowerCase("id-ID");
export function detectFranchiseTerritoryConflicts(candidate,activeTerritories) {
 if(!candidate||!candidate.countryCode||!candidate.provinceCode||!candidate.cityCode)fail("TERRITORY_SCOPE_REQUIRED","Country, province and city codes are required");
 const keys=new Set((candidate.postalCodes??[]).map(norm).filter(Boolean));
 const conflicts=[];
 for(const t of activeTerritories??[]){
  if(t.status!=="active"&&t.status!=="reserved")continue;
  const sameCity=norm(t.countryCode)===norm(candidate.countryCode)&&norm(t.provinceCode)===norm(candidate.provinceCode)&&norm(t.cityCode)===norm(candidate.cityCode);
  const postalOverlap=(t.postalCodes??[]).some(x=>keys.has(norm(x)));
  if(sameCity||postalOverlap)conflicts.push(Object.freeze({territoryId:t.id,reason:postalOverlap?"postal_code_overlap":"city_scope_overlap",status:t.status}));
 }
 return Object.freeze({clear:conflicts.length===0,conflicts:Object.freeze(conflicts)});
}
export function evaluateFranchiseOpeningGates({applicationId,contract,site,checks,provisioning,actor}) {
 if(!applicationId)fail("APPLICATION_REQUIRED","Application id is required");
 if(!contract||contract.status!=="signed"||!contract.version||!contract.signedDocumentHash||!contract.signedAt)fail("SIGNED_CONTRACT_REQUIRED","Versioned contract and signed document evidence are required");
 if(!site||site.status!=="approved"||!site.feasibilityEvidenceRef)fail("APPROVED_SITE_REQUIRED","Approved site with evidence is required");
 const required=["legal","financial","territory","site","operations","brand","training","food_safety","security","technology"];
 const byKey=new Map((checks??[]).map(x=>[x.checkKey,x]));
 const missing=required.filter(k=>!byKey.has(k)||byKey.get(k).status!=="passed"||!byKey.get(k).evidenceRef);
 if(missing.length)fail("OPENING_GATES_INCOMPLETE",missing.join(","));
 if(!actor?.userId||actor.userId===contract.signedBy||actor.userId===site.reviewedBy)fail("INDEPENDENT_OPENING_VERIFIER_REQUIRED","Opening verifier must be distinct from contract signer and site reviewer");
 if(!provisioning||provisioning.status!=="verified"||!provisioning.tenantId||!provisioning.branchId||!provisioning.evidenceRef)fail("TENANT_BRANCH_PROVISIONING_NOT_VERIFIED","Provisioning must be independently verified before opening");
 return Object.freeze({applicationId,contractVersion:contract.version,tenantId:provisioning.tenantId,branchId:provisioning.branchId,verifiedBy:actor.userId,gateCount:required.length,status:"opening_eligible"});
}
