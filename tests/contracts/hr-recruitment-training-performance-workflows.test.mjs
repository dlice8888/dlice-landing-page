import test from "node:test";
import assert from "node:assert/strict";
import {
 transitionRecruitmentCandidate,completeEmployeeOffboarding,recordEmployeeTrainingCompletion,publishEmployeePerformanceReview,
} from "../../src/hr-recruitment-training-performance-workflows.mjs";

const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"hr-a",idempotencyKey:"hr-flow-0001"};
const common=(overrides={})=>({
 withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
 appendAudit:async(_tx,e)=>{assert.ok(e.action.startsWith("hr."));},...overrides,
});

test("recruitment transition to hire creates employee and onboarding plan atomically",async()=>{
 const deps=common({
  findRecruitmentEventByIdempotencyKey:async()=>null,
  loadRecruitmentCandidateForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"candidate-a",status:"offered"}),
  persistRecruitmentTransition:async()=>({id:"event-hire"}),
  createEmployeeFromHiredCandidate:async()=>({id:"employee-a"}),
  createApprovedOnboardingPlan:async()=>({id:"onboarding-a"}),
 });
 const result=await transitionRecruitmentCandidate({...base,candidateId:"candidate-a",decision:"hire"},deps);
 assert.deepEqual(result,{status:"hired",eventId:"event-hire",onboardingPlanId:"onboarding-a"});
});
test("recruitment rejects invalid state transition before persistence",async()=>{
 let persisted=false;
 const deps=common({findRecruitmentEventByIdempotencyKey:async()=>null,
  loadRecruitmentCandidateForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"candidate-a",status:"applied"}),
  persistRecruitmentTransition:async()=>{persisted=true;}});
 await assert.rejects(transitionRecruitmentCandidate({...base,candidateId:"candidate-a",decision:"hire"},deps),
  {code:"HR_RECRUITMENT_TRANSITION_INVALID"});
 assert.equal(persisted,false);
});
test("offboarding requires independent approval, access revocation and asset return",async()=>{
 const deps=common({
  findOffboardingCompletionByIdempotencyKey:async()=>null,
  loadEmployeeForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"employee-a",status:"offboarding",userId:"user-a"}),
  loadIndependentOffboardingApproval:async()=>({approved:true,approvedBy:"owner-b",id:"approval-a",evidenceReference:"private://approval"}),
  revokeEmployeeAccess:async()=>({revoked:true,activeSessionsRemaining:0,id:"revocation-a"}),
  verifyEmployeeAssetReturn:async()=>({complete:true,id:"assets-a"}),
  persistOffboardingCompletion:async()=>({id:"completion-a"}),
 });
 const result=await completeEmployeeOffboarding({...base,employeeId:"employee-a"},deps);
 assert.deepEqual(result,{status:"completed",completionId:"completion-a"});
});
test("offboarding refuses incomplete session revocation",async()=>{
 const deps=common({
  findOffboardingCompletionByIdempotencyKey:async()=>null,
  loadEmployeeForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"employee-a",status:"offboarding"}),
  loadIndependentOffboardingApproval:async()=>({approved:true,approvedBy:"owner-b",id:"approval-a",evidenceReference:"private://approval"}),
  revokeEmployeeAccess:async()=>({revoked:true,activeSessionsRemaining:1,id:"revocation-a"}),
 });
 await assert.rejects(completeEmployeeOffboarding({...base,employeeId:"employee-a"},deps),
  {code:"HR_ACCESS_REVOCATION_INCOMPLETE"});
});
test("training completion requires approved course and independent evidence verifier",async()=>{
 const deps=common({
  findTrainingCompletionByIdempotencyKey:async()=>null,
  loadEmployeeForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"employee-a"}),
  loadApprovedTrainingCourse:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"course-a",status:"approved",requiresCertification:true}),
  verifyTrainingEvidence:async()=>({verified:true,verifiedBy:"trainer-b",id:"verification-a"}),
  persistTrainingCompletion:async()=>({id:"training-a"}),
 });
 const result=await recordEmployeeTrainingCompletion({...base,employeeId:"employee-a",courseId:"course-a",
  evidenceReference:"private://certificate",completedAt:"2026-11-27T10:00:00Z",expiresAt:"2027-11-27T10:00:00Z"},deps);
 assert.equal(result.status,"completed");assert.equal(result.completionId,"training-a");
});
test("training rejects missing certification expiry and self verification",async()=>{
 const deps=common({
  findTrainingCompletionByIdempotencyKey:async()=>null,
  loadEmployeeForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"employee-a"}),
  loadApprovedTrainingCourse:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"course-a",status:"approved",requiresCertification:true}),
 });
 await assert.rejects(recordEmployeeTrainingCompletion({...base,employeeId:"employee-a",courseId:"course-a",
  evidenceReference:"private://certificate",completedAt:"2026-11-27T10:00:00Z"},deps),
  {code:"HR_TRAINING_COURSE_OR_CERTIFICATION_INVALID"});
});
test("performance review requires reconciled metrics and independent reviewer",async()=>{
 const deps=common({
  findPerformanceReviewByIdempotencyKey:async()=>null,
  loadEmployeeForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"employee-a",userId:"employee-user"}),
  loadApprovedEmployeePerformanceMetrics:async()=>({tenantId:"tenant-a",reconciled:true,measures:[{key:"attendance",score:98}]}),
  loadIndependentPerformanceReviewer:async()=>({approved:true,userId:"reviewer-b"}),
  persistEmployeePerformanceReview:async()=>({id:"review-a"}),
 });
 const result=await publishEmployeePerformanceReview({...base,employeeId:"employee-a",
  periodStart:"2026-10-01",periodEnd:"2026-10-31"},deps);
 assert.deepEqual(result,{status:"published",reviewId:"review-a"});
});
test("performance review rejects unverified source metrics",async()=>{
 const deps=common({
  findPerformanceReviewByIdempotencyKey:async()=>null,
  loadEmployeeForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"employee-a",userId:"employee-user"}),
  loadApprovedEmployeePerformanceMetrics:async()=>({tenantId:"tenant-a",reconciled:false,measures:[]}),
 });
 await assert.rejects(publishEmployeePerformanceReview({...base,employeeId:"employee-a",
  periodStart:"2026-10-01",periodEnd:"2026-10-31"},deps),{code:"HR_PERFORMANCE_METRICS_NOT_RECONCILED"});
});
