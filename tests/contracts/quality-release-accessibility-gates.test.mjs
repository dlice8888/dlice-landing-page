import test from "node:test";
import assert from "node:assert/strict";
import {
 evaluatePilotAcceptance,evaluateReleaseExitCriteria,evaluateResponsiveAccessibilityAudit,
 recordStagingPilotOutcome,authorizeStagingRollback,
} from "../../src/quality-release-accessibility-gates.mjs";

const acceptedPilot={signedOff:true,workflowTestsPassed:true,reconciliationStatus:"RECONCILED",rollbackDrillPassed:true,
 tenantIsolationPassed:true,failedJobs:0,skippedJobs:0,branchCount:150,evidenceReference:"private://pilot/evidence"};
const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"qa-a",idempotencyKey:"quality-gate-0001"};

test("pilot acceptance requires all evidence, reconciliation, rollback and isolation gates",()=>{
 assert.equal(evaluatePilotAcceptance(acceptedPilot).status,"accepted");
 const failed=evaluatePilotAcceptance({...acceptedPilot,skippedJobs:1,rollbackDrillPassed:false});
 assert.equal(failed.status,"blocked");assert.deepEqual(failed.missing,["rollbackDrill","noSkippedJobs"]);
});
test("release exit criteria requires all 18 domains, 189 DONE features, 150 branches and every final gate",()=>{
 const testResults=Object.fromEntries(["migrationReplay","pgTap","tenantIsolationP01P09","posE2E","browserE2E","deviceE2E","reconciliation","securityReview"]
  .map(key=>[key,{status:"PASS",skipped:false,executed:true}]));
 const input={domainCount:18,featureCount:189,acceptedBranchCount:150,unverifiedFeatureCount:0,blockedFeatureCount:0,
  partialFeatureCount:0,doneFeatureCount:189,releaseFlags:{TENANT_ISOLATION_RELEASED:false,PUBLIC_TENANT_ROUTING_RELEASED:false},testResults};
 assert.equal(evaluateReleaseExitCriteria(input).status,"ready");
 assert.equal(evaluateReleaseExitCriteria({...input,testResults:{...testResults,posE2E:{status:"PASS",skipped:true}}}).status,"not_ready");
 assert.equal(evaluateReleaseExitCriteria({...input,acceptedBranchCount:149}).status,"not_ready");
});
test("responsive accessibility requires mobile tablet desktop and all WCAG evidence",()=>{
 const checks={keyboardNavigation:true,visibleFocus:true,reducedMotion:true,contrast:true,labels:true,validation:true,screenReader:true};
 const viewports=Object.fromEntries(["mobile","tablet","desktop"].map(v=>[v,{...checks,screenshotReference:"private://"+v,criticalIssues:0,seriousIssues:0}]));
 assert.equal(evaluateResponsiveAccessibilityAudit({viewports}).status,"passed");
 const broken={...viewports,mobile:{...viewports.mobile,screenReader:false}};
 assert.equal(evaluateResponsiveAccessibilityAudit({viewports:broken}).status,"not_passed");
});
test("pilot outcome is recorded only from same-tenant/branch staging evidence",async()=>{
 const deps={
  withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
  findPilotByIdempotencyKey:async()=>null,
  loadPilotEvidence:async()=>({tenantId:"tenant-a",branchId:"branch-a",...acceptedPilot}),
  persistPilotOutcome:async(_tx,row)=>{assert.equal(row.status,"accepted");return{id:"pilot-a"};},
  appendAudit:async()=>{},
 };
 const result=await recordStagingPilotOutcome({...base,environment:"staging",pilotRunId:"pilot-run-a"},deps);
 assert.equal(result.status,"accepted");assert.equal(result.pilotId,"pilot-a");
});
test("pilot and rollback writes reject non-staging environment",async()=>{
 await assert.rejects(recordStagingPilotOutcome({...base,environment:"production",pilotRunId:"pilot-run-a"},{}),
  {code:"QUALITY_PILOT_STAGING_ONLY"});
 await assert.rejects(authorizeStagingRollback({...base,environment:"production",deploymentId:"deploy-a"},{}),
  {code:"QUALITY_ROLLBACK_STAGING_ONLY"});
});
test("rollback requires degraded staging deployment and independent approval",async()=>{
 const deps={
  withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
  loadDeploymentForRollback:async()=>({id:"deploy-a",tenantId:"tenant-a",branchId:"branch-a",status:"degraded"}),
  loadIndependentRollbackApproval:async()=>({id:"approval-a",approved:true,approvedBy:"owner-b",evidenceReference:"private://approval"}),
  persistRollbackAuthorization:async()=>({id:"rollback-a"}),appendAudit:async()=>{},
 };
 const result=await authorizeStagingRollback({...base,actorId:"qa-a",environment:"staging",deploymentId:"deploy-a"},deps);
 assert.deepEqual(result,{status:"authorized",rollbackId:"rollback-a"});
});
test("rollback rejects self-approval and healthy deployments",async()=>{
 const self={withTenantTransaction:async(_s,fn)=>fn({}),authorize:async()=>{},
  loadDeploymentForRollback:async()=>({id:"deploy-a",tenantId:"tenant-a",branchId:"branch-a",status:"degraded"}),
  loadIndependentRollbackApproval:async()=>({id:"approval-a",approved:true,approvedBy:"qa-a",evidenceReference:"private://approval"})};
 await assert.rejects(authorizeStagingRollback({...base,environment:"staging",deploymentId:"deploy-a"},self),
  {code:"QUALITY_ROLLBACK_APPROVAL_REQUIRED"});
 const healthy={...self,loadDeploymentForRollback:async()=>({id:"deploy-a",tenantId:"tenant-a",branchId:"branch-a",status:"ready"})};
 await assert.rejects(authorizeStagingRollback({...base,environment:"staging",deploymentId:"deploy-a"},healthy),
  {code:"QUALITY_ROLLBACK_NOT_REQUIRED"});
});
