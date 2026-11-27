import test from "node:test";
import assert from "node:assert/strict";
import {
  createBranchTask,
  recordBranchIncident,
  createEquipmentMaintenanceOrder,
  publishBranchComplianceScore,
} from "../../src/branch-operations-workflows.mjs";

const base = {
  tenantId: "tenant-a", branchId: "branch-a", actorId: "manager-a",
  idempotencyKey: "branch-ops-key-0001",
};
const common = (overrides = {}) => ({
  withTenantTransaction: async (_scope, callback) => callback({ transaction: true }),
  authorize: async (_tx, scope) => {
    assert.equal(scope.tenantId, "tenant-a");
    assert.equal(scope.branchId, "branch-a");
  },
  appendAudit: async (_tx, event) => { assert.ok(event.action.startsWith("branch.")); },
  ...overrides,
});

test("branch task is tenant/branch scoped and idempotent", async () => {
  let persisted = 0;
  const deps = common({
    findBranchTaskByIdempotencyKey: async () => null,
    loadBranchAssignee: async () => ({ tenantId: "tenant-a", branchId: "branch-a", active: true }),
    persistBranchTask: async () => { persisted++; return { id: "task-a" }; },
  });
  const input = { ...base, title: "Closing checklist", dueAt: "2026-11-28T12:00:00Z", assigneeId: "staff-a" };
  assert.deepEqual(await createBranchTask(input, deps), { status: "created", taskId: "task-a" });
  assert.equal(persisted, 1);
});

test("branch task rejects cross-branch assignee before persistence", async () => {
  let persisted = false;
  const deps = common({
    findBranchTaskByIdempotencyKey: async () => null,
    loadBranchAssignee: async () => ({ tenantId: "tenant-a", branchId: "branch-b", active: true }),
    persistBranchTask: async () => { persisted = true; return { id: "bad" }; },
  });
  await assert.rejects(createBranchTask({ ...base, title: "Task", dueAt: "2026-11-28T12:00:00Z", assigneeId: "staff-b" }, deps),
    { code: "BRANCH_SCOPE_MISMATCH" });
  assert.equal(persisted, false);
});

test("branch task returns existing durable idempotency record without duplicate write", async () => {
  let persisted = false;
  const deps = common({ findBranchTaskByIdempotencyKey: async () => ({ id: "existing-task" }),
    persistBranchTask: async () => { persisted = true; } });
  const result = await createBranchTask({ ...base, title: "Task", dueAt: "2026-11-28T12:00:00Z", assigneeId: "staff-a" }, deps);
  assert.deepEqual(result, { status: "duplicate", taskId: "existing-task" });
  assert.equal(persisted, false);
});

test("critical incident requires evidence and creates escalation task atomically", async () => {
  let escalated = false;
  const deps = common({
    findBranchIncidentByIdempotencyKey: async () => null,
    persistBranchIncident: async (tx, row) => { assert.ok(tx.transaction); assert.deepEqual(row.evidenceReferences, ["private://incident/photo"]); return { id: "incident-a" }; },
    createIncidentEscalationTask: async (_tx, row) => { escalated = true; assert.equal(row.priority, "critical"); return { id: "task-escalation" }; },
  });
  const result = await recordBranchIncident({ ...base, category: "safety", description: "Gas leak", severity: "critical",
    evidenceReferences: ["private://incident/photo"] }, deps);
  assert.deepEqual(result, { status: "recorded", incidentId: "incident-a", escalationTaskId: "task-escalation" });
  assert.equal(escalated, true);
});

test("critical incident fails closed without evidence", async () => {
  let persisted = false;
  const deps = common({ findBranchIncidentByIdempotencyKey: async () => null,
    persistBranchIncident: async () => { persisted = true; } });
  await assert.rejects(recordBranchIncident({ ...base, category: "safety", description: "Hazard", severity: "critical" }, deps),
    { code: "BRANCH_INCIDENT_EVIDENCE_REQUIRED" });
  assert.equal(persisted, false);
});

test("maintenance order rejects retired equipment", async () => {
  let persisted = false;
  const deps = common({
    findMaintenanceOrderByIdempotencyKey: async () => null,
    loadBranchEquipmentForUpdate: async () => ({ tenantId: "tenant-a", branchId: "branch-a", status: "retired" }),
    persistMaintenanceOrder: async () => { persisted = true; },
  });
  await assert.rejects(createEquipmentMaintenanceOrder({ ...base, equipmentId: "fridge-a", maintenanceType: "preventive",
    scheduledAt: "2026-11-29T09:00:00Z", description: "Quarterly inspection" }, deps), { code: "BRANCH_EQUIPMENT_RETIRED" });
  assert.equal(persisted, false);
});

test("compliance snapshot cannot publish incomplete or unreconciled evidence", async () => {
  let persisted = false;
  const deps = common({
    findBranchComplianceSnapshotByIdempotencyKey: async () => null,
    loadBranchComplianceEvidence: async () => ({ approved: true, reconciled: false, requiredChecks: 5,
      completedChecks: 4, score: 80, evidenceReferences: ["a", "b", "c", "d"], sourceRevision: "rev-1" }),
    persistBranchComplianceSnapshot: async () => { persisted = true; },
  });
  await assert.rejects(publishBranchComplianceScore({ ...base, periodStart: "2026-11-01", periodEnd: "2026-11-30" }, deps),
    { code: "BRANCH_COMPLIANCE_EVIDENCE_INCOMPLETE" });
  assert.equal(persisted, false);
});

test("compliance snapshot publishes only complete approved reconciled evidence", async () => {
  const deps = common({
    findBranchComplianceSnapshotByIdempotencyKey: async () => null,
    loadBranchComplianceEvidence: async () => ({ approved: true, reconciled: true, requiredChecks: 2,
      completedChecks: 2, score: 96, evidenceReferences: ["private://1", "private://2"], sourceRevision: "branch-a:2026-11-30:v3" }),
    persistBranchComplianceSnapshot: async (_tx, row) => { assert.equal(row.score, 96); return { id: "snapshot-a" }; },
  });
  const result = await publishBranchComplianceScore({ ...base, periodStart: "2026-11-01", periodEnd: "2026-11-30" }, deps);
  assert.deepEqual(result, { status: "published", snapshotId: "snapshot-a", score: 96 });
});
