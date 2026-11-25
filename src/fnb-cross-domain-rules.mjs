/**
 * Pure business invariants for the remaining priority domains.
 * These functions validate command payloads only. Server handlers must resolve
 * trusted tenant/branch scope, authorize roles, persist atomically, and audit.
 */
const fail = (code, details = {}) => ({ ok: false, code, ...details });
const ok = (value) => ({ ok: true, ...value });
const text = (v) => typeof v === "string" && v.trim().length > 0;
const integer = (v) => Number.isSafeInteger(v);
const date = (v) => typeof v === "string" && !Number.isNaN(Date.parse(v));

export function validateAttendanceEvent({ tenant_id, employee_tenant_id, employee_id, branch_id, event_type, occurred_at, source, idempotency_key } = {}) {
  if (!text(tenant_id) || tenant_id !== employee_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (![employee_id, branch_id, idempotency_key].every(text) || !date(occurred_at)) return fail("ATTENDANCE_REFERENCE_REQUIRED");
  if (!["clock_in", "clock_out", "break_start", "break_end"].includes(event_type)) return fail("INVALID_ATTENDANCE_EVENT");
  if (!["kiosk", "manager", "mobile", "system"].includes(source)) return fail("INVALID_ATTENDANCE_SOURCE");
  return ok({ event: Object.freeze({ tenant_id, employee_id, branch_id, event_type, occurred_at: new Date(occurred_at).toISOString(), source, idempotency_key }) });
}

export function validateTimesheetApproval({ tenant_id, timesheet_tenant_id, employee_id, branch_id, period_start, period_end, total_minutes, approved_by, approver_employee_id, attendance_event_ids = [], status } = {}) {
  if (!text(tenant_id) || tenant_id !== timesheet_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (![employee_id, branch_id, approved_by].every(text) || !date(period_start) || !date(period_end) || Date.parse(period_end) < Date.parse(period_start)) return fail("INVALID_TIMESHEET_SCOPE");
  if (!integer(total_minutes) || total_minutes < 0 || !Array.isArray(attendance_event_ids) || attendance_event_ids.length === 0) return fail("TIMESHEET_EVIDENCE_REQUIRED");
  if (employee_id === approver_employee_id) return fail("SELF_APPROVAL_FORBIDDEN");
  if (status !== "submitted") return fail("TIMESHEET_NOT_SUBMITTED");
  return ok({ approval: Object.freeze({ tenant_id, employee_id, branch_id, period_start, period_end, total_minutes, approved_by, attendance_event_ids: [...attendance_event_ids], status: "approved" }) });
}

export function validatePayrollRun({ tenant_id, payroll_tenant_id, period_start, period_end, approved_timesheet_ids = [], gross_amount, deductions_amount, currency, idempotency_key } = {}) {
  if (!text(tenant_id) || tenant_id !== payroll_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (!date(period_start) || !date(period_end) || Date.parse(period_end) < Date.parse(period_start)) return fail("INVALID_PAYROLL_PERIOD");
  if (!Array.isArray(approved_timesheet_ids) || approved_timesheet_ids.length === 0) return fail("APPROVED_TIMESHEETS_REQUIRED");
  if (![gross_amount, deductions_amount].every((v) => Number.isSafeInteger(v) && v >= 0) || deductions_amount > gross_amount) return fail("INVALID_PAYROLL_TOTALS");
  if (!text(currency) || !text(idempotency_key)) return fail("PAYROLL_REFERENCE_REQUIRED");
  return ok({ net_amount: gross_amount - deductions_amount, currency, idempotency_key });
}

export function validateDeliveryQuote({ tenant_id, order_tenant_id, order_id, provider, provider_quote_id, customer_fee, merchant_subsidy, estimated_cost, currency, quoted_at, expires_at } = {}) {
  if (!text(tenant_id) || tenant_id !== order_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (![order_id, provider, currency].every(text) || !date(quoted_at) || !date(expires_at) || Date.parse(expires_at) <= Date.parse(quoted_at)) return fail("INVALID_DELIVERY_QUOTE");
  if (![customer_fee, merchant_subsidy, estimated_cost].every((v) => Number.isSafeInteger(v) && v >= 0)) return fail("INVALID_DELIVERY_COST");
  if (!text(provider_quote_id) && provider !== "manual") return fail("PROVIDER_QUOTE_REFERENCE_REQUIRED");
  return ok({ quote: Object.freeze({ tenant_id, order_id, provider, provider_quote_id: provider_quote_id ?? null, customer_fee, merchant_subsidy, estimated_cost, currency, quoted_at, expires_at }) });
}

export function validateDeliveryWebhook({ tenant_id, fulfillment_tenant_id, fulfillment_id, provider_event_id, event_type, occurred_at, existingProviderEventIds = [] } = {}) {
  if (!text(tenant_id) || tenant_id !== fulfillment_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (![fulfillment_id, provider_event_id].every(text) || !date(occurred_at)) return fail("INVALID_PROVIDER_EVENT");
  if (existingProviderEventIds.includes(provider_event_id)) return fail("DUPLICATE_PROVIDER_EVENT");
  const allowed = ["booked", "dispatched", "in_transit", "delivered", "failed", "cancelled"];
  if (!allowed.includes(event_type)) return fail("UNSUPPORTED_DELIVERY_EVENT");
  return ok({ event: Object.freeze({ tenant_id, fulfillment_id, provider_event_id, event_type, occurred_at }) });
}

export function calculateFranchiseRoyalty({ tenant_id, contract_tenant_id, contract_version, effective_from, effective_until, business_date, eligible_net_sales, rate_bps, minimum_amount = 0, currency } = {}) {
  if (!text(tenant_id) || tenant_id !== contract_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (!text(contract_version) || !date(effective_from) || !date(business_date) || (effective_until && !date(effective_until))) return fail("INVALID_CONTRACT_VERSION");
  const day = Date.parse(business_date), start = Date.parse(effective_from), end = effective_until ? Date.parse(effective_until) : Number.POSITIVE_INFINITY;
  if (day < start || day > end) return fail("CONTRACT_NOT_EFFECTIVE");
  if (!integer(eligible_net_sales) || eligible_net_sales < 0 || !integer(rate_bps) || rate_bps < 0 || rate_bps > 10000 || !integer(minimum_amount) || minimum_amount < 0 || !text(currency)) return fail("INVALID_ROYALTY_INPUT");
  const calculatedBig = (BigInt(eligible_net_sales) * BigInt(rate_bps)) / 10000n;
  if (calculatedBig > BigInt(Number.MAX_SAFE_INTEGER)) return fail("ROYALTY_AMOUNT_OVERFLOW");
  const calculated = Number(calculatedBig);
  return ok({ amount: Math.max(calculated, minimum_amount), calculated_amount: calculated, currency, contract_version });
}

export function validateKpiDefinition({ tenant_id, definition_tenant_id, metric_key, formula, source_lineage = [], timezone, owner, version, reconciliation_status, published_version } = {}) {
  if (!text(tenant_id) || tenant_id !== definition_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (![metric_key, formula, timezone, owner].every(text) || !Array.isArray(source_lineage) || source_lineage.length === 0) return fail("KPI_LINEAGE_REQUIRED");
  if (!integer(version) || version < 1) return fail("INVALID_KPI_VERSION");
  if (published_version !== undefined && version <= published_version) return fail("KPI_VERSION_MUST_INCREASE");
  if (reconciliation_status !== "passed") return fail("KPI_RECONCILIATION_REQUIRED");
  return ok({ definition: Object.freeze({ tenant_id, metric_key, formula, source_lineage: [...source_lineage], timezone, owner, version, status: "published" }) });
}

export function authorizeEntitlement({ tenant_id, membership_tenant_id, entitlement, plan_entitlements = [], tenant_status, usage, quota } = {}) {
  if (!text(tenant_id) || tenant_id !== membership_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (tenant_status !== "active" && tenant_status !== "trial") return fail("TENANT_NOT_ACTIVE");
  if (!text(entitlement) || !plan_entitlements.includes(entitlement)) return fail("ENTITLEMENT_NOT_INCLUDED");
  if (quota !== null && quota !== undefined && (!integer(usage) || !integer(quota) || usage >= quota)) return fail("QUOTA_EXCEEDED");
  return ok({ allowed: true });
}

export function validateThreeWayMatch({ tenant_id, po_tenant_id, purchase_order_id, supplier_id, invoice_supplier_id, ordered_amount, received_amount, invoiced_amount, tolerance_amount = 0, receipt_accepted, invoice_reference } = {}) {
  if (!text(tenant_id) || tenant_id !== po_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (!text(purchase_order_id) || !text(supplier_id) || supplier_id !== invoice_supplier_id || !text(invoice_reference)) return fail("SUPPLIER_OR_DOCUMENT_MISMATCH");
  if (![ordered_amount, received_amount, invoiced_amount, tolerance_amount].every((v) => Number.isSafeInteger(v) && v >= 0)) return fail("INVALID_MATCH_AMOUNT");
  if (receipt_accepted !== true) return fail("RECEIPT_NOT_ACCEPTED");
  if (received_amount > ordered_amount) return fail("RECEIPT_EXCEEDS_ORDER");
  if (Math.abs(invoiced_amount - received_amount) > tolerance_amount) return fail("THREE_WAY_MATCH_VARIANCE", { variance: invoiced_amount - received_amount });
  return ok({ matched_amount: received_amount, purchase_order_id, invoice_reference });
}

export function validateExecutiveAlertResolution({ tenant_id, alert_tenant_id, alert_id, assignee_id, resolution_evidence, verified_by, measured_outcome, dismissed, dismissal_reason } = {}) {
  if (!text(tenant_id) || tenant_id !== alert_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (!text(alert_id)) return fail("ALERT_REFERENCE_REQUIRED");
  if (dismissed === true) return text(dismissal_reason) ? ok({ status: "dismissed" }) : fail("DISMISSAL_REASON_REQUIRED");
  if (![assignee_id, resolution_evidence, verified_by].every(text)) return fail("ALERT_RESOLUTION_EVIDENCE_REQUIRED");
  if (assignee_id === verified_by) return fail("RESOLUTION_SELF_VERIFICATION_FORBIDDEN");
  if (measured_outcome === undefined || measured_outcome === null || measured_outcome === "") return fail("MEASURED_OUTCOME_REQUIRED");
  return ok({ status: "verified", alert_id, verified_by, measured_outcome });
}


export function validateDeliveryTransition({ current_status, next_status, payment_status, has_verified_pod = false, event_id, idempotency_seen = false } = {}) {
  const transitions = {
    booked: ["picked_up", "failed", "cancelled"],
    picked_up: ["in_transit", "failed"],
    in_transit: ["delivered", "failed"],
    delivered: [], failed: [], cancelled: [],
  };
  if (!text(event_id)) return fail("DELIVERY_EVENT_REFERENCE_REQUIRED");
  if (idempotency_seen) return fail("DUPLICATE_DELIVERY_EVENT");
  if (!(transitions[current_status] || []).includes(next_status)) return fail("INVALID_DELIVERY_TRANSITION");
  if (next_status === "delivered" && has_verified_pod !== true) return fail("DELIVERY_PROOF_REQUIRED");
  if (next_status === "delivered" && !["paid", "verified", "settled"].includes(payment_status)) return fail("DELIVERY_PAYMENT_NOT_SETTLED");
  return ok({ current_status, next_status, event_id });
}

export function validateSupplierTenantLink({ tenant_id, supplier_id, relationship_type, status, created_by, approved_by } = {}) {
  if (![tenant_id, supplier_id, created_by].every(text)) return fail("SUPPLIER_LINK_SCOPE_REQUIRED");
  if (!["exclusive", "shared"].includes(relationship_type)) return fail("INVALID_SUPPLIER_RELATIONSHIP");
  if (status === "active" && (!text(approved_by) || approved_by === created_by)) return fail("INDEPENDENT_SUPPLIER_APPROVAL_REQUIRED");
  if (!["pending", "active", "suspended", "revoked"].includes(status)) return fail("INVALID_SUPPLIER_LINK_STATUS");
  return ok({ tenant_id, supplier_id, relationship_type, status });
}

export function validateBiSnapshotPublication({ tenant_id, snapshot_tenant_id, metric_version, active_metric_version, watermarks = [], reconciliations = [], now = Date.now(), freshness_sla_ms } = {}) {
  if (!text(tenant_id) || tenant_id !== snapshot_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  if (!integer(metric_version) || metric_version !== active_metric_version) return fail("BI_METRIC_VERSION_INACTIVE");
  if (!Array.isArray(watermarks) || watermarks.length === 0 || !Array.isArray(reconciliations) || reconciliations.length === 0) return fail("BI_EVIDENCE_REQUIRED");
  if (!integer(freshness_sla_ms) || freshness_sla_ms < 1) return fail("INVALID_BI_FRESHNESS_SLA");
  if (watermarks.some(w => w.status !== "complete" || !date(w.max_source_updated_at) || now - Date.parse(w.max_source_updated_at) > freshness_sla_ms)) return fail("BI_SOURCE_STALE_OR_INCOMPLETE");
  if (reconciliations.some(r => r.status !== "passed")) return fail("BI_RECONCILIATION_NOT_PASSED");
  return ok({ status: "publishable" });
}

export function validateSaasSubscriptionChange({ tenant_id, subscription_tenant_id, current_status, next_status, billing_verified = false, reason } = {}) {
  if (!text(tenant_id) || tenant_id !== subscription_tenant_id) return fail("TENANT_SCOPE_MISMATCH");
  const allowed = { trialing: ["active", "cancelled", "expired"], active: ["past_due", "suspended", "cancelled"], past_due: ["active", "suspended", "cancelled"], suspended: ["active", "cancelled"], cancelled: [], expired: [] };
  if (!(allowed[current_status] || []).includes(next_status)) return fail("INVALID_SUBSCRIPTION_TRANSITION");
  if (next_status === "active" && current_status !== "trialing" && billing_verified !== true) return fail("BILLING_VERIFICATION_REQUIRED");
  if (next_status === "cancelled" && !text(reason)) return fail("CANCELLATION_REASON_REQUIRED");
  return ok({ tenant_id, next_status });
}

export function validateFranchiseApproval({ status, due_diligence_checks = [], approved_site_count = 0, reviewer_id, applicant_id } = {}) {
  if (status !== "due_diligence") return fail("FRANCHISE_DUE_DILIGENCE_REQUIRED");
  if (!Array.isArray(due_diligence_checks) || due_diligence_checks.length !== 6 || due_diligence_checks.some(x => !["passed", "waived"].includes(x.status) || !text(x.reviewer_id))) return fail("FRANCHISE_DUE_DILIGENCE_INCOMPLETE");
  if (!integer(approved_site_count) || approved_site_count < 1) return fail("FRANCHISE_SITE_NOT_APPROVED");
  if (!text(reviewer_id) || reviewer_id === applicant_id) return fail("FRANCHISE_INDEPENDENT_REVIEW_REQUIRED");
  return ok({ status: "approved" });
}
