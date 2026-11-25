/** D'Lice FnB OS shared workflow contracts. Pure rules only; persistence and authorization remain server-side. */
export const DOMAIN_WORKFLOWS = Object.freeze({
  crm: { aggregate:'customer_relationship', states:['prospect','active','suppressed','merged'], transitions:{
    activate:{from:['prospect'],to:'active',roles:['crm_manager','owner'],requires:['consent_recorded']},
    suppress:{from:['prospect','active'],to:'suppressed',roles:['crm_agent','crm_manager','owner'],requires:['suppression_reason']},
    reactivate:{from:['suppressed'],to:'active',roles:['crm_manager','owner'],requires:['fresh_consent']},
    merge:{from:['prospect','active'],to:'merged',roles:['crm_manager','owner'],requires:['canonical_customer_id','same_tenant']}
  }, invariants:['consent_before_marketing','immutable_points_ledger','idempotent_reward_redemption','tenant_scoped_customer_identity'] },
  hr: { aggregate:'employment_assignment', states:['draft','onboarding','active','leave','suspended','offboarding','terminated'], transitions:{
    submit_onboarding:{from:['draft'],to:'onboarding',roles:['hr_manager','owner'],requires:['employee_identity','position','branch_assignment']},
    activate:{from:['onboarding'],to:'active',roles:['hr_manager','owner'],requires:['onboarding_checklist_complete']},
    start_leave:{from:['active'],to:'leave',roles:['hr_manager','owner'],requires:['approved_leave_request']},
    return_from_leave:{from:['leave'],to:'active',roles:['hr_manager','owner'],requires:['return_date_reached']},
    suspend:{from:['active','leave'],to:'suspended',roles:['hr_manager','owner'],requires:['reason','audit_reference']},
    start_offboarding:{from:['active','leave','suspended'],to:'offboarding',roles:['hr_manager','owner'],requires:['offboarding_reason','effective_date']},
    terminate:{from:['offboarding'],to:'terminated',roles:['hr_manager','owner'],requires:['asset_clearance','access_revocation_reference','final_payroll_reference']}
  }, invariants:['server_timestamp_attendance','approved_timesheet_locked','payroll_uses_approved_time','terminated_access_revoked'] },
  delivery: { aggregate:'delivery_fulfillment', states:['awaiting_quote','quoted','booked','dispatched','in_transit','delivered','failed','cancelled','refunded'], transitions:{
    quote:{from:['awaiting_quote'],to:'quoted',roles:['system','branch_worker'],requires:['validated_address','provider_quote_or_manual_policy']},
    book:{from:['quoted'],to:'booked',roles:['system','branch_worker'],requires:['customer_acceptance','idempotency_key']},
    dispatch:{from:['booked'],to:'dispatched',roles:['system','branch_worker'],requires:['courier_booking_reference']},
    track:{from:['dispatched','in_transit'],to:'in_transit',roles:['system'],requires:['provider_event_id']},
    deliver:{from:['dispatched','in_transit'],to:'delivered',roles:['system','branch_worker'],requires:['proof_of_delivery']},
    fail:{from:['booked','dispatched','in_transit'],to:'failed',roles:['system','branch_worker'],requires:['failure_code']},
    cancel:{from:['awaiting_quote','quoted','booked'],to:'cancelled',roles:['branch_worker','owner'],requires:['cancellation_reason']},
    refund:{from:['failed','cancelled'],to:'refunded',roles:['finance','owner'],requires:['refund_reference']}
  }, invariants:['deduplicated_provider_callbacks','separate_customer_fee_subsidy_actual_cost','delivery_never_marks_payment_paid','explicit_manual_fallback_policy'] },
  franchise: { aggregate:'franchise_application', states:['lead','applied','due_diligence','feasibility_review','approved','contracting','opening','operating','rejected','terminated'], transitions:{
    apply:{from:['lead'],to:'applied',roles:['franchise_sales','owner'],requires:['applicant_identity','proposed_territory']},
    due_diligence:{from:['applied'],to:'due_diligence',roles:['franchise_manager','owner'],requires:['application_complete']},
    review_feasibility:{from:['due_diligence'],to:'feasibility_review',roles:['franchise_manager','finance','owner'],requires:['site_scorecard','financial_forecast']},
    approve:{from:['feasibility_review'],to:'approved',roles:['owner'],requires:['approval_decision','territory_clearance']},
    contract:{from:['approved'],to:'contracting',roles:['legal','owner'],requires:['signed_agreement','effective_date','expiry_date']},
    open:{from:['contracting'],to:'opening',roles:['franchise_manager','owner'],requires:['opening_project']},
    operate:{from:['opening'],to:'operating',roles:['franchise_manager','owner'],requires:['readiness_checklist_passed','tenant_scope_provisioned']},
    reject:{from:['applied','due_diligence','feasibility_review'],to:'rejected',roles:['owner'],requires:['decision_reason']},
    terminate:{from:['operating'],to:'terminated',roles:['owner'],requires:['termination_decision','settlement_reference']}
  }, invariants:['exclusive_or_explicitly_shared_territory','royalty_uses_effective_contract_version','franchise_access_is_tenant_and_territory_scoped'] },
  bi: { aggregate:'kpi_definition', states:['draft','review','published','deprecated'], transitions:{
    submit:{from:['draft'],to:'review',roles:['analyst','bi_manager','owner'],requires:['formula','source_lineage','timezone','owner']},
    publish:{from:['review'],to:'published',roles:['bi_manager','owner'],requires:['reconciliation_passed','version']},
    deprecate:{from:['published'],to:'deprecated',roles:['bi_manager','owner'],requires:['replacement_or_retirement_reason']}
  }, invariants:['published_kpi_versions_immutable','metric_has_lineage_timezone_owner','freshness_and_completeness_monitored','forecast_accuracy_measured'] },
  saas: { aggregate:'tenant_lifecycle', states:['provisioning','trial','active','past_due','suspended','offboarding','deleted'], transitions:{
    provision:{from:['provisioning'],to:'trial',roles:['platform_owner'],requires:['tenant_identity','owner_membership','isolation_checks_passed']},
    activate:{from:['trial','past_due'],to:'active',roles:['billing_system','platform_owner'],requires:['entitlement_set','billing_status_clear']},
    past_due:{from:['active'],to:'past_due',roles:['billing_system'],requires:['invoice_reference']},
    suspend:{from:['trial','active','past_due'],to:'suspended',roles:['platform_owner','billing_system'],requires:['suspension_reason','notice_reference']},
    resume:{from:['suspended'],to:'active',roles:['platform_owner','billing_system'],requires:['resolution_reference','isolation_recheck_passed']},
    offboard:{from:['active','past_due','suspended'],to:'offboarding',roles:['platform_owner'],requires:['approved_request','export_policy']},
    delete:{from:['offboarding'],to:'deleted',roles:['platform_owner'],requires:['retention_check','deletion_audit_reference']}
  }, invariants:['server_enforced_tenant_scope','server_enforced_entitlements','just_in_time_audited_support_access','retention_aware_offboarding'] },
  procurement: { aggregate:'purchase_requisition', states:['draft','submitted','approved','ordered','partially_received','received','matched','closed','rejected','cancelled'], transitions:{
    submit:{from:['draft'],to:'submitted',roles:['branch_worker','procurement','owner'],requires:['lines','need_by_date','branch_scope']},
    approve:{from:['submitted'],to:'approved',roles:['procurement_manager','owner'],requires:['approval_limit_check','separation_of_duties']},
    order:{from:['approved'],to:'ordered',roles:['procurement','owner'],requires:['supplier','effective_price_snapshot','po_number']},
    receive_partial:{from:['ordered','partially_received'],to:'partially_received',roles:['warehouse','branch_worker'],requires:['grn','quantity_and_quality_inspection']},
    receive_final:{from:['ordered','partially_received'],to:'received',roles:['warehouse','branch_worker'],requires:['grn','quantity_and_quality_inspection','stock_ledger_reference']},
    match_invoice:{from:['received'],to:'matched',roles:['finance','owner'],requires:['supplier_invoice','three_way_match_result']},
    close:{from:['matched'],to:'closed',roles:['finance','procurement_manager','owner'],requires:['ap_handoff_reference']},
    reject:{from:['submitted'],to:'rejected',roles:['procurement_manager','owner'],requires:['rejection_reason']},
    cancel:{from:['draft','submitted','approved'],to:'cancelled',roles:['procurement','owner'],requires:['cancellation_reason']}
  }, invariants:['idempotent_receiving','stock_only_from_accepted_grn','three_way_po_receipt_invoice_match','supplier_price_snapshotted_at_order'] },
  executive: { aggregate:'executive_alert', states:['detected','acknowledged','assigned','in_progress','resolved','verified','dismissed'], transitions:{
    acknowledge:{from:['detected'],to:'acknowledged',roles:['owner','group_manager','branch_manager'],requires:['acknowledged_by']},
    assign:{from:['acknowledged'],to:'assigned',roles:['owner','group_manager','branch_manager'],requires:['assignee','due_at']},
    start:{from:['assigned'],to:'in_progress',roles:['assignee'],requires:['action_note']},
    resolve:{from:['in_progress'],to:'resolved',roles:['assignee','owner'],requires:['resolution_evidence']},
    verify:{from:['resolved'],to:'verified',roles:['owner','group_manager'],requires:['measured_outcome']},
    dismiss:{from:['detected','acknowledged'],to:'dismissed',roles:['owner','group_manager'],requires:['dismissal_reason']}
  }, invariants:['kpis_from_authoritative_events','drilldown_preserves_role_and_tenant_scope','resolution_requires_measured_outcome','branch_cohorts_versioned'] }
});

const present = (v) => v !== undefined && v !== null && v !== '';
export function validateWorkflowCommand({domain,action,currentState,actorRoles=[],context={}}) {
  const wf=DOMAIN_WORKFLOWS[domain]; if(!wf) return {ok:false,code:'UNKNOWN_DOMAIN'};
  const t=wf.transitions[action]; if(!t) return {ok:false,code:'UNKNOWN_ACTION'};
  if(!t.from.includes(currentState)) return {ok:false,code:'INVALID_STATE_TRANSITION'};
  if(!t.roles.some(r=>actorRoles.includes(r))) return {ok:false,code:'ROLE_NOT_ALLOWED'};
  const missing=t.requires.filter(k=>!present(context[k]));
  if(missing.length) return {ok:false,code:'MISSING_REQUIREMENTS',missing};
  if(context.tenant_id&&context.resource_tenant_id&&context.tenant_id!==context.resource_tenant_id) return {ok:false,code:'TENANT_SCOPE_MISMATCH'};
  if(context.branch_id&&context.resource_branch_id&&context.branch_id!==context.resource_branch_id&&!actorRoles.includes('owner')) return {ok:false,code:'BRANCH_SCOPE_MISMATCH'};
  if(context.idempotency_key&&context.idempotency_key_reused===true) return {ok:false,code:'DUPLICATE_COMMAND'};
  return {ok:true,nextState:t.to,aggregate:wf.aggregate};
}
export function assertWorkflowDefinitionIntegrity() {
  for(const [domain,wf] of Object.entries(DOMAIN_WORKFLOWS)) {
    if(!wf.aggregate||!wf.states.length||!wf.invariants.length||!Object.keys(wf.transitions).length) throw new Error('Incomplete workflow: '+domain);
    for(const [action,t] of Object.entries(wf.transitions)) if(!wf.states.includes(t.to)||t.from.some(s=>!wf.states.includes(s))||!t.roles.length||!Array.isArray(t.requires)) throw new Error('Invalid transition: '+domain+'.'+action);
  }
  return true;
}
