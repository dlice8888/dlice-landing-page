import test from 'node:test';
import assert from 'node:assert/strict';
import {
 calculateLoyaltyEarn,validateCustomerMerge,validateCampaignSend,
 validateAttendanceSequence,validateShiftAssignment,validateLeaveRequest,validateOvertime,
 validateDeliveryTransition,validateFranchiseApplication,validateFranchiseOpening,
 validateBiSnapshot,validateTenantLifecycle,validateProcurementApproval,
 validateProcurementReceipt,validateExecutiveDrilldown,validateExecutiveTarget,
} from '../../src/fnb-domain-acceptance-rules.mjs';

test('CRM loyalty earn is bounded by rate, minimum spend and cap',()=>{
 assert.deepEqual(calculateLoyaltyEarn({eligible_net_idr:100000,rate_bps:100}),{ok:true,points:1000});
 assert.equal(calculateLoyaltyEarn({eligible_net_idr:1000,rate_bps:100,minimum_spend_idr:5000}).reason,'MINIMUM_SPEND_NOT_MET');
 assert.equal(calculateLoyaltyEarn({eligible_net_idr:100000,rate_bps:100,cap_points:500}).points,500);
});
test('CRM customer merge requires same tenant, resolved vouchers and approval',()=>{
 const input={tenant_id:'t1',source_tenant_id:'t1',target_tenant_id:'t1',source_customer_id:'c1',target_customer_id:'c2',source_has_open_redemptions:false,reason:'duplicate identity',approved_by:'owner'};
 assert.equal(validateCustomerMerge(input).ok,true);
 assert.equal(validateCustomerMerge({...input,target_tenant_id:'t2'}).code,'TENANT_SCOPE_MISMATCH');
 assert.equal(validateCustomerMerge({...input,source_has_open_redemptions:true}).code,'OPEN_REDEMPTIONS_MUST_BE_RESOLVED');
});
test('CRM campaign send excludes suppressed and requires fresh consent and active provider',()=>{
 const input={tenant_id:'t1',campaign_tenant_id:'t1',channel:'whatsapp',eligible_customer_ids:['c1','c2'],suppressed_customer_ids:['c2'],consent_checked_at:'2026-11-25T08:00:00Z',content_approved_by:'owner',scheduled_at:'2026-11-26T08:00:00Z',now:'2026-11-25T09:00:00Z',provider_connection_status:'active'};
 assert.equal(validateCampaignSend(input).recipient_count,1);
 assert.equal(validateCampaignSend({...input,provider_connection_status:'disabled'}).code,'CHANNEL_CONNECTION_NOT_ACTIVE');
});
test('HR attendance sequence requires clock-in before breaks and clock-out',()=>{
 assert.equal(validateAttendanceSequence({last_event:null,event_type:'clock_in'}).ok,true);
 assert.equal(validateAttendanceSequence({last_event:null,event_type:'clock_out'}).code,'INVALID_ATTENDANCE_SEQUENCE');
 assert.equal(validateAttendanceSequence({last_event:'clock_in',event_type:'break_start'}).ok,true);
 assert.equal(validateAttendanceSequence({last_event:'break_start',event_type:'clock_out'}).code,'INVALID_ATTENDANCE_SEQUENCE');
 assert.equal(validateAttendanceSequence({last_event:'break_end',event_type:'clock_out'}).ok,true);
});
test('HR shift assignment rejects overlaps and inactive staff',()=>{
 const input={tenant_id:'t1',employee_tenant_id:'t1',employee_id:'e1',branch_id:'b1',starts_at:'2026-11-25T08:00:00Z',ends_at:'2026-11-25T16:00:00Z',existingAssignments:[{employee_id:'e1',starts_at:'2026-11-25T12:00:00Z',ends_at:'2026-11-25T20:00:00Z',status:'scheduled'}],position_id:'cashier',employee_status:'active'};
 assert.equal(validateShiftAssignment(input).code,'SHIFT_OVERLAP');
 assert.equal(validateShiftAssignment({...input,existingAssignments:[],employee_status:'inactive'}).code,'EMPLOYEE_NOT_ACTIVE');
});
test('HR leave requires balance and approved shift coverage',()=>{
 const input={tenant_id:'t1',employee_tenant_id:'t1',employee_id:'e1',starts_on:'2026-12-01',ends_on:'2026-12-03',leave_type:'annual',available_days:5,requested_days:3,coverage_employee_id:'e2',coverage_approved:true};
 assert.equal(validateLeaveRequest(input).status,'submitted');
 assert.equal(validateLeaveRequest({...input,requested_days:6}).code,'INSUFFICIENT_LEAVE_BALANCE');
 assert.equal(validateLeaveRequest({...input,coverage_approved:false}).code,'SHIFT_COVERAGE_REQUIRED');
});
test('HR overtime enforces independent approval and period cap',()=>{
 const input={tenant_id:'t1',employee_tenant_id:'t1',employee_id:'e1',branch_id:'b1',shift_id:'s1',minutes:60,reason:'peak demand',approved_by:'manager',employee_approver_id:'manager',period_minutes:120,period_cap_minutes:240};
 assert.equal(validateOvertime(input).status,'approved');
 assert.equal(validateOvertime({...input,employee_approver_id:'e1'}).code,'SELF_APPROVAL_FORBIDDEN');
 assert.equal(validateOvertime({...input,period_minutes:200}).code,'OVERTIME_CAP_EXCEEDED');
});
test('Delivery transition requires allowed state and proof of delivery',()=>{
 const input={tenant_id:'t1',fulfillment_tenant_id:'t1',from:'in_transit',to:'delivered',provider_event_id:'ev1',occurred_at:'2026-11-25T09:00:00Z',proof_of_delivery:'photo-ref'};
 assert.equal(validateDeliveryTransition(input).next_status,'delivered');
 assert.equal(validateDeliveryTransition({...input,proof_of_delivery:null}).code,'POD_REQUIRED');
 assert.equal(validateDeliveryTransition({...input,to:'booked'}).code,'INVALID_DELIVERY_TRANSITION');
});
test('Franchise due diligence must pass before approval',()=>{
 const input={tenant_id:'t1',application_tenant_id:'t1',applicant_name:'Applicant',territory:'Jakarta Selatan',financial_review:'passed',site_feasibility:'passed',legal_review:'passed',approved_by:'committee',conflict_check_passed:true};
 assert.equal(validateFranchiseApplication(input).status,'approved_for_agreement');
 assert.equal(validateFranchiseApplication({...input,legal_review:'pending'}).code,'DUE_DILIGENCE_INCOMPLETE');
});
test('Franchise opening requires signed contract and verified tenant provisioning',()=>{
 const input={tenant_id:'t1',agreement_tenant_id:'t1',agreement_status:'signed',site_approved:true,training_completed:true,food_safety_passed:true,systems_ready:true,opening_checklist_passed:true,tenant_provisioning_status:'verified'};
 assert.equal(validateFranchiseOpening(input).status,'ready_to_open');
 assert.equal(validateFranchiseOpening({...input,tenant_provisioning_status:'pending'}).code,'TENANT_PROVISIONING_NOT_VERIFIED');
});
test('BI snapshot requires complete, fresh and reconciled sources',()=>{
 const input={tenant_id:'t1',snapshot_tenant_id:'t1',period_start:'2026-11-01',period_end:'2026-11-24',source_watermark:'2026-11-25T08:30:00Z',source_expected_count:100,source_processed_count:100,reconciliation_difference:0,generated_at:'2026-11-25T08:40:00Z',now:'2026-11-25T09:00:00Z',max_age_minutes:60,version:2,previous_version:1};
 assert.equal(validateBiSnapshot(input).status,'reconciled');
 assert.equal(validateBiSnapshot({...input,source_processed_count:99}).code,'SOURCE_COMPLETENESS_FAILED');
 assert.equal(validateBiSnapshot({...input,reconciliation_difference:100}).code,'BI_RECONCILIATION_FAILED');
});
test('SaaS tenant lifecycle is gated by approval and offboarding evidence',()=>{
 const input={tenant_id:'t1',from:'trial',to:'active',owner_approval:true};
 assert.equal(validateTenantLifecycle(input).status,'active');
 assert.equal(validateTenantLifecycle({...input,owner_approval:false}).code,'TENANT_ACTIVATION_APPROVAL_REQUIRED');
 assert.equal(validateTenantLifecycle({tenant_id:'t1',from:'active',to:'offboarding'}).code,'TENANT_OBLIGATIONS_REMAIN');
 assert.equal(validateTenantLifecycle({tenant_id:'t1',from:'offboarding',to:'closed',retention_policy_confirmed:true,offboarding_export_verified:false}).code,'OFFBOARDING_EVIDENCE_REQUIRED');
});
test('Procurement approval enforces segregation, limits and active master data',()=>{
 const input={tenant_id:'t1',po_tenant_id:'t1',requested_by:'buyer',approved_by:'manager',amount_idr:100000,approval_limit_idr:200000,approval_policy_version:'v2',supplier_active:true,branch_active:true};
 assert.equal(validateProcurementApproval(input).status,'approved');
 assert.equal(validateProcurementApproval({...input,approved_by:'buyer'}).code,'SEPARATION_OF_DUTIES_REQUIRED');
 assert.equal(validateProcurementApproval({...input,amount_idr:300000}).code,'APPROVAL_LIMIT_EXCEEDED');
});
test('Procurement receipt reconciles accepted and damaged quantities',()=>{
 const input={tenant_id:'t1',po_tenant_id:'t1',ordered_quantity:10,received_quantity:9,accepted_quantity:8,damaged_quantity:1,receipt_accepted:true,received_by:'warehouse',approved_by:'manager'};
 assert.equal(validateProcurementReceipt(input).status,'accepted');
 assert.equal(validateProcurementReceipt({...input,received_quantity:10}).code,'RECEIPT_QUANTITY_MISMATCH');
});
test('Executive drilldown respects tenant, branch and level boundaries',()=>{
 const input={actor_tenant_ids:['t1'],resource_tenant_id:'t1',actor_branch_ids:['b1'],resource_branch_id:'b1',max_level:'transaction',resource_level:'shift'};
 assert.equal(validateExecutiveDrilldown(input).allowed,true);
 assert.equal(validateExecutiveDrilldown({...input,resource_tenant_id:'t2'}).code,'TENANT_SCOPE_MISMATCH');
 assert.equal(validateExecutiveDrilldown({...input,resource_level:'transaction',max_level:'branch'}).code,'DRILLDOWN_LEVEL_ESCALATION');
});
test('Executive targets require reconciled sources and return variance',()=>{
 const input={tenant_id:'t1',target_tenant_id:'t1',metric_key:'net_sales',period_start:'2026-11-01',period_end:'2026-11-30',target_value:1000000,actual_value:900000,unit:'IDR',source_reconciled:true};
 assert.equal(validateExecutiveTarget(input).variance,-100000);
 assert.equal(validateExecutiveTarget({...input,source_reconciled:false}).code,'TARGET_SOURCE_NOT_RECONCILED');
});
