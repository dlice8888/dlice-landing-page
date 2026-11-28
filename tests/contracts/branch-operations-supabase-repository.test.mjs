import test from "node:test";
import assert from "node:assert/strict";
import { createBranchOperationsRepository } from "../../src/branch-operations-supabase-repository.mjs";

const scope = { tenantId: "tenant-a", branchId: "branch-a", actorId: "user-a" };

test("repository writes only through atomic RPC and always binds verified tenant/branch/actor", async () => {
  const calls = [];
  const client = {
    rpc: async (name, args) => { calls.push({ name, args }); return { data: { status: "created", taskId: "task-a" }, error: null }; },
    from: () => { throw new Error("No table query expected for atomic task creation"); },
  };
  const repo = createBranchOperationsRepository({ serviceClient: client, ...scope });
  const result = await repo.createTask({
    assigneeId: "staff-a", idempotencyKey: "task-idem-0001", title: "Closing",
    dueAt: "2026-11-28T12:00:00Z", priority: "high",
  });
  assert.equal(result.taskId, "task-a");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "branch_ops_create_task");
  assert.deepEqual(
    [calls[0].args.p_tenant_id, calls[0].args.p_branch_id, calls[0].args.p_actor_id],
    ["tenant-a", "branch-a", "user-a"],
  );
  assert.equal(calls[0].args.p_assignee_id, "staff-a");
});

test("repository rejects incomplete scope before issuing database calls", () => {
  let called = false;
  const client = { rpc: async () => { called = true; }, from: () => ({}) };
  assert.throws(() => createBranchOperationsRepository({ serviceClient: client, tenantId: "", branchId: "b", actorId: "u" }),
    { code: "BRANCH_OPS_SCOPE_REQUIRED" });
  assert.equal(called, false);
});

test("incident evidence ids are deduplicated before the atomic database write", async () => {
  let args;
  const client = {
    rpc: async (_name, value) => { args = value; return { data: { status: "recorded" }, error: null }; },
    from: () => ({}),
  };
  const repo = createBranchOperationsRepository({ serviceClient: client, ...scope });
  await repo.recordIncident({
    idempotencyKey: "incident-idem-001", category: "safety", description: "Hazard",
    severity: "critical", evidenceAssetIds: ["asset-a", "asset-a"],
  });
  assert.deepEqual(args.p_evidence_asset_ids, ["asset-a"]);
});

test("equipment registration and lifecycle transitions use server-scoped RPC calls", async () => {
  const calls = [];
  const client = {
    rpc: async (name, args) => { calls.push({ name, args }); return { data: { status: "ok" }, error: null }; },
    from: () => ({}),
  };
  const repo = createBranchOperationsRepository({ serviceClient: client, ...scope });
  await repo.registerEquipment({ assetCode: "FRIDGE-01", name: "Display chiller" });
  await repo.updateTaskStatus({ taskId: "task-a", status: "completed" });
  await repo.updateIncidentStatus({ incidentId: "incident-a", status: "resolved" });
  await repo.updateWorkOrderStatus({ workOrderId: "work-a", status: "in_progress" });
  assert.deepEqual(calls.map((call) => call.name), [
    "branch_ops_register_equipment",
    "branch_ops_update_task_status",
    "branch_ops_update_incident_status",
    "branch_ops_update_work_order_status",
  ]);
  assert.ok(calls.every((call) => call.args.p_tenant_id === scope.tenantId && call.args.p_branch_id === scope.branchId && call.args.p_actor_id === scope.actorId));
});
