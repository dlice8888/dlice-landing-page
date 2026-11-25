import test from 'node:test';
import assert from 'node:assert/strict';
import {DOMAIN_WORKFLOWS,validateWorkflowCommand,assertWorkflowDefinitionIntegrity} from '../src/fnb-domain-workflows.mjs';

test('eight priority domains expose valid workflows and invariants',()=>{
  assert.deepEqual(Object.keys(DOMAIN_WORKFLOWS).sort(),['bi','crm','delivery','executive','franchise','hr','procurement','saas']);
  assert.equal(assertWorkflowDefinitionIntegrity(),true);
  for(const wf of Object.values(DOMAIN_WORKFLOWS)){assert.ok(wf.invariants.length);assert.ok(Object.keys(wf.transitions).length>=3);}
});
test('CRM requires consent and a CRM role',()=>{
  assert.equal(validateWorkflowCommand({domain:'crm',action:'activate',currentState:'prospect',actorRoles:['crm_manager']}).missing[0],'consent_recorded');
  assert.equal(validateWorkflowCommand({domain:'crm',action:'activate',currentState:'prospect',actorRoles:['crm_manager'],context:{consent_recorded:'c1'}}).nextState,'active');
  assert.equal(validateWorkflowCommand({domain:'crm',action:'activate',currentState:'prospect',actorRoles:['branch_worker'],context:{consent_recorded:'c1'}}).code,'ROLE_NOT_ALLOWED');
});
test('HR cannot skip offboarding to terminate employment',()=>{
  assert.equal(validateWorkflowCommand({domain:'hr',action:'terminate',currentState:'active',actorRoles:['hr_manager'],context:{asset_clearance:'ok',access_revocation_reference:'r1',final_payroll_reference:'p1'}}).code,'INVALID_STATE_TRANSITION');
});
test('delivery needs proof of delivery',()=>{
  assert.equal(validateWorkflowCommand({domain:'delivery',action:'deliver',currentState:'in_transit',actorRoles:['branch_worker']}).code,'MISSING_REQUIREMENTS');
});
test('franchise cannot operate before readiness and tenant provisioning',()=>{
  assert.equal(validateWorkflowCommand({domain:'franchise',action:'operate',currentState:'opening',actorRoles:['owner'],context:{readiness_checklist_passed:true}}).code,'MISSING_REQUIREMENTS');
});
test('BI KPI publication requires reconciliation',()=>{
  assert.equal(validateWorkflowCommand({domain:'bi',action:'publish',currentState:'review',actorRoles:['bi_manager'],context:{version:1}}).code,'MISSING_REQUIREMENTS');
});
test('SaaS tenant provisioning requires isolation proof',()=>{
  assert.equal(validateWorkflowCommand({domain:'saas',action:'provision',currentState:'provisioning',actorRoles:['platform_owner'],context:{tenant_identity:'t1',owner_membership:'u1'}}).code,'MISSING_REQUIREMENTS');
});
test('procurement receipt requires GRN inspection and stock ledger reference',()=>{
  assert.equal(validateWorkflowCommand({domain:'procurement',action:'receive_final',currentState:'ordered',actorRoles:['warehouse'],context:{grn:'g1',quantity_and_quality_inspection:true}}).code,'MISSING_REQUIREMENTS');
});
test('executive alert verification requires measured outcome',()=>{
  assert.equal(validateWorkflowCommand({domain:'executive',action:'verify',currentState:'resolved',actorRoles:['owner']}).code,'MISSING_REQUIREMENTS');
});
test('tenant/branch scope mismatches and duplicate commands are rejected',()=>{
  const base={domain:'crm',action:'suppress',currentState:'active',actorRoles:['crm_agent'],context:{suppression_reason:'opt-out'}};
  assert.equal(validateWorkflowCommand({...base,context:{...base.context,tenant_id:'A',resource_tenant_id:'B'}}).code,'TENANT_SCOPE_MISMATCH');
  assert.equal(validateWorkflowCommand({...base,context:{...base.context,branch_id:'A',resource_branch_id:'B'}}).code,'BRANCH_SCOPE_MISMATCH');
  assert.equal(validateWorkflowCommand({domain:'delivery',action:'book',currentState:'quoted',actorRoles:['branch_worker'],context:{customer_acceptance:true,idempotency_key:'k1',idempotency_key_reused:true}}).code,'DUPLICATE_COMMAND');
});

test('boolean prerequisites must be true, not merely present',()=>{
  assert.equal(validateWorkflowCommand({domain:'saas',action:'provision',currentState:'provisioning',actorRoles:['platform_owner'],context:{tenant_identity:'t1',owner_membership:'u1',isolation_checks_passed:false}}).code,'MISSING_REQUIREMENTS');
  assert.equal(validateWorkflowCommand({domain:'franchise',action:'operate',currentState:'opening',actorRoles:['owner'],context:{readiness_checklist_passed:false,tenant_scope_provisioned:true}}).code,'MISSING_REQUIREMENTS');
});
