/**
 * Additional acceptance rules for end-to-end D'LIce FnB workflows.
 * Pure functions only: persistence, locking, authorization and audit remain server responsibilities.
 */
const fail=(code,details={})=>({ok:false,code,...details});
const ok=(value={})=>({ok:true,...value});
const str=v=>typeof v==="string"&&v.trim().length>0;
const int=v=>Number.isSafeInteger(v);
const date=v=>typeof v==="string"&&!Number.isNaN(Date.parse(v));

export function calculateLoyaltyEarn({eligible_net_idr,rate_bps,cap_points=Number.MAX_SAFE_INTEGER,minimum_spend_idr=0}={}){
 if(!int(eligible_net_idr)||eligible_net_idr<0||!int(rate_bps)||rate_bps<0||rate_bps>10000||!int(cap_points)||cap_points<0||!int(minimum_spend_idr)||minimum_spend_idr<0)return fail("INVALID_EARN_RULE");
 if(eligible_net_idr<minimum_spend_idr)return ok({points:0,reason:"MINIMUM_SPEND_NOT_MET"});
 return ok({points:Math.min(Math.floor(eligible_net_idr*rate_bps/10000),cap_points)});
}
export function validateCustomerMerge({tenant_id,source_tenant_id,target_tenant_id,source_customer_id,target_customer_id,source_has_open_redemptions,reason,approved_by}={}){
 if(!str(tenant_id)||tenant_id!==source_tenant_id||tenant_id!==target_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 if(!str(source_customer_id)||!str(target_customer_id)||source_customer_id===target_customer_id)return fail("INVALID_CUSTOMER_MERGE");
 if(source_has_open_redemptions===true)return fail("OPEN_REDEMPTIONS_MUST_BE_RESOLVED");
 if(!str(reason)||!str(approved_by))return fail("MERGE_APPROVAL_EVIDENCE_REQUIRED");
 return ok({status:"ready_for_atomic_merge",source_customer_id,target_customer_id});
}
export function validateCampaignSend({tenant_id,campaign_tenant_id,channel,eligible_customer_ids=[],suppressed_customer_ids=[],consent_checked_at,content_approved_by,scheduled_at,now,provider_connection_status}={}){
 if(!str(tenant_id)||tenant_id!==campaign_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 if(!["email","sms","whatsapp"].includes(channel)||!Array.isArray(eligible_customer_ids)||eligible_customer_ids.length===0)return fail("INVALID_CAMPAIGN_AUDIENCE");
 if(!date(consent_checked_at)||!date(scheduled_at)||!date(now)||Date.parse(consent_checked_at)>Date.parse(now))return fail("CONSENT_RECHECK_REQUIRED");
 if(!str(content_approved_by))return fail("CONTENT_APPROVAL_REQUIRED");
 if(provider_connection_status!=="active")return fail("CHANNEL_CONNECTION_NOT_ACTIVE");
 const suppressed=new Set(suppressed_customer_ids);
 const recipients=eligible_customer_ids.filter(id=>!suppressed.has(id));
 if(!recipients.length)return fail("NO_CONSENTED_RECIPIENTS");
 return ok({status:"queued",recipient_count:recipients.length,scheduled_at});
}

export function validateShiftAssignment({tenant_id,employee_tenant_id,employee_id,branch_id,starts_at,ends_at,existingAssignments=[],required_position_id,position_id,employee_status="active"}={}){
 if(!str(tenant_id)||tenant_id!==employee_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 if(![employee_id,branch_id,position_id].every(str)||!date(starts_at)||!date(ends_at)||Date.parse(ends_at)<=Date.parse(starts_at))return fail("INVALID_SHIFT_ASSIGNMENT");
 if(employee_status!=="active")return fail("EMPLOYEE_NOT_ACTIVE");
 if(required_position_id&&required_position_id!==position_id)return fail("POSITION_MISMATCH");
 const overlap=existingAssignments.some(a=>a.employee_id===employee_id&&a.status!=="cancelled"&&date(a.starts_at)&&date(a.ends_at)&&Date.parse(starts_at)<Date.parse(a.ends_at)&&Date.parse(ends_at)>Date.parse(a.starts_at));
 if(overlap)return fail("SHIFT_OVERLAP");
 return ok({assignment:{tenant_id,employee_id,branch_id,position_id,starts_at,ends_at,status:"scheduled"}});
}
export function validateLeaveRequest({tenant_id,employee_tenant_id,employee_id,starts_on,ends_on,leave_type,available_days,requested_days,coverage_employee_id,coverage_approved}={}){
 if(!str(tenant_id)||tenant_id!==employee_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 if(!str(employee_id)||!date(starts_on)||!date(ends_on)||Date.parse(ends_on)<Date.parse(starts_on))return fail("INVALID_LEAVE_PERIOD");
 if(!["annual","sick","unpaid","maternity","paternity","other"].includes(leave_type))return fail("INVALID_LEAVE_TYPE");
 if(!int(available_days)||!int(requested_days)||requested_days<1)return fail("INVALID_LEAVE_BALANCE");
 if(leave_type==="annual"&&requested_days>available_days)return fail("INSUFFICIENT_LEAVE_BALANCE");
 if(!str(coverage_employee_id)||coverage_approved!==true)return fail("SHIFT_COVERAGE_REQUIRED");
 return ok({status:"submitted",employee_id,starts_on,ends_on,leave_type,requested_days});
}
export function validateOvertime({tenant_id,employee_tenant_id,employee_id,branch_id,shift_id,minutes,reason,approved_by,employee_approver_id,period_minutes,period_cap_minutes}={}){
 if(!str(tenant_id)||tenant_id!==employee_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 if(![employee_id,branch_id,shift_id,reason,approved_by].every(str)||!int(minutes)||minutes<1||!int(period_minutes)||!int(period_cap_minutes))return fail("INVALID_OVERTIME_REQUEST");
 if(employee_id===employee_approver_id)return fail("SELF_APPROVAL_FORBIDDEN");
 if(period_minutes+minutes>period_cap_minutes)return fail("OVERTIME_CAP_EXCEEDED");
 return ok({status:"approved",minutes,total_period_minutes:period_minutes+minutes});
}

export function validateDeliveryTransition({tenant_id,fulfillment_tenant_id,from,to,provider_event_id,proof_of_delivery,failed_reason,occurred_at}={}){
 if(!str(tenant_id)||tenant_id!==fulfillment_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 const transitions={queued:["booked","cancelled"],booked:["dispatched","cancelled","failed"],dispatched:["in_transit","delivered","failed"],in_transit:["delivered","failed"],failed:["booked","cancelled"],delivered:[],cancelled:[]};
 if(!transitions[from]||!transitions[from].includes(to))return fail("INVALID_DELIVERY_TRANSITION");
 if(!str(provider_event_id)||!date(occurred_at))return fail("PROVIDER_EVENT_EVIDENCE_REQUIRED");
 if(to==="delivered"&&!str(proof_of_delivery))return fail("POD_REQUIRED");
 if(to==="failed"&&!str(failed_reason))return fail("FAILURE_REASON_REQUIRED");
 return ok({next_status:to});
}
export function validateFranchiseApplication({tenant_id,application_tenant_id,applicant_name,territory,financial_review,site_feasibility,legal_review,approved_by,conflict_check_passed}={}){
 if(!str(tenant_id)||tenant_id!==application_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 if(![applicant_name,territory].every(str))return fail("APPLICATION_IDENTITY_REQUIRED");
 if(financial_review!=="passed"||site_feasibility!=="passed"||legal_review!=="passed"||conflict_check_passed!==true)return fail("DUE_DILIGENCE_INCOMPLETE");
 if(!str(approved_by))return fail("FRANCHISE_APPROVAL_REQUIRED");
 return ok({status:"approved_for_agreement",territory});
}
export function validateFranchiseOpening({tenant_id,agreement_tenant_id,agreement_status,site_approved,training_completed,food_safety_passed,systems_ready,opening_checklist_passed,tenant_provisioning_status}={}){
 if(!str(tenant_id)||tenant_id!==agreement_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 if(agreement_status!=="signed")return fail("SIGNED_AGREEMENT_REQUIRED");
 if([site_approved,training_completed,food_safety_passed,systems_ready,opening_checklist_passed].some(v=>v!==true))return fail("OPENING_READINESS_INCOMPLETE");
 if(tenant_provisioning_status!=="verified")return fail("TENANT_PROVISIONING_NOT_VERIFIED");
 return ok({status:"ready_to_open"});
}

export function validateBiSnapshot({tenant_id,snapshot_tenant_id,period_start,period_end,source_watermark,source_expected_count,source_processed_count,reconciliation_difference,generated_at,now,max_age_minutes=60,version,previous_version}={}){
 if(!str(tenant_id)||tenant_id!==snapshot_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 if(!date(period_start)||!date(period_end)||Date.parse(period_end)<Date.parse(period_start)||!date(source_watermark)||!date(generated_at)||!date(now))return fail("INVALID_BI_SNAPSHOT");
 if(!int(source_expected_count)||!int(source_processed_count)||source_expected_count<0||source_processed_count<0||source_processed_count!==source_expected_count)return fail("SOURCE_COMPLETENESS_FAILED");
 if(reconciliation_difference!==0)return fail("BI_RECONCILIATION_FAILED");
 if(!int(max_age_minutes)||max_age_minutes<1||Date.parse(now)-Date.parse(source_watermark)>max_age_minutes*60000)return fail("SOURCE_DATA_STALE");
 if(!int(version)||version<1||(previous_version!==undefined&&version<=previous_version))return fail("INVALID_SNAPSHOT_VERSION");
 return ok({status:"reconciled",version,generated_at});
}
export function validateTenantLifecycle({tenant_id,from,to,owner_approval,open_financial_obligations,active_branches,retention_policy_confirmed,offboarding_export_verified}={}){
 if(!str(tenant_id))return fail("TENANT_REQUIRED");
 const transitions={trial:["active","suspended","offboarding"],active:["suspended","offboarding"],suspended:["active","offboarding"],offboarding:["closed"],closed:[]};
 if(!transitions[from]||!transitions[from].includes(to))return fail("INVALID_TENANT_TRANSITION");
 if(to==="active"&&owner_approval!==true)return fail("TENANT_ACTIVATION_APPROVAL_REQUIRED");
 if(to==="offboarding"&&(open_financial_obligations>0||active_branches>0))return fail("TENANT_OBLIGATIONS_REMAIN");
 if(to==="closed"&&(retention_policy_confirmed!==true||offboarding_export_verified!==true))return fail("OFFBOARDING_EVIDENCE_REQUIRED");
 return ok({status:to});
}
export function validateProcurementApproval({tenant_id,po_tenant_id,requested_by,approved_by,amount_idr,approval_limit_idr,approval_policy_version,supplier_active,branch_active}={}){
 if(!str(tenant_id)||tenant_id!==po_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 if(![requested_by,approved_by,approval_policy_version].every(str)||requested_by===approved_by)return fail("SEPARATION_OF_DUTIES_REQUIRED");
 if(!int(amount_idr)||amount_idr<0||!int(approval_limit_idr)||approval_limit_idr<0)return fail("INVALID_APPROVAL_AMOUNT");
 if(amount_idr>approval_limit_idr)return fail("APPROVAL_LIMIT_EXCEEDED");
 if(supplier_active!==true||branch_active!==true)return fail("SUPPLIER_OR_BRANCH_INACTIVE");
 return ok({status:"approved",approval_policy_version});
}
export function validateProcurementReceipt({tenant_id,po_tenant_id,ordered_quantity,received_quantity,accepted_quantity,damaged_quantity,receipt_accepted,received_by,approved_by}={}){
 if(!str(tenant_id)||tenant_id!==po_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 if(![ordered_quantity,received_quantity,accepted_quantity,damaged_quantity].every(v=>Number.isSafeInteger(v)&&v>=0))return fail("INVALID_RECEIPT_QUANTITY");
 if(received_quantity!==accepted_quantity+damaged_quantity||received_quantity>ordered_quantity)return fail("RECEIPT_QUANTITY_MISMATCH");
 if(receipt_accepted!==true||!str(received_by)||!str(approved_by)||received_by===approved_by)return fail("RECEIPT_APPROVAL_REQUIRED");
 return ok({status:"accepted",accepted_quantity,damaged_quantity});
}
export function validateExecutiveDrilldown({actor_tenant_ids=[],resource_tenant_id,actor_branch_ids=[],resource_branch_id,requested_level,resource_level,platform_owner_verified=false}={}){
 if(!str(resource_tenant_id)||!["company","region","branch","shift","transaction"].includes(requested_level)||!["company","region","branch","shift","transaction"].includes(resource_level))return fail("INVALID_DRILLDOWN_SCOPE");
 if(!platform_owner_verified&&!actor_tenant_ids.includes(resource_tenant_id))return fail("TENANT_SCOPE_MISMATCH");
 if(!platform_owner_verified&&resource_branch_id&&!actor_branch_ids.includes(resource_branch_id))return fail("BRANCH_SCOPE_MISMATCH");
 const order=["company","region","branch","shift","transaction"];
 if(order.indexOf(resource_level)>order.indexOf(requested_level))return fail("DRILLDOWN_LEVEL_ESCALATION");
 return ok({allowed:true});
}
export function validateExecutiveTarget({tenant_id,target_tenant_id,metric_key,period_start,period_end,target_value,actual_value,unit,source_reconciled}={}){
 if(!str(tenant_id)||tenant_id!==target_tenant_id)return fail("TENANT_SCOPE_MISMATCH");
 if(![metric_key,unit].every(str)||!date(period_start)||!date(period_end)||Date.parse(period_end)<Date.parse(period_start))return fail("INVALID_TARGET_PERIOD");
 if(typeof target_value!=="number"||!Number.isFinite(target_value)||typeof actual_value!=="number"||!Number.isFinite(actual_value))return fail("INVALID_TARGET_VALUE");
 if(source_reconciled!==true)return fail("TARGET_SOURCE_NOT_RECONCILED");
 return ok({variance:actual_value-target_value,achievement_ratio:target_value===0?null:actual_value/target_value});
}
