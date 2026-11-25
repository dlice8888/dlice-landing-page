import test from 'node:test';
import assert from 'node:assert/strict';
import {
  validateAttendanceEvent, validateTimesheetApproval, validatePayrollRun,
  validateDeliveryQuote, validateDeliveryWebhook, calculateFranchiseRoyalty,
  validateKpiDefinition, authorizeEntitlement, validateThreeWayMatch,
  validateExecutiveAlertResolution, validateDeliveryTransition, validateSupplierTenantLink,
  validateBiSnapshotPublication, validateSaasSubscriptionChange, validateFranchiseApproval,
} from '../../src/fnb-cross-domain-rules.mjs';

test('HR attendance is tenant-scoped and server event metadata is required', () => {
  assert.equal(validateAttendanceEvent({ tenant_id: 't1', employee_tenant_id: 't2' }).code, 'TENANT_SCOPE_MISMATCH');
  const result = validateAttendanceEvent({ tenant_id: 't1', employee_tenant_id: 't1', employee_id: 'e1', branch_id: 'b1', event_type: 'clock_in', occurred_at: '2026-11-25T08:00:00Z', source: 'kiosk', idempotency_key: 'k1' });
  assert.equal(result.ok, true);
  assert.equal(validateAttendanceEvent({ tenant_id: 't1', employee_tenant_id: 't1', employee_id: 'e1', branch_id: 'b1', event_type: 'unknown', occurred_at: '2026-11-25T08:00:00Z', source: 'kiosk', idempotency_key: 'k1' }).code, 'INVALID_ATTENDANCE_EVENT');
});

test('HR timesheet forbids self-approval and payroll requires approved time', () => {
  const timesheet = { tenant_id: 't1', timesheet_tenant_id: 't1', employee_id: 'e1', branch_id: 'b1', period_start: '2026-11-01', period_end: '2026-11-30', total_minutes: 9000, approved_by: 'manager-1', approver_employee_id: 'e1', attendance_event_ids: ['a1'], status: 'submitted' };
  assert.equal(validateTimesheetApproval(timesheet).code, 'SELF_APPROVAL_FORBIDDEN');
  assert.equal(validateTimesheetApproval({ ...timesheet, approver_employee_id: 'manager-1' }).ok, true);
  assert.equal(validatePayrollRun({ tenant_id: 't1', payroll_tenant_id: 't1', period_start: '2026-11-01', period_end: '2026-11-30', gross_amount: 100000, deductions_amount: 10000, currency: 'IDR', idempotency_key: 'p1' }).code, 'APPROVED_TIMESHEETS_REQUIRED');
});

test('delivery quote separates customer fee, subsidy, and estimated provider cost', () => {
  const quote = validateDeliveryQuote({ tenant_id: 't1', order_tenant_id: 't1', order_id: 'o1', provider: 'manual', customer_fee: 10000, merchant_subsidy: 5000, estimated_cost: 18000, currency: 'IDR', quoted_at: '2026-11-25T08:00:00Z', expires_at: '2026-11-25T08:10:00Z' });
  assert.equal(quote.quote.estimated_cost, 18000);
  assert.equal(validateDeliveryQuote({ ...{ tenant_id: 't1', order_tenant_id: 't1', order_id: 'o1', provider: 'provider-x', customer_fee: 10000, merchant_subsidy: 0, estimated_cost: 10000, currency: 'IDR', quoted_at: '2026-11-25T08:00:00Z', expires_at: '2026-11-25T08:10:00Z' } }).code, 'PROVIDER_QUOTE_REFERENCE_REQUIRED');
});

test('delivery webhook rejects duplicate provider events', () => {
  const event = { tenant_id: 't1', fulfillment_tenant_id: 't1', fulfillment_id: 'f1', provider_event_id: 'ev1', event_type: 'in_transit', occurred_at: '2026-11-25T08:00:00Z' };
  assert.equal(validateDeliveryWebhook(event).ok, true);
  assert.equal(validateDeliveryWebhook({ ...event, existingProviderEventIds: ['ev1'] }).code, 'DUPLICATE_PROVIDER_EVENT');
});

test('franchise royalty uses effective contract version and basis points', () => {
  const input = { tenant_id: 't1', contract_tenant_id: 't1', contract_version: 'v3', effective_from: '2026-01-01', effective_until: '2026-12-31', business_date: '2026-11-25', eligible_net_sales: 1000000, rate_bps: 500, minimum_amount: 1000, currency: 'IDR' };
  assert.equal(calculateFranchiseRoyalty(input).amount, 50000);
  assert.equal(calculateFranchiseRoyalty({ ...input, business_date: '2027-01-01' }).code, 'CONTRACT_NOT_EFFECTIVE');
});

test('BI KPI requires lineage, timezone, owner, new version, and reconciliation', () => {
  const input = { tenant_id: 't1', definition_tenant_id: 't1', metric_key: 'net_sales', formula: 'gross-refunds-discounts', source_lineage: ['orders', 'refunds'], timezone: 'Asia/Jakarta', owner: 'finance', version: 2, published_version: 1, reconciliation_status: 'passed' };
  assert.equal(validateKpiDefinition(input).definition.status, 'published');
  assert.equal(validateKpiDefinition({ ...input, reconciliation_status: 'pending' }).code, 'KPI_RECONCILIATION_REQUIRED');
});

test('SaaS entitlements are fail-closed for tenant, status, feature, and quota', () => {
  const input = { tenant_id: 't1', membership_tenant_id: 't1', entitlement: 'multi_branch', plan_entitlements: ['multi_branch'], tenant_status: 'active', usage: 4, quota: 5 };
  assert.equal(authorizeEntitlement(input).allowed, true);
  assert.equal(authorizeEntitlement({ ...input, tenant_status: 'suspended' }).code, 'TENANT_NOT_ACTIVE');
  assert.equal(authorizeEntitlement({ ...input, usage: 5 }).code, 'QUOTA_EXCEEDED');
  assert.equal(authorizeEntitlement({ ...input, membership_tenant_id: 't2' }).code, 'TENANT_SCOPE_MISMATCH');
});

test('procurement three-way match requires accepted receipt and supplier consistency', () => {
  const input = { tenant_id: 't1', po_tenant_id: 't1', purchase_order_id: 'po1', supplier_id: 's1', invoice_supplier_id: 's1', ordered_amount: 100000, received_amount: 90000, invoiced_amount: 90500, tolerance_amount: 1000, receipt_accepted: true, invoice_reference: 'inv1' };
  assert.equal(validateThreeWayMatch(input).matched_amount, 90000);
  assert.equal(validateThreeWayMatch({ ...input, receipt_accepted: false }).code, 'RECEIPT_NOT_ACCEPTED');
  assert.equal(validateThreeWayMatch({ ...input, invoiced_amount: 95000 }).code, 'THREE_WAY_MATCH_VARIANCE');
});

test('executive alert requires independent verification and measured outcome', () => {
  const input = { tenant_id: 't1', alert_tenant_id: 't1', alert_id: 'a1', assignee_id: 'manager-1', resolution_evidence: 'task-77', verified_by: 'owner-1', measured_outcome: { recovered_sales: 500000 } };
  assert.equal(validateExecutiveAlertResolution(input).status, 'verified');
  assert.equal(validateExecutiveAlertResolution({ ...input, verified_by: 'manager-1' }).code, 'RESOLUTION_SELF_VERIFICATION_FORBIDDEN');
  assert.equal(validateExecutiveAlertResolution({ ...input, measured_outcome: null }).code, 'MEASURED_OUTCOME_REQUIRED');
});


test('Delivery transitions require unique events, settled payment and verified POD',()=>{
 assert.equal(validateDeliveryTransition({current_status:'booked',next_status:'picked_up',event_id:'event-0001'}).ok,true);
 assert.equal(validateDeliveryTransition({current_status:'booked',next_status:'delivered',event_id:'event-0002',has_verified_pod:true,payment_status:'paid'}).code,'INVALID_DELIVERY_TRANSITION');
 assert.equal(validateDeliveryTransition({current_status:'in_transit',next_status:'delivered',event_id:'event-0003',payment_status:'paid'}).code,'DELIVERY_PROOF_REQUIRED');
 assert.equal(validateDeliveryTransition({current_status:'in_transit',next_status:'delivered',event_id:'event-0004',has_verified_pod:true,payment_status:'pending'}).code,'DELIVERY_PAYMENT_NOT_SETTLED');
 assert.equal(validateDeliveryTransition({current_status:'in_transit',next_status:'delivered',event_id:'event-0005',has_verified_pod:true,payment_status:'paid'}).ok,true);
});
test('Supplier tenant ownership requires independent approval',()=>{
 assert.equal(validateSupplierTenantLink({tenant_id:'t1',supplier_id:'s1',relationship_type:'shared',status:'pending',created_by:'u1'}).ok,true);
 assert.equal(validateSupplierTenantLink({tenant_id:'t1',supplier_id:'s1',relationship_type:'exclusive',status:'active',created_by:'u1',approved_by:'u1'}).code,'INDEPENDENT_SUPPLIER_APPROVAL_REQUIRED');
 assert.equal(validateSupplierTenantLink({tenant_id:'t1',supplier_id:'s1',relationship_type:'exclusive',status:'active',created_by:'u1',approved_by:'u2'}).ok,true);
});
test('BI snapshot cannot publish without fresh complete lineage and reconciliation',()=>{
 const now=Date.parse('2026-11-25T12:00:00Z');
 const input={tenant_id:'t1',snapshot_tenant_id:'t1',metric_version:2,active_metric_version:2,now,freshness_sla_ms:3600000,watermarks:[{status:'complete',max_source_updated_at:'2026-11-25T11:30:00Z'}],reconciliations:[{status:'passed'}]};
 assert.equal(validateBiSnapshotPublication(input).ok,true);
 assert.equal(validateBiSnapshotPublication({...input,watermarks:[{status:'partial',max_source_updated_at:'2026-11-25T11:30:00Z'}]}).code,'BI_SOURCE_STALE_OR_INCOMPLETE');
 assert.equal(validateBiSnapshotPublication({...input,reconciliations:[{status:'failed'}]}).code,'BI_RECONCILIATION_NOT_PASSED');
});
test('SaaS activation requires billing verification outside a trial',()=>{
 assert.equal(validateSaasSubscriptionChange({tenant_id:'t1',subscription_tenant_id:'t1',current_status:'trialing',next_status:'active'}).ok,true);
 assert.equal(validateSaasSubscriptionChange({tenant_id:'t1',subscription_tenant_id:'t1',current_status:'past_due',next_status:'active'}).code,'BILLING_VERIFICATION_REQUIRED');
 assert.equal(validateSaasSubscriptionChange({tenant_id:'t1',subscription_tenant_id:'t1',current_status:'past_due',next_status:'active',billing_verified:true}).ok,true);
});
test('Franchise approval requires six completed due diligence checks and an approved site',()=>{
 const checks=['identity','financial','legal','operational','territory','reputation'].map(()=>({status:'passed',reviewer_id:'reviewer'}));
 const input={status:'due_diligence',due_diligence_checks:checks,approved_site_count:1,reviewer_id:'owner',applicant_id:'applicant'};
 assert.equal(validateFranchiseApproval(input).ok,true);
 assert.equal(validateFranchiseApproval({...input,due_diligence_checks:checks.slice(0,5)}).code,'FRANCHISE_DUE_DILIGENCE_INCOMPLETE');
 assert.equal(validateFranchiseApproval({...input,approved_site_count:0}).code,'FRANCHISE_SITE_NOT_APPROVED');
});
