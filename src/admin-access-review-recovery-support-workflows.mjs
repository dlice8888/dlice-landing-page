/**
 * Identity/device access reviews, account recovery and just-in-time tenant support.
 * Sensitive auth/session changes are delegated to official Auth/session adapters.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("ACCESS_WORKFLOW_INPUT_REQUIRED",f);return v.trim();};
const adapter=(d,n)=>{if(typeof d?.[n]!=="function")fail("ACCESS_WORKFLOW_ADAPTER_REQUIRED",n);return d[n];};
const scope=(i,a)=>({tenantId:req(i?.tenantId,"tenantId"),actorId:req(i?.actorId,"actorId"),
 branchId:i?.branchId==null?null:req(i.branchId,"branchId"),idempotencyKey:req(i?.idempotencyKey,"idempotencyKey"),action:a});
const txScope=(d,s,fn)=>adapter(d,"withTenantTransaction")(s,async tx=>{
 if(!tx)fail("ACCESS_WORKFLOW_TRANSACTION_REQUIRED","Database transaction required");
 await adapter(d,"authorize")(tx,s);return fn(tx);
});
const assertTenant=(r,s,n)=>{if(!r||r.tenantId!==s.tenantId)fail("ACCESS_WORKFLOW_TENANT_MISMATCH",n);};

/** Record an independent access review and revoke every unapproved device/session. */
export async function completeAccessReview(input,deps){
 const s=scope(input,"admin.access_review.complete"),memberId=req(input.memberId,"memberId"),reviewPeriod=req(input.reviewPeriod,"reviewPeriod");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findAccessReviewByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",reviewId:prior.id});
  const member=await adapter(deps,"loadTenantMemberForAccessReview")(tx,{...s,memberId});assertTenant(member,s,"member");
  if(member.userId===s.actorId)fail("ACCESS_REVIEW_SELF_REVIEW_DENIED","Members cannot review their own access");
  const reviewer=await adapter(deps,"loadAccessReviewAuthority")(tx,s);
  if(!reviewer?.approved||reviewer.userId!==s.actorId)fail("ACCESS_REVIEW_AUTHORITY_REQUIRED","Authorized independent reviewer is required");
  const inventory=await adapter(deps,"loadMemberSessionsAndDevices")(tx,{...s,memberId});
  if(!inventory||!Array.isArray(inventory.sessions)||!Array.isArray(inventory.devices))fail("ACCESS_REVIEW_INVENTORY_REQUIRED","Current session and device inventory is required");
  const decisions=await adapter(deps,"loadAccessReviewDecisions")(tx,{...s,memberId,reviewPeriod});
  if(!Array.isArray(decisions))fail("ACCESS_REVIEW_DECISIONS_REQUIRED","Every session/device needs an explicit review decision");
  const reviewed=new Set(decisions.map(d=>d.resourceId));
  const resources=[...inventory.sessions.map(x=>({...x,kind:"session"})),...inventory.devices.map(x=>({...x,kind:"device"}))];
  if(resources.some(r=>!reviewed.has(r.id)))fail("ACCESS_REVIEW_INCOMPLETE","Every active session and device must be reviewed");
  const revoked=[];
  for(const resource of resources){
   const decision=decisions.find(d=>d.resourceId===resource.id);
   if(decision.decision==="revoke"){
    if(resource.kind==="session")await adapter(deps,"revokeAuthSession")(tx,{...s,sessionId:resource.id});
    else await adapter(deps,"revokeTrustedDevice")(tx,{...s,deviceId:resource.id});
    revoked.push(resource.id);
   }else if(decision.decision!=="retain"||!decision.reason||decision.reason.length<8)
    fail("ACCESS_REVIEW_DECISION_INVALID","Retained access requires a documented reason");
  }
  const saved=await adapter(deps,"persistAccessReview")(tx,{...s,memberId,reviewPeriod,
   reviewedCount:resources.length,revokedResourceIds:revoked});
  if(!saved?.id)fail("ACCESS_REVIEW_PERSIST_FAILED","Access review was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"admin.access_review.completed",entityType:"tenant_member_access_review",entityId:saved.id,
   metadata:{memberId,reviewedCount:resources.length,revokedCount:revoked.length}});
  return Object.freeze({status:"completed",reviewId:saved.id,reviewedCount:resources.length,revokedCount:revoked.length});
 });
}

/** Complete account recovery only after verified proof; revoke every existing session. */
export async function completeAccountRecovery(input,deps){
 const s=scope(input,"admin.account_recovery.complete"),userId=req(input.userId,"userId");
 const recoveryProof=req(input.recoveryProofReference,"recoveryProofReference");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findAccountRecoveryByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",recoveryId:prior.id});
  const proof=await adapter(deps,"verifyOfficialAuthRecoveryProof")(tx,{...s,userId,recoveryProofReference:recoveryProof});
  if(!proof?.verified||proof.userId!==userId)fail("ACCOUNT_RECOVERY_PROOF_INVALID","Official Auth recovery proof must be verified");
  const approval=await adapter(deps,"loadIndependentRecoveryApproval")(tx,{...s,userId});
  if(!approval?.approved||approval.approvedBy===userId||approval.approvedBy===s.actorId)
   fail("ACCOUNT_RECOVERY_INDEPENDENT_APPROVAL_REQUIRED","Recovery requires a different authorized approver");
  const reset=await adapter(deps,"rotateAuthRecoveryFactors")(tx,{...s,userId,proofId:proof.id});
  if(!reset?.rotated)fail("ACCOUNT_RECOVERY_FACTOR_ROTATION_FAILED","Official Auth recovery factors were not rotated");
  const sessions=await adapter(deps,"revokeAllUserSessions")(tx,{...s,userId});
  if(!sessions?.revoked||sessions.remaining!==0)fail("ACCOUNT_RECOVERY_SESSION_REVOCATION_FAILED","All prior sessions must be revoked");
  const saved=await adapter(deps,"persistAccountRecoveryEvent")(tx,{...s,userId,proofId:proof.id,approvalId:approval.id,
   factorRotationId:reset.id,sessionRevocationId:sessions.id});
  if(!saved?.id)fail("ACCOUNT_RECOVERY_EVENT_FAILED","Recovery event was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"admin.account_recovery.completed",entityType:"auth_account_recovery",entityId:saved.id,
   metadata:{userId,sessionRevocationId:sessions.id}});
  return Object.freeze({status:"completed",recoveryId:saved.id});
 });
}

/** Grant time-bounded, least-privilege support access only after tenant-owner approval. */
export async function grantJustInTimeSupportAccess(input,deps){
 const s=scope(input,"saas.support_access.grant"),tenantId=s.tenantId,userId=req(input.supportUserId,"supportUserId");
 const ticketReference=req(input.ticketReference,"ticketReference"),requestedScopes=input.scopes;
 if(!Array.isArray(requestedScopes)||!requestedScopes.length||requestedScopes.some(x=>!["tenant.read","billing.read","configuration.read","audit.read"].includes(x)))
  fail("SUPPORT_ACCESS_SCOPE_INVALID","Support access must be least-privilege read-only scopes");
 const expiresAt=Date.parse(req(input.expiresAt,"expiresAt")),now=Date.parse(req(input.now,"now"));
 if(!Number.isFinite(expiresAt)||!Number.isFinite(now)||expiresAt<=now||expiresAt-now>30*60*1000)
  fail("SUPPORT_ACCESS_DURATION_INVALID","JIT support access must expire within 30 minutes");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findSupportAccessGrantByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",grantId:prior.id});
  const approval=await adapter(deps,"loadTenantOwnerSupportApproval")(tx,{...s,ticketReference,supportUserId:userId});
  if(!approval?.approved||approval.tenantId!==tenantId||approval.approvedBy===userId)
   fail("SUPPORT_ACCESS_TENANT_OWNER_APPROVAL_REQUIRED","Tenant owner approval is required");
  const grant=await adapter(deps,"createScopedSupportSession")(tx,{...s,supportUserId:userId,ticketReference,
   scopes:[...new Set(requestedScopes)],expiresAt:new Date(expiresAt).toISOString(),approvalId:approval.id});
  if(!grant?.id||grant.expiresAt!==new Date(expiresAt).toISOString())fail("SUPPORT_ACCESS_GRANT_FAILED","Scoped support session was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"saas.support_access.granted",entityType:"saas_support_access_grant",entityId:grant.id,
   metadata:{supportUserId:userId,ticketReference,scopes:[...new Set(requestedScopes)],expiresAt:grant.expiresAt}});
  return Object.freeze({status:"granted",grantId:grant.id,expiresAt:grant.expiresAt,scopes:Object.freeze([...new Set(requestedScopes)])});
 });
}

/** Revoke a JIT support grant immediately and prove no active session remains. */
export async function revokeJustInTimeSupportAccess(input,deps){
 const s=scope(input,"saas.support_access.revoke"),grantId=req(input.grantId,"grantId");
 return txScope(deps,s,async tx=>{
  const grant=await adapter(deps,"loadSupportAccessGrantForUpdate")(tx,{...s,grantId});assertTenant(grant,s,"supportGrant");
  const result=await adapter(deps,"revokeScopedSupportSession")(tx,{...s,grantId});
  if(!result?.revoked||result.activeSessionsRemaining!==0)fail("SUPPORT_ACCESS_REVOCATION_FAILED","All scoped support sessions must be revoked");
  await adapter(deps,"appendAudit")(tx,{...s,action:"saas.support_access.revoked",entityType:"saas_support_access_grant",entityId:grantId});
  return Object.freeze({status:"revoked",grantId});
 });
}
