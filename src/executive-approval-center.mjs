/**
 * D01-F07 unified Executive approval inbox.
 * Business status remains owned by the source domain; this module stores only
 * workflow coordination and delegates the single source mutation to an adapter.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
const req=(v,n)=>{if(typeof v!=="string"||!v.trim())fail("EXEC_APPROVAL_INPUT_REQUIRED",n);return v.trim();};
const fn=(d,n)=>{if(typeof d?.[n]!=="function")fail("EXEC_APPROVAL_ADAPTER_REQUIRED",n);return d[n];};
const version=v=>{if(!Number.isSafeInteger(v)||v<0)fail("EXEC_APPROVAL_VERSION_REQUIRED","A non-negative expectedVersion is required");return v;};
const reason=v=>{if(typeof v!=="string"||v.trim().length<8||v.trim().length>2000)fail("EXEC_APPROVAL_REASON_REQUIRED","Decision reason must contain 8-2000 characters");return v.trim();};

/** All authorization/policy adapters execute server-side within the transaction. */
export async function listPendingApprovals(input,deps){
 const actorId=req(input?.actorId,"actorId"),tenantId=req(input?.tenantId,"tenantId");
 const filters=input?.filters??{};
 return fn(deps,"withTenantTransaction")({actorId,tenantId,action:"executive.approvals.list"},async tx=>{
  const scope=await fn(deps,"resolveApprovalScope")(tx,{actorId,tenantId});
  await fn(deps,"authorizeApprovalInbox")(tx,scope);
  const rows=await fn(deps,"listPendingApprovalSources")(tx,{scope,filters});
  if(!Array.isArray(rows))fail("EXEC_APPROVAL_SOURCE_INVALID","Approval source adapter must return an array");
  for(const row of rows)if(row.tenantId!==tenantId||!scope.branchIds.includes(row.branchId))fail("EXEC_APPROVAL_SCOPE_MISMATCH","Approval source escaped actor scope");
  return rows;
 });
}

export async function claimApproval(input,deps){
 const actorId=req(input?.actorId,"actorId"),tenantId=req(input?.tenantId,"tenantId");
 const approvalId=req(input?.approvalId,"approvalId"),expectedVersion=version(input?.expectedVersion);
 const idempotencyKey=req(input?.idempotencyKey,"idempotencyKey");
 return fn(deps,"withTenantTransaction")({actorId,tenantId,approvalId,action:"executive.approval.claim"},async tx=>{
  const scope=await fn(deps,"resolveApprovalScope")(tx,{actorId,tenantId});
  await fn(deps,"authorizeApprovalClaim")(tx,{scope,approvalId});
  const current=await fn(deps,"lockApprovalInboxItem")(tx,{tenantId,approvalId});
  if(!current||current.tenantId!==tenantId||!scope.branchIds.includes(current.branchId))fail("EXEC_APPROVAL_NOT_FOUND","Approval item not found in authorized scope");
  if(current.version!==expectedVersion)fail("EXEC_APPROVAL_STALE_VERSION","Approval item changed; refresh before claiming");
  if(current.expiresAt&&Date.parse(current.expiresAt)<=Date.now())fail("EXEC_APPROVAL_EXPIRED","Approval request expired");
  const result=await fn(deps,"persistApprovalClaim")(tx,{current,actorId,idempotencyKey,expectedVersion});
  await fn(deps,"appendApprovalAudit")(tx,{tenantId,actorId,approvalId,action:"claimed",idempotencyKey});
  return result;
 });
}

export async function decideApproval(input,deps){
 const actorId=req(input?.actorId,"actorId"),tenantId=req(input?.tenantId,"tenantId");
 const approvalId=req(input?.approvalId,"approvalId"),expectedVersion=version(input?.expectedVersion);
 const idempotencyKey=req(input?.idempotencyKey,"idempotencyKey"),decision=input?.decision;
 if(!["approved","rejected"].includes(decision))fail("EXEC_APPROVAL_DECISION_INVALID","Decision must be approved or rejected");
 const decisionReason=reason(input?.reason);
 return fn(deps,"withTenantTransaction")({actorId,tenantId,approvalId,action:"executive.approval.decide"},async tx=>{
  const scope=await fn(deps,"resolveApprovalScope")(tx,{actorId,tenantId});
  const item=await fn(deps,"lockApprovalInboxItem")(tx,{tenantId,approvalId});
  if(!item||item.tenantId!==tenantId||!scope.branchIds.includes(item.branchId))fail("EXEC_APPROVAL_NOT_FOUND","Approval item not found in authorized scope");
  if(item.version!==expectedVersion)fail("EXEC_APPROVAL_STALE_VERSION","Approval item changed; refresh before deciding");
  if(item.status!=="claimed"||item.claimedBy!==actorId)fail("EXEC_APPROVAL_CLAIM_REQUIRED","Approver must hold the active claim");
  if(item.expiresAt&&Date.parse(item.expiresAt)<=Date.now())fail("EXEC_APPROVAL_EXPIRED","Approval request expired");
  const policy=await fn(deps,"resolveApprovalPolicy")(tx,{scope,item,actorId});
  if(!policy?.allowed||policy.approverId!==actorId)fail("EXEC_APPROVAL_FORBIDDEN","Actor is not an eligible approver");
  if(policy.forbidSelfApproval&&item.createdBy===actorId)fail("EXEC_APPROVAL_SELF_APPROVAL_DENIED","Creator cannot approve this source entity");
  if(policy.requiresDelegation&&!policy.validDelegation)fail("EXEC_APPROVAL_DELEGATION_INVALID","A valid, unexpired delegation is required");
  await fn(deps,"assertSourceEntityVersion")(tx,{item,expectedSourceVersion:item.sourceVersion});
  const saved=await fn(deps,"persistApprovalDecision")(tx,{item,actorId,decision,reason:decisionReason,idempotencyKey,expectedVersion});
  if(saved?.duplicate)return saved;
  const sourceResult=await fn(deps,"applySourceEntityDecisionOnce")(tx,{item,actorId,decision,reason:decisionReason,idempotencyKey,expectedSourceVersion:item.sourceVersion});
  if(!sourceResult||sourceResult.applied!==true)fail("EXEC_APPROVAL_SOURCE_MUTATION_FAILED","Source entity decision was not applied exactly once");
  await fn(deps,"appendApprovalAudit")(tx,{tenantId,actorId,approvalId,action:decision,idempotencyKey,sourceEntity:item.sourceEntity,sourceEntityId:item.sourceEntityId});
  return Object.freeze({approvalId,decision,sourceEntity:item.sourceEntity,sourceEntityId:item.sourceEntityId,sourceMutationId:sourceResult.mutationId,version:saved.version});
 });
}
