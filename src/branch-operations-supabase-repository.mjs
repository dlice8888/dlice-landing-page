/**
 * Server-only Supabase persistence adapter for Branch Operations.
 * Import only from Edge Functions/server runtimes. Never pass a service-role
 * client to browser code. Mutations are single Postgres RPC transactions.
 */
const required = (value, field) => {
  if (typeof value !== "string" || !value.trim()) {
    const error = new Error(`Missing ${field}`);
    error.code = "BRANCH_OPS_SCOPE_REQUIRED";
    throw error;
  }
  return value.trim();
};
const unwrap = ({ data, error }, operation) => {
  if (error) {
    const failure = new Error(`Branch Operations ${operation} failed`);
    failure.code = error.code === "PGRST202"
      ? "BRANCH_OPS_RPC_NOT_DEPLOYED"
      : error.code === "PGRST205"
        ? "BRANCH_OPS_TABLE_NOT_DEPLOYED"
        : error.code ?? "BRANCH_OPS_PERSISTENCE_FAILED";
    failure.details = error.message;
    throw failure;
  }
  return data;
};

export function createBranchOperationsRepository({ serviceClient, tenantId, branchId, actorId }) {
  if (!serviceClient || typeof serviceClient.rpc !== "function" || typeof serviceClient.from !== "function") {
    throw new TypeError("A server-side Supabase service client is required");
  }
  const scope = Object.freeze({
    tenantId: required(tenantId, "tenantId"),
    branchId: required(branchId, "branchId"),
    actorId: required(actorId, "actorId"),
  });
  const rpc = async (name, args, operation) =>
    unwrap(await serviceClient.rpc(name, { ...scopeArgs(), ...args }), operation);
  const scopeArgs = () => ({
    p_tenant_id: scope.tenantId,
    p_branch_id: scope.branchId,
    p_actor_id: scope.actorId,
  });
  const scopedQuery = (table, columns = "*") =>
    serviceClient.from(table).select(columns).eq("tenant_id", scope.tenantId).eq("branch_id", scope.branchId);
  const requiredTables = Object.freeze([
    "branch_ops_equipment",
    "branch_ops_tasks",
    "branch_ops_evidence_assets",
    "branch_ops_incidents",
    "branch_ops_work_orders",
    "branch_ops_compliance_checks",
    "branch_ops_compliance_snapshots",
  ]);
  const assertReady = async () => {
    for (const table of requiredTables) {
      const { error } = await serviceClient.from(table).select("id").limit(0);
      if (error) {
        const failure = new Error(`Branch Operations schema is unavailable: ${table}`);
        failure.code = error.code === "PGRST205" ? "BRANCH_OPS_TABLE_NOT_DEPLOYED" : error.code ?? "BRANCH_OPS_SCHEMA_CHECK_FAILED";
        failure.details = error.message;
        throw failure;
      }
    }
    return { ready: true, tables: [...requiredTables] };
  };

  return Object.freeze({
    scope,
    assertReady,
    async registerEquipment(input) {
      return rpc("branch_ops_register_equipment", {
        p_asset_code: required(input.assetCode, "assetCode"),
        p_name: required(input.name, "name"),
      }, "registerEquipment");
    },
    async updateTaskStatus(input) {
      return rpc("branch_ops_update_task_status", {
        p_task_id: required(input.taskId, "taskId"),
        p_status: required(input.status, "status"),
      }, "updateTaskStatus");
    },
    async updateIncidentStatus(input) {
      return rpc("branch_ops_update_incident_status", {
        p_incident_id: required(input.incidentId, "incidentId"),
        p_status: required(input.status, "status"),
      }, "updateIncidentStatus");
    },
    async updateWorkOrderStatus(input) {
      return rpc("branch_ops_update_work_order_status", {
        p_work_order_id: required(input.workOrderId, "workOrderId"),
        p_status: required(input.status, "status"),
      }, "updateWorkOrderStatus");
    },
    async createTask(input) {
      return rpc("branch_ops_create_task", {
        p_assignee_id: required(input.assigneeId, "assigneeId"),
        p_idempotency_key: required(input.idempotencyKey, "idempotencyKey"),
        p_title: required(input.title, "title"),
        p_description: input.description == null ? null : String(input.description).slice(0, 4000),
        p_due_at: required(input.dueAt, "dueAt"),
        p_priority: input.priority ?? "normal",
        p_source_type: input.sourceType ?? "manual",
        p_source_id: input.sourceId ?? null,
      }, "createTask");
    },
    async recordIncident(input) {
      const evidenceAssetIds = Array.isArray(input.evidenceAssetIds) ? [...new Set(input.evidenceAssetIds)] : [];
      return rpc("branch_ops_record_incident", {
        p_idempotency_key: required(input.idempotencyKey, "idempotencyKey"),
        p_category: required(input.category, "category"),
        p_description: required(input.description, "description"),
        p_severity: required(input.severity, "severity"),
        p_occurred_at: input.occurredAt ?? null,
        p_evidence_asset_ids: evidenceAssetIds,
      }, "recordIncident");
    },
    async createMaintenanceOrder(input) {
      return rpc("branch_ops_create_maintenance_order", {
        p_equipment_id: required(input.equipmentId, "equipmentId"),
        p_idempotency_key: required(input.idempotencyKey, "idempotencyKey"),
        p_maintenance_type: required(input.maintenanceType, "maintenanceType"),
        p_scheduled_at: required(input.scheduledAt, "scheduledAt"),
        p_description: required(input.description, "description"),
        p_assigned_to: input.assignedTo ?? null,
        p_evidence_asset_ids: Array.isArray(input.evidenceAssetIds) ? [...new Set(input.evidenceAssetIds)] : [],
      }, "createMaintenanceOrder");
    },
    async registerEvidenceAsset(input) {
      const result = await rpc("branch_ops_register_evidence_asset", {
        p_object_path: required(input.objectPath, "objectPath"),
        p_purpose: required(input.purpose, "purpose"),
        p_mime_type: required(input.mimeType, "mimeType"),
        p_size_bytes: input.sizeBytes,
      }, "registerEvidenceAsset");
      return { evidenceAssetId: result };
    },
    async verifyPrivateEvidenceOwnership(references, purpose) {
      if (!Array.isArray(references) || references.length === 0) return true;
      const { data, error } = await serviceClient.from("branch_ops_evidence_assets")
        .select("id,tenant_id,branch_id,owner_user_id,purpose,retention_until,bucket_id,object_path")
        .eq("tenant_id", scope.tenantId)
        .eq("branch_id", scope.branchId)
        .eq("owner_user_id", scope.actorId)
        .eq("purpose", purpose)
        .eq("bucket_id", "branch-ops-evidence")
        .in("id", references);
      if (error) throw Object.assign(new Error("Evidence ownership lookup failed"), { code: error.code ?? "BRANCH_EVIDENCE_LOOKUP_FAILED" });
      if (!Array.isArray(data) || data.length !== new Set(references).size) return false;
      const now = Date.now();
      return data.every((item) =>
        item.tenant_id === scope.tenantId &&
        item.branch_id === scope.branchId &&
        item.owner_user_id === scope.actorId &&
        item.purpose === purpose &&
        item.bucket_id === "branch-ops-evidence" &&
        Date.parse(item.retention_until) > now &&
        typeof item.object_path === "string" &&
        item.object_path.startsWith(`${scope.tenantId}/${scope.branchId}/${scope.actorId}/`)
      );
    },
    async submitComplianceCheck(input) {
      return rpc("branch_ops_submit_compliance_check", {
        p_check_key: required(input.checkKey, "checkKey"),
        p_title: required(input.title, "title"),
        p_weight: Number(input.weight),
        p_business_date: required(input.businessDate, "businessDate"),
        p_evidence_asset_id: required(input.evidenceAssetId, "evidenceAssetId"),
      }, "submitComplianceCheck");
    },
    async reviewComplianceCheck(input) {
      return rpc("branch_ops_review_compliance_check", {
        p_check_id: required(input.checkId, "checkId"),
        p_result: required(input.result, "result"),
      }, "reviewComplianceCheck");
    },
    async publishComplianceSnapshot(input) {
      return rpc("branch_ops_publish_compliance_snapshot", {
        p_period_start: required(input.periodStart, "periodStart"),
        p_period_end: required(input.periodEnd, "periodEnd"),
        p_idempotency_key: required(input.idempotencyKey, "idempotencyKey"),
        p_source_revision: input.sourceRevision == null ? null : String(input.sourceRevision),
      }, "publishComplianceSnapshot");
    },
    async listTasks({ status, limit = 100 } = {}) {
      let query = scopedQuery("branch_ops_tasks").order("due_at", { ascending: true }).limit(Math.min(Math.max(Number(limit) || 100, 1), 200));
      if (status) query = query.eq("status", status);
      return unwrap(await query, "listTasks") ?? [];
    },
    async listIncidents({ status, limit = 100 } = {}) {
      let query = scopedQuery("branch_ops_incidents").order("created_at", { ascending: false }).limit(Math.min(Math.max(Number(limit) || 100, 1), 200));
      if (status) query = query.eq("status", status);
      return unwrap(await query, "listIncidents") ?? [];
    },
    async listMaintenanceOrders({ status, limit = 100 } = {}) {
      let query = scopedQuery("branch_ops_work_orders").order("scheduled_at", { ascending: true }).limit(Math.min(Math.max(Number(limit) || 100, 1), 200));
      if (status) query = query.eq("status", status);
      return unwrap(await query, "listMaintenanceOrders") ?? [];
    },
    async listEquipment({ limit = 200 } = {}) {
      const query = scopedQuery("branch_ops_equipment").order("name", { ascending: true }).limit(Math.min(Math.max(Number(limit) || 200, 1), 300));
      return unwrap(await query, "listEquipment") ?? [];
    },
    async listComplianceChecks({ limit = 200 } = {}) {
      const query = scopedQuery("branch_ops_compliance_checks").order("business_date", { ascending: false }).limit(Math.min(Math.max(Number(limit) || 200, 1), 300));
      return unwrap(await query, "listComplianceChecks") ?? [];
    },
    async listComplianceSnapshots({ limit = 24 } = {}) {
      const query = scopedQuery("branch_ops_compliance_snapshots")
        .order("period_end", { ascending: false })
        .limit(Math.min(Math.max(Number(limit) || 24, 1), 60));
      return unwrap(await query, "listComplianceSnapshots") ?? [];
    },
  });
}
