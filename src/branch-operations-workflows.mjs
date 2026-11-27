/**
 * Branch operations transactional workflows.
 *
 * All writes require a tenant transaction, an in-transaction authorization
 * decision, tenant/branch-scoped repository adapters, durable idempotency and
 * append-only audit. Evidence references are opaque pointers; the repository
 * must verify private-storage ownership and retention before accepting them.
 */
const fail = (code, message) => { const error = new Error(message); error.code = code; throw error; };
const required = (value, field) => {
  if (typeof value !== "string" || !value.trim()) fail("BRANCH_WORKFLOW_INPUT_REQUIRED", field);
  return value.trim();
};
const adapter = (deps, name) => {
  if (typeof deps?.[name] !== "function") fail("BRANCH_WORKFLOW_ADAPTER_REQUIRED", name);
  return deps[name];
};
const scopeOf = (input, action) => ({
  tenantId: required(input?.tenantId, "tenantId"),
  branchId: required(input?.branchId, "branchId"),
  actorId: required(input?.actorId, "actorId"),
  idempotencyKey: required(input?.idempotencyKey, "idempotencyKey"),
  action,
});
const inBranchTransaction = (deps, scope, operation) =>
  adapter(deps, "withTenantTransaction")(scope, async (tx) => {
    if (!tx) fail("BRANCH_TRANSACTION_REQUIRED", "A database transaction is required");
    await adapter(deps, "authorize")(tx, scope);
    return operation(tx);
  });
const assertBranch = (record, scope, name) => {
  if (!record || record.tenantId !== scope.tenantId || record.branchId !== scope.branchId) {
    fail("BRANCH_SCOPE_MISMATCH", name);
  }
};
const audit = (deps, tx, scope, event) => adapter(deps, "appendAudit")(tx, {
  tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
  idempotencyKey: scope.idempotencyKey, ...event,
});

/** Create a branch task only after resolving a same-branch assignee and checklist. */
export async function createBranchTask(input, deps) {
  const scope = scopeOf(input, "branch.task.create");
  const title = required(input.title, "title");
  const dueAt = required(input.dueAt, "dueAt");
  const assigneeId = required(input.assigneeId, "assigneeId");
  const priority = input.priority ?? "normal";
  if (!["low", "normal", "high", "critical"].includes(priority)) fail("BRANCH_TASK_PRIORITY_INVALID", "Unsupported task priority");
  if (!Number.isFinite(Date.parse(dueAt))) fail("BRANCH_TASK_DUE_DATE_INVALID", "dueAt must be an ISO date/time");
  return inBranchTransaction(deps, scope, async (tx) => {
    const prior = await adapter(deps, "findBranchTaskByIdempotencyKey")(tx, scope);
    if (prior) return Object.freeze({ status: "duplicate", taskId: prior.id });
    const assignee = await adapter(deps, "loadBranchAssignee")(tx, { ...scope, assigneeId });
    assertBranch(assignee, scope, "assignee");
    if (assignee.active !== true) fail("BRANCH_TASK_ASSIGNEE_INACTIVE", "Assignee must be active");
    const task = await adapter(deps, "persistBranchTask")(tx, {
      ...scope, title, dueAt, assigneeId, priority,
      description: input.description == null ? null : String(input.description).slice(0, 4000),
      sourceType: input.sourceType ?? "manual", sourceId: input.sourceId ?? null,
    });
    if (!task?.id) fail("BRANCH_TASK_PERSIST_FAILED", "Task was not persisted");
    await audit(deps, tx, scope, { action: "branch.task.created", entityType: "branch_task", entityId: task.id });
    return Object.freeze({ status: "created", taskId: task.id });
  });
}

/** Record an incident; critical incidents require a persisted escalation task. */
export async function recordBranchIncident(input, deps) {
  const scope = scopeOf(input, "branch.incident.record");
  const category = required(input.category, "category");
  const description = required(input.description, "description");
  const severity = input.severity;
  if (!["low", "medium", "high", "critical"].includes(severity)) fail("BRANCH_INCIDENT_SEVERITY_INVALID", "Unsupported incident severity");
  const evidenceReferences = Array.isArray(input.evidenceReferences) ? [...new Set(input.evidenceReferences.map((v) => required(v, "evidenceReference"))] : [];
  return inBranchTransaction(deps, scope, async (tx) => {
    const prior = await adapter(deps, "findBranchIncidentByIdempotencyKey")(tx, scope);
    if (prior) return Object.freeze({ status: "duplicate", incidentId: prior.id, escalationTaskId: prior.escalationTaskId ?? null });
    if (severity === "critical" && evidenceReferences.length === 0) fail("BRANCH_INCIDENT_EVIDENCE_REQUIRED", "Critical incidents require evidence");
    const incident = await adapter(deps, "persistBranchIncident")(tx, {
      ...scope, category, description, severity, evidenceReferences,
      occurredAt: input.occurredAt ?? null,
    });
    if (!incident?.id) fail("BRANCH_INCIDENT_PERSIST_FAILED", "Incident was not persisted");
    let escalationTaskId = null;
    if (severity === "critical" || severity === "high") {
      const escalation = await adapter(deps, "createIncidentEscalationTask")(tx, {
        ...scope, incidentId: incident.id, priority: severity,
      });
      if (!escalation?.id) fail("BRANCH_INCIDENT_ESCALATION_FAILED", "High-severity incident requires a durable escalation task");
      escalationTaskId = escalation.id;
    }
    await audit(deps, tx, scope, { action: "branch.incident.recorded", entityType: "branch_incident", entityId: incident.id,
      metadata: { severity, escalationTaskId, evidenceCount: evidenceReferences.length } });
    return Object.freeze({ status: "recorded", incidentId: incident.id, escalationTaskId });
  });
}

/** Schedule preventive/corrective maintenance against a verified branch asset. */
export async function createEquipmentMaintenanceOrder(input, deps) {
  const scope = scopeOf(input, "branch.maintenance.create");
  const equipmentId = required(input.equipmentId, "equipmentId");
  const maintenanceType = input.maintenanceType;
  if (!["preventive", "corrective", "inspection"].includes(maintenanceType)) fail("BRANCH_MAINTENANCE_TYPE_INVALID", "Unsupported maintenance type");
  const scheduledAt = required(input.scheduledAt, "scheduledAt");
  if (!Number.isFinite(Date.parse(scheduledAt))) fail("BRANCH_MAINTENANCE_DATE_INVALID", "scheduledAt must be an ISO date/time");
  return inBranchTransaction(deps, scope, async (tx) => {
    const prior = await adapter(deps, "findMaintenanceOrderByIdempotencyKey")(tx, scope);
    if (prior) return Object.freeze({ status: "duplicate", workOrderId: prior.id });
    const equipment = await adapter(deps, "loadBranchEquipmentForUpdate")(tx, { ...scope, equipmentId });
    assertBranch(equipment, scope, "equipment");
    if (equipment.status === "retired") fail("BRANCH_EQUIPMENT_RETIRED", "Retired equipment cannot receive new work orders");
    const order = await adapter(deps, "persistMaintenanceOrder")(tx, {
      ...scope, equipmentId, maintenanceType, scheduledAt,
      description: required(input.description, "description"),
      assignedTo: input.assignedTo == null ? null : required(input.assignedTo, "assignedTo"),
    });
    if (!order?.id) fail("BRANCH_MAINTENANCE_PERSIST_FAILED", "Maintenance work order was not persisted");
    await audit(deps, tx, scope, { action: "branch.maintenance.created", entityType: "equipment_work_order", entityId: order.id });
    return Object.freeze({ status: "created", workOrderId: order.id });
  });
}

/** Publish a branch compliance score only from approved, complete, evidenced checks. */
export async function publishBranchComplianceScore(input, deps) {
  const scope = scopeOf(input, "branch.compliance.publish");
  const periodStart = required(input.periodStart, "periodStart");
  const periodEnd = required(input.periodEnd, "periodEnd");
  if (periodStart > periodEnd) fail("BRANCH_COMPLIANCE_PERIOD_INVALID", "periodStart must not exceed periodEnd");
  return inBranchTransaction(deps, scope, async (tx) => {
    const prior = await adapter(deps, "findBranchComplianceSnapshotByIdempotencyKey")(tx, scope);
    if (prior) return Object.freeze({ status: "duplicate", snapshotId: prior.id, score: prior.score });
    const evidence = await adapter(deps, "loadBranchComplianceEvidence")(tx, { ...scope, periodStart, periodEnd });
    if (!evidence || evidence.approved !== true || evidence.reconciled !== true ||
        !Number.isInteger(evidence.requiredChecks) || evidence.requiredChecks < 1 ||
        evidence.completedChecks !== evidence.requiredChecks ||
        !Number.isFinite(evidence.score) || evidence.score < 0 || evidence.score > 100 ||
        !Array.isArray(evidence.evidenceReferences) || evidence.evidenceReferences.length < evidence.requiredChecks) {
      fail("BRANCH_COMPLIANCE_EVIDENCE_INCOMPLETE", "All approved checks, evidence references and reconciliations are required");
    }
    const snapshot = await adapter(deps, "persistBranchComplianceSnapshot")(tx, {
      ...scope, periodStart, periodEnd, score: evidence.score,
      completedChecks: evidence.completedChecks, requiredChecks: evidence.requiredChecks,
      sourceRevision: required(evidence.sourceRevision, "sourceRevision"),
    });
    if (!snapshot?.id) fail("BRANCH_COMPLIANCE_SNAPSHOT_FAILED", "Compliance snapshot was not persisted");
    await audit(deps, tx, scope, { action: "branch.compliance.published", entityType: "branch_compliance_snapshot",
      entityId: snapshot.id, metadata: { score: evidence.score, completedChecks: evidence.completedChecks } });
    return Object.freeze({ status: "published", snapshotId: snapshot.id, score: evidence.score });
  });
}
