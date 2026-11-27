/**
 * HR recruitment, employee lifecycle, training/certification and performance review.
 * Identity, employment status and evidence are server-resolved inside tenant transactions.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("HR_WORKFLOW_INPUT_REQUIRED",f);return v.trim();};
const adapter=(d,n)=>{if(typeof d?.[n]!=="function")fail("HR_WORKFLOW_ADAPTER_REQUIRED",n);return d[n];};
const scope=(i,a)=>({tenantId:req(i?.tenantId,"tenantId"),branchId:req(i?.branchId,"branchId"),
 actorId:req(i?.actorId,"actorId"),idempotencyKey:req(i?.idempotencyKey,"idempotencyKey"),action:a});
const txScope=(d,s,fn)=>adapter(d,"withTenantTransaction")(s,async tx=>{
 if(!tx)fail("HR_WORKFLOW_TRANSACTION_REQUIRED","Database transaction required");
 await adapter(d,"authorize")(tx,s);return fn(tx);
});
const assertScope=(r,s,name)=>{if(!r||r.tenantId!==s.tenantId||(s.branchId&&r.branchId!==s.branchId))fail("HR_WORKFLOW_SCOPE_MISMATCH",name);};

/** Move a candidate through governed recruitment states; hiring creates onboarding plan atomically. */
export async function transitionRecruitmentCandidate(input,deps){
 const s=scope(input,"hr.recruitment.transition"),candidateId=req(input.candidateId,"candidateId"),decision=input.decision;
 if(!["screen","interview","offer","hire","reject"].includes(decision))fail("HR_RECRUITMENT_DECISION_INVALID","Unsupported recruitment decision");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findRecruitmentEventByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",eventId:prior.id});
  const candidate=await adapter(deps,"loadRecruitmentCandidateForUpdate")(tx,{...s,candidateId});assertScope(candidate,s,"candidate");
  const transitions={applied:["screen","reject"],screened:["interview","reject"],interviewed:["offer","reject"],offered:["hire","reject"]};
  const expected={screen:"applied",interview:"screened",offer:"interviewed",hire:"offered",reject:candidate.status};
  if(decision!=="reject"&&candidate.status!==expected[decision])fail("HR_RECRUITMENT_TRANSITION_INVALID","Candidate is not in the required state");
  if(decision==="reject"&&!["applied","screened","interviewed","offered"].includes(candidate.status))
   fail("HR_RECRUITMENT_TRANSITION_INVALID","Candidate cannot be rejected from this state");
  const updated=await adapter(deps,"persistRecruitmentTransition")(tx,{...s,candidateId,decision,expectedStatus:candidate.status,
   reason:input.reason==null?null:String(input.reason).slice(0,1000)});
  if(!updated?.id)fail("HR_RECRUITMENT_TRANSITION_FAILED","Recruitment transition was not persisted");
  let onboardingPlanId=null;
  if(decision==="hire"){
   const employee=await adapter(deps,"createEmployeeFromHiredCandidate")(tx,{...s,candidateId,eventId:updated.id});
   if(!employee?.id)fail("HR_EMPLOYEE_CREATION_FAILED","Hired candidate must create an employee record");
   const plan=await adapter(deps,"createApprovedOnboardingPlan")(tx,{...s,employeeId:employee.id});
   if(!plan?.id)fail("HR_ONBOARDING_PLAN_FAILED","Hiring requires an onboarding plan");
   onboardingPlanId=plan.id;
  }
  await adapter(deps,"appendAudit")(tx,{...s,action:"hr.recruitment."+decision,entityType:"hr_recruitment_candidate",entityId:candidateId,
   metadata:{eventId:updated.id,onboardingPlanId}});
  return Object.freeze({status:decision==="hire"?"hired":decision==="reject"?"rejected":"advanced",
   eventId:updated.id,onboardingPlanId});
 });
}

/** Complete offboarding only after independent approval and server-side access revocation evidence. */
export async function completeEmployeeOffboarding(input,deps){
 const s=scope(input,"hr.employee.offboarding.complete"),employeeId=req(input.employeeId,"employeeId");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findOffboardingCompletionByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",completionId:prior.id});
  const employee=await adapter(deps,"loadEmployeeForUpdate")(tx,{...s,employeeId});assertScope(employee,s,"employee");
  if(employee.status!=="offboarding")fail("HR_EMPLOYEE_NOT_OFFBOARDING","Employee must be in offboarding state");
  const approval=await adapter(deps,"loadIndependentOffboardingApproval")(tx,{...s,employeeId});
  if(!approval?.approved||approval.approvedBy===s.actorId||!approval.evidenceReference)
   fail("HR_OFFBOARDING_APPROVAL_REQUIRED","Independent approval and evidence are required");
  const access=await adapter(deps,"revokeEmployeeAccess")(tx,{...s,employeeId});
  if(!access?.revoked||access.activeSessionsRemaining!==0)fail("HR_ACCESS_REVOCATION_INCOMPLETE","All employee sessions and access must be revoked");
  const assets=await adapter(deps,"verifyEmployeeAssetReturn")(tx,{...s,employeeId});
  if(!assets?.complete)fail("HR_ASSET_RETURN_INCOMPLETE","Company asset return must be reconciled");
  const saved=await adapter(deps,"persistOffboardingCompletion")(tx,{...s,employeeId,approvalId:approval.id,
   accessRevocationId:access.id,assetReturnEvidenceId:assets.id});
  if(!saved?.id)fail("HR_OFFBOARDING_COMPLETION_FAILED","Offboarding completion was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"hr.employee.offboarding.completed",entityType:"hr_employee",entityId:employeeId,
   metadata:{completionId:saved.id,accessRevocationId:access.id,assetReturnEvidenceId:assets.id}});
  return Object.freeze({status:"completed",completionId:saved.id});
 });
}

/** Record verified training/certification completion with expiry and independent reviewer. */
export async function recordEmployeeTrainingCompletion(input,deps){
 const s=scope(input,"hr.training.complete"),employeeId=req(input.employeeId,"employeeId"),courseId=req(input.courseId,"courseId");
 const evidenceReference=req(input.evidenceReference,"evidenceReference"),completedAt=req(input.completedAt,"completedAt");
 const expiresAt=input.expiresAt==null?null:req(input.expiresAt,"expiresAt");
 if(!Number.isFinite(Date.parse(completedAt))||(expiresAt&&(!Number.isFinite(Date.parse(expiresAt))||Date.parse(expiresAt)<=Date.parse(completedAt))))
  fail("HR_TRAINING_DATE_INVALID","Training completion and expiry dates are invalid");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findTrainingCompletionByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",completionId:prior.id});
  const employee=await adapter(deps,"loadEmployeeForUpdate")(tx,{...s,employeeId});assertScope(employee,s,"employee");
  const course=await adapter(deps,"loadApprovedTrainingCourse")(tx,{...s,courseId});
  assertScope(course,s,"course");
  if(course.status!=="approved"||course.requiresCertification===true&&expiresAt===null)
   fail("HR_TRAINING_COURSE_OR_CERTIFICATION_INVALID","Approved course and required certification expiry are mandatory");
  const verification=await adapter(deps,"verifyTrainingEvidence")(tx,{...s,employeeId,courseId,evidenceReference});
  if(!verification?.verified||verification.verifiedBy===s.actorId)fail("HR_TRAINING_INDEPENDENT_VERIFICATION_REQUIRED","Training evidence needs independent verification");
  const saved=await adapter(deps,"persistTrainingCompletion")(tx,{...s,employeeId,courseId,evidenceReference,completedAt,expiresAt,
   verificationId:verification.id});
  if(!saved?.id)fail("HR_TRAINING_COMPLETION_FAILED","Training completion was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"hr.training.completed",entityType:"hr_training_completion",entityId:saved.id,
   metadata:{employeeId,courseId,expiresAt}});
  return Object.freeze({status:"completed",completionId:saved.id,expiresAt});
 });
}

/** Publish a performance review only from approved measured metrics and independent reviewer. */
export async function publishEmployeePerformanceReview(input,deps){
 const s=scope(input,"hr.performance_review.publish"),employeeId=req(input.employeeId,"employeeId");
 const periodStart=req(input.periodStart,"periodStart"),periodEnd=req(input.periodEnd,"periodEnd");
 if(periodStart>periodEnd)fail("HR_REVIEW_PERIOD_INVALID","Review period is invalid");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findPerformanceReviewByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",reviewId:prior.id});
  const employee=await adapter(deps,"loadEmployeeForUpdate")(tx,{...s,employeeId});assertScope(employee,s,"employee");
  const metrics=await adapter(deps,"loadApprovedEmployeePerformanceMetrics")(tx,{...s,employeeId,periodStart,periodEnd});
  if(!metrics||metrics.tenantId!==s.tenantId||metrics.reconciled!==true||!Array.isArray(metrics.measures)||!metrics.measures.length)
   fail("HR_PERFORMANCE_METRICS_NOT_RECONCILED","Approved reconciled performance metrics are required");
  const reviewer=await adapter(deps,"loadIndependentPerformanceReviewer")(tx,{...s,employeeId});
  if(!reviewer?.approved||reviewer.userId===s.actorId||reviewer.userId===employee.userId)
   fail("HR_PERFORMANCE_REVIEWER_INVALID","Independent reviewer approval is required");
  const saved=await adapter(deps,"persistEmployeePerformanceReview")(tx,{...s,employeeId,periodStart,periodEnd,
   measures:metrics.measures,reviewerId:reviewer.userId});
  if(!saved?.id)fail("HR_PERFORMANCE_REVIEW_PERSIST_FAILED","Performance review was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"hr.performance_review.published",entityType:"hr_performance_review",entityId:saved.id});
  return Object.freeze({status:"published",reviewId:saved.id});
 });
}
