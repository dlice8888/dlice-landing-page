import test from "node:test";
import assert from "node:assert/strict";
import {
 completeAccessReview,completeAccountRecovery,grantJustInTimeSupportAccess,revokeJustInTimeSupportAccess,
} from "../../src/admin-access-review-recovery-support-workflows.mjs";

const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"security-reviewer",idempotencyKey:"security-flow-0001"};
const common=(overrides={})=>({
 withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
 appendAudit:async(_tx,e)=>{assert.ok(e.action.startsWith("admin.")||e.action.startsWith("saas."));},...overrides,
});

test("access review requires independent reviewer and explicit decisions for every device/session",async()=>{
 const deps=common({
  findAccessReviewByIdempotencyKey:async()=>null,
  loadTenantMemberForAccessReview:async()=>({tenantId:"tenant-a",userId:"employee-a"}),
  loadAccessReviewAuthority:async()=>({approved:true,userId:"security-reviewer"}),
  loadMemberSessionsAndDevices:async()=>({sessions:[{id:"session-a"}],devices:[{id:"device-a"}]}),
  loadAccessReviewDecisions:async()=>[{resourceId:"session-a",decision:"revoke"},{resourceId:"device-a",decision:"retain",reason:"Managed corporate tablet"}],
  revokeAuthSession:async()=>{},revokeTrustedDevice:async()=>{},
  persistAccessReview:async(_tx,row)=>{assert.equal(row.reviewedCount,2);return{id:"review-a"};},
 });
 const result=await completeAccessReview({...base,memberId:"member-a",reviewPeriod:"2026-H2"},deps);
 assert.deepEqual(result,{status:"completed",reviewId:"review-a",reviewedCount:2,revokedCount:1});
});
test("access review rejects self review and missing resource decisions",async()=>{
 const deps=common({
  findAccessReviewByIdempotencyKey:async()=>null,
  loadTenantMemberForAccessReview:async()=>({tenantId:"tenant-a",userId:"security-reviewer"}),
  loadAccessReviewAuthority:async()=>({approved:true,userId:"security-reviewer"}),
 });
 await assert.rejects(completeAccessReview({...base,memberId:"member-a",reviewPeriod:"2026-H2"},deps),
  {code:"ACCESS_REVIEW_SELF_REVIEW_DENIED"});
 const incomplete=common({
  findAccessReviewByIdempotencyKey:async()=>null,
  loadTenantMemberForAccessReview:async()=>({tenantId:"tenant-a",userId:"employee-a"}),
  loadAccessReviewAuthority:async()=>({approved:true,userId:"security-reviewer"}),
  loadMemberSessionsAndDevices:async()=>({sessions:[{id:"session-a"}],devices:[]}),
  loadAccessReviewDecisions:async()=>[],
 });
 await assert.rejects(completeAccessReview({...base,memberId:"member-a",reviewPeriod:"2026-H2"},incomplete),
  {code:"ACCESS_REVIEW_INCOMPLETE"});
});
test("account recovery requires official proof, independent approval and zero active sessions",async()=>{
 const deps=common({
  findAccountRecoveryByIdempotencyKey:async()=>null,
  verifyOfficialAuthRecoveryProof:async()=>({verified:true,userId:"user-a",id:"proof-a"}),
  loadIndependentRecoveryApproval:async()=>({approved:true,approvedBy:"owner-b",id:"approval-a"}),
  rotateAuthRecoveryFactors:async()=>({rotated:true,id:"rotation-a"}),
  revokeAllUserSessions:async()=>({revoked:true,remaining:0,id:"sessions-a"}),
  persistAccountRecoveryEvent:async()=>({id:"recovery-a"}),
 });
 const result=await completeAccountRecovery({...base,userId:"user-a",recoveryProofReference:"auth-recovery://proof"},deps);
 assert.deepEqual(result,{status:"completed",recoveryId:"recovery-a"});
});
test("account recovery rejects unverified proof and remaining sessions",async()=>{
 const deps=common({
  findAccountRecoveryByIdempotencyKey:async()=>null,
  verifyOfficialAuthRecoveryProof:async()=>({verified:false,userId:"user-a"}),
 });
 await assert.rejects(completeAccountRecovery({...base,userId:"user-a",recoveryProofReference:"proof"},deps),
  {code:"ACCOUNT_RECOVERY_PROOF_INVALID"});
 const sessions=common({
  findAccountRecoveryByIdempotencyKey:async()=>null,
  verifyOfficialAuthRecoveryProof:async()=>({verified:true,userId:"user-a",id:"proof"}),
  loadIndependentRecoveryApproval:async()=>({approved:true,approvedBy:"owner-b",id:"approval"}),
  rotateAuthRecoveryFactors:async()=>({rotated:true,id:"rotation"}),
  revokeAllUserSessions:async()=>({revoked:true,remaining:1,id:"sessions"}),
 });
 await assert.rejects(completeAccountRecovery({...base,userId:"user-a",recoveryProofReference:"proof"},sessions),
  {code:"ACCOUNT_RECOVERY_SESSION_REVOCATION_FAILED"});
});
test("JIT support grant is read-only, tenant-owner approved and expires within 30 minutes",async()=>{
 const deps=common({
  findSupportAccessGrantByIdempotencyKey:async()=>null,
  loadTenantOwnerSupportApproval:async()=>({approved:true,tenantId:"tenant-a",approvedBy:"tenant-owner",id:"approval-a"}),
  createScopedSupportSession:async(_tx,row)=>({id:"grant-a",expiresAt:row.expiresAt}),
 });
 const result=await grantJustInTimeSupportAccess({...base,supportUserId:"support-agent",
  ticketReference:"SUP-123",scopes:["tenant.read","audit.read"],now:"2026-11-27T10:00:00Z",
  expiresAt:"2026-11-27T10:20:00Z"},deps);
 assert.equal(result.status,"granted");assert.equal(result.grantId,"grant-a");
});
test("JIT support grant rejects write scopes, missing approval and excessive duration",async()=>{
 await assert.rejects(grantJustInTimeSupportAccess({...base,supportUserId:"support-agent",ticketReference:"SUP-1",
  scopes:["tenant.write"],now:"2026-11-27T10:00:00Z",expiresAt:"2026-11-27T10:10:00Z"},{}),
  {code:"SUPPORT_ACCESS_SCOPE_INVALID"});
 await assert.rejects(grantJustInTimeSupportAccess({...base,supportUserId:"support-agent",ticketReference:"SUP-1",
  scopes:["tenant.read"],now:"2026-11-27T10:00:00Z",expiresAt:"2026-11-27T11:00:00Z"},{}),
  {code:"SUPPORT_ACCESS_DURATION_INVALID"});
});
test("JIT support access revocation requires zero remaining sessions",async()=>{
 const deps=common({
  loadSupportAccessGrantForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"grant-a"}),
  revokeScopedSupportSession:async()=>({revoked:true,activeSessionsRemaining:0}),
 });
 const result=await revokeJustInTimeSupportAccess({...base,grantId:"grant-a"},deps);
 assert.deepEqual(result,{status:"revoked",grantId:"grant-a"});
});
