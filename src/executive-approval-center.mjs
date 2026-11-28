/**
 * D01-F07: unified approval inbox orchestration.
 * Source business state remains authoritative; this module only claims work,
 * validates policy, asks the source adapter to transition once, and audits it.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,n)=>{if(typeof v!=="string"||!v.trim())fail("APPROVAL_INPUT_REQUIRED",n);return v.trim();};
const fn=(d,n)=>{if(typeof d?.[n]!=="function")fail("APPROVAL_ADAPTER_REQUIRED",n);return d[n];};
const decisionSet=new Set(["approve","reject"]);
export async function listPendingApprovals(input,deps){
 const actorId=req(input?.actorId,"actorId"),tenantId=req(input?.tenantId,"tenantId");
 const scope=Object.freeze({actorId,tenantId,action:"executive.approvals.list"});
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  const policy=await fn(deps,"resolveApproverScope")(tx,scope);
  if(!policy||policy.tenantId!==tenantId||!Array.isArray(policy.branchIds)||!Array.isArray(policy.categories))fail("APPROVAL_SCOPE_DENIED","Server-resolved approver scope required");
  const rows=await fn(deps,"loadPendingApprovalSources")(tx,{tenantId,branchIds:policy.branchIds,categories:policy.categories,roles:policy.roles??[]});
  if(!Array.isArray(rows))fail("APPROVAL_SOURCE_INVALID","Approval source rows required");
  const seen=new Set();
  for(const row of rows){
   if(row.tenantId!==tenantId||!policy.branchIds.includes(row.branchId)||!policy.categories.includes(row.category))fail("APPROVAL_SOURCE_SCOPE_MISMATCH","Approval outside authorized scope");
   if(!row.entityType||!row.entityId||seen.has(row.entityType+":"+row.entityId))fail("APPROVAL_DUPLICATE_SOURCE","Duplicate or invalid approval entity");
   seen.add(row.entityType+":"+row.entityId);
  }
  return rows.sort((a,b)=>(Date.parse(a.expiresAt??"9999-12-31")-Date.parse(b.expiresAt??"9999-12-31"))||Number(b.amountIdr??0)-Number(a.amountIdr??0));
 });
}
export async function decideApproval(input,deps){
 const actorId=req(input?.actorId,"actorId"),tenantId=req(input?.tenantId,"tenantId"),approvalId=req(input?.approvalId,"approvalId");
 const decision=input?.decision,reason=req(input?.reason,"reason"),expectedVersion=input?.expectedVersion;
 if(!decisionSet.has(decision))fail("APPROVAL_DECISION_INVALID","decision must be approve or reject");
 if(!Number.isSafeInteger(expectedVersion)||expectedVersion<0)fail("APPROVAL_VERSION_REQUIRED","expectedVersion must be a non-negative integer");
 const scope=Object.freeze({actorId,tenantId,approvalId,action:"executive.approvals.decide"});
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  const actor=await fn(deps,"resolveApproverScope")(tx,scope);
  if(!actor||actor.tenantId!==tenantId)fail("APPROVAL_SCOPE_DENIED","Actor has no tenant approval scope");
  const approval=await fn(deps,"lockApproval")(tx,{tenantId,approvalId});
  if(!approval||approval.tenantId!==tenantId)fail("APPROVAL_NOT_FOUND","Approval not found");
  if(approval.status!=="pending")fail("APPROVAL_NOT_PENDING","Approval is no longer pending");
  if(approval.version!==expectedVersion)fail("APPROVAL_STALE_VERSION","Approval changed; reload before deciding");
  if(Date.parse(approval.expiresAt)<=Date.now())fail("APPROVAL_EXPIRED","Approval has expired");
  if(!actor.branchIds?.includes(approval.branchId)||!actor.categories?.includes(approval.category))fail("APPROVAL_BRANCH_OR_CATEGORY_DENIED","Approval outside actor scope");
  if(!actor.roles?.some(role=>approval.requiredRoles?.includes(role)))fail("APPROVAL_ROLE_DENIED","Required approver role missing");
  if(approval.createdBy===actorId&&approval.policy?.allowSelfApproval!==true)fail("APPROVAL_SELF_APPROVAL_DENIED","Creator cannot approve this entity");
  if(approval.claimedBy&&approval.claimedBy!==actorId&&approval.claimExpiresAt&&Date.parse(approval.claimExpiresAt)>Date.now())fail("APPROVAL_CLAIMED_BY_OTHER","Approval is claimed by another approver");
  if(approval.amountIdr>Number(actor.maxApprovalAmountIdr??0))fail("APPROVAL_AMOUNT_LIMIT","Approval amount exceeds actor limit");
  const claim=await fn(deps,"claimApprovalLocked")(tx,{tenantId,approvalId,actorId,expectedVersion});
  if(!claim||claim.claimedBy!==actorId)fail("APPROVAL_CLAIM_FAILED","Atomic claim failed");
  const source=await fn(deps,"decideSourceEntityOnce")(tx,{tenantId,entityType:approval.entityType,entityId:approval.entityId,actorId,decision,reason,expectedSourceVersion:approval.sourceVersion,idempotencyKey:"approval:"+approvalId+":"+expectedVersion});
  if(!source?.updated||source.updateCount!==1)fail("APPROVAL_SOURCE_TRANSITION_FAILED","Source entity must transition exactly once");
  const result=await fn(deps,"persistApprovalDecision")(tx,{tenantId,approvalId,actorId,decision,reason,expectedVersion,sourceVersion:source.version});
  if(!result?.id)fail("APPROVAL_DECISION_PERSIST_FAILED","Approval decision was not persisted");
  await fn(deps,"appendAudit")(tx,{...scope,action:"executive.approval."+decision,entityType:approval.entityType,entityId:approval.entityId,metadata:{approvalId,sourceVersion:source.version,decisionId:result.id}});
  return Object.freeze({approvalId,decision,decisionId:result.id,sourceVersion:source.version});
 });
}
