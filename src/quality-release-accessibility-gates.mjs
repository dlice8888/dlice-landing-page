/**
 * Quality gates for pilot/rollback, release exit criteria and responsive accessibility.
 * These evaluators fail closed; they do not mutate release flags or deploy.
 */
const fail=(code,message)=>{const error=new Error(message);error.code=code;throw error;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("QUALITY_GATE_INPUT_REQUIRED",f);return v.trim();};

export function evaluatePilotAcceptance(input){
 const branches=Number(input.branchCount),failed=Number(input.failedJobs??0),skipped=Number(input.skippedJobs??0);
 const gates={
  signedOff:input.signedOff===true,
  workflowTests:input.workflowTestsPassed===true,
  reconciliation:input.reconciliationStatus==="RECONCILED",
  rollbackDrill:input.rollbackDrillPassed===true,
  tenantIsolation:input.tenantIsolationPassed===true,
  noFailedJobs:Number.isInteger(failed)&&failed===0,
  noSkippedJobs:Number.isInteger(skipped)&&skipped===0,
  branchScope:Number.isInteger(branches)&&branches>=1&&branches<=150,
  evidence:typeof input.evidenceReference==="string"&&input.evidenceReference.trim().length>=8,
 };
 const missing=Object.entries(gates).filter(([,ok])=>!ok).map(([key])=>key);
 return Object.freeze({status:missing.length?"blocked":"accepted",gates:Object.freeze(gates),missing:Object.freeze(missing)});
}

export function evaluateReleaseExitCriteria(input){
 const domains=Number(input.domainCount),features=Number(input.featureCount),branchCount=Number(input.acceptedBranchCount);
 const tests=input.testResults||{};
 const required=["migrationReplay","pgTap","tenantIsolationP01P09","posE2E","browserE2E","deviceE2E","reconciliation","securityReview"];
 const missing=required.filter(key=>tests[key]?.status!=="PASS"||tests[key]?.skipped===true||tests[key]?.executed===false);
 const complete=domains===18&&features===189&&branchCount===150&&
  input.unverifiedFeatureCount===0&&input.blockedFeatureCount===0&&
  input.partialFeatureCount===0&&input.doneFeatureCount===189&&
  input.releaseFlags?.TENANT_ISOLATION_RELEASED===false&&
  input.releaseFlags?.PUBLIC_TENANT_ROUTING_RELEASED===false;
 if(!complete)missing.push("featureAndBranchCompleteness");
 return Object.freeze({status:missing.length?"not_ready":"ready",missing:Object.freeze(missing)});
}

export function evaluateResponsiveAccessibilityAudit(input){
 const viewports=["mobile","tablet","desktop"];
 const requiredChecks=["keyboardNavigation","visibleFocus","reducedMotion","contrast","labels","validation","screenReader"];
 const missing=[];
 for(const viewport of viewports){
  const result=input.viewports?.[viewport];
  if(!result){missing.push(viewport+":missing");continue;}
  if(typeof result.screenshotReference!=="string"||result.screenshotReference.trim().length<8)missing.push(viewport+":screenshot");
  if(result.criticalIssues!==0||result.seriousIssues!==0)missing.push(viewport+":issues");
  for(const check of requiredChecks)if(result[check]!==true)missing.push(viewport+":"+check);
 }
 return Object.freeze({status:missing.length?"not_passed":"passed",standard:"WCAG-2.2-AA",missing:Object.freeze(missing)});
}

/** Record a staging pilot only from server-loaded immutable evidence. */
export async function recordStagingPilotOutcome(input,deps){
 const s={tenantId:req(input.tenantId,"tenantId"),actorId:req(input.actorId,"actorId"),
  branchId:req(input.branchId,"branchId"),idempotencyKey:req(input.idempotencyKey,"idempotencyKey"),action:"quality.pilot.record"};
 if(input.environment!=="staging")fail("QUALITY_PILOT_STAGING_ONLY","Pilot outcome writes are staging-only");
 if(typeof deps?.withTenantTransaction!=="function"||typeof deps?.authorize!=="function")fail("QUALITY_GATE_ADAPTER_REQUIRED","Transaction and authorization adapters are required");
 return deps.withTenantTransaction(s,async tx=>{
  if(!tx)fail("QUALITY_GATE_TRANSACTION_REQUIRED","Database transaction required");
  await deps.authorize(tx,s);
  const prior=await deps.findPilotByIdempotencyKey(tx,s);
  if(prior)return Object.freeze({status:"duplicate",pilotId:prior.id});
  const evidence=await deps.loadPilotEvidence(tx,{...s,pilotRunId:req(input.pilotRunId,"pilotRunId")});
  if(!evidence||evidence.tenantId!==s.tenantId||evidence.branchId!==s.branchId)fail("QUALITY_PILOT_SCOPE_MISMATCH","Pilot evidence must match tenant and branch");
  const result=evaluatePilotAcceptance(evidence);
  const saved=await deps.persistPilotOutcome(tx,{...s,pilotRunId:input.pilotRunId,...result});
  if(!saved?.id)fail("QUALITY_PILOT_PERSIST_FAILED","Pilot outcome was not persisted");
  await deps.appendAudit(tx,{...s,action:"quality.pilot.outcome_recorded",entityType:"quality_pilot_run",entityId:saved.id,
   metadata:{status:result.status,missing:result.missing}});
  return Object.freeze({status:result.status,pilotId:saved.id,missing:result.missing});
 });
}

/** Rollback orchestration is restricted to staging and requires independent approval. */
export async function authorizeStagingRollback(input,deps){
 const s={tenantId:req(input.tenantId,"tenantId"),actorId:req(input.actorId,"actorId"),
  branchId:req(input.branchId,"branchId"),idempotencyKey:req(input.idempotencyKey,"idempotencyKey"),action:"quality.rollback.authorize"};
 if(input.environment!=="staging")fail("QUALITY_ROLLBACK_STAGING_ONLY","Rollback authorization is staging-only");
 return deps.withTenantTransaction(s,async tx=>{
  await deps.authorize(tx,s);
  const deployment=await deps.loadDeploymentForRollback(tx,{...s,deploymentId:req(input.deploymentId,"deploymentId")});
  if(!deployment||deployment.tenantId!==s.tenantId||deployment.branchId!==s.branchId)fail("QUALITY_ROLLBACK_SCOPE_MISMATCH","Deployment must match tenant and branch");
  if(deployment.status!=="failed"&&deployment.status!=="degraded")fail("QUALITY_ROLLBACK_NOT_REQUIRED","Only failed or degraded staging deployments may be rolled back");
  const approval=await deps.loadIndependentRollbackApproval(tx,{...s,deploymentId:deployment.id});
  if(!approval?.approved||approval.approvedBy===s.actorId||!approval.evidenceReference)fail("QUALITY_ROLLBACK_APPROVAL_REQUIRED","Independent approval and evidence are required");
  const rollback=await deps.persistRollbackAuthorization(tx,{...s,deploymentId:deployment.id,approvalId:approval.id});
  if(!rollback?.id)fail("QUALITY_ROLLBACK_PERSIST_FAILED","Rollback authorization was not persisted");
  await deps.appendAudit(tx,{...s,action:"quality.rollback.authorized",entityType:"quality_rollback",entityId:rollback.id});
  return Object.freeze({status:"authorized",rollbackId:rollback.id});
 });
}
