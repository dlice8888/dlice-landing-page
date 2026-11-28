import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const required = (v: unknown, name: string) => {
  if (typeof v !== "string" || !v.trim()) throw new Error(`Missing ${name}`);
  return v.trim();
};
const unwrap = (result: any, operation: string) => {
  if (result.error) {
    const error = new Error(`Branch Operations ${operation} failed`);
    (error as any).code = result.error.code ?? "BRANCH_OPS_PERSISTENCE_FAILED";
    (error as any).details = result.error.message;
    throw error;
  }
  return result.data;
};

export function createBranchOperationsRepository(
  serviceClient: SupabaseClient,
  scope: { tenantId: string; branchId: string; actorId: string },
) {
  const tenantId = required(scope.tenantId, "tenantId");
  const branchId = required(scope.branchId, "branchId");
  const actorId = required(scope.actorId, "actorId");
  const common = { p_tenant_id: tenantId, p_branch_id: branchId, p_actor_id: actorId };
  const call = async (name: string, args: Record<string, unknown>, label: string) =>
    unwrap(await serviceClient.rpc(name, { ...common, ...args }), label);
  const scoped = (table: string) => serviceClient.from(table).select("*").eq("tenant_id", tenantId).eq("branch_id", branchId);

  return {
    registerEquipment: (v: any) => call("branch_ops_register_equipment", {
      p_asset_code: required(v.assetCode, "assetCode"),
      p_name: required(v.name, "name"),
    }, "registerEquipment"),
    updateTaskStatus: (v: any) => call("branch_ops_update_task_status", {
      p_task_id: required(v.taskId, "taskId"),
      p_status: required(v.status, "status"),
    }, "updateTaskStatus"),
    updateIncidentStatus: (v: any) => call("branch_ops_update_incident_status", {
      p_incident_id: required(v.incidentId, "incidentId"),
      p_status: required(v.status, "status"),
    }, "updateIncidentStatus"),
    updateWorkOrderStatus: (v: any) => call("branch_ops_update_work_order_status", {
      p_work_order_id: required(v.workOrderId, "workOrderId"),
      p_status: required(v.status, "status"),
    }, "updateWorkOrderStatus"),
    createTask: (v: any) => call("branch_ops_create_task", {
      p_assignee_id: required(v.assigneeId, "assigneeId"),
      p_idempotency_key: required(v.idempotencyKey, "idempotencyKey"),
      p_title: required(v.title, "title"),
      p_description: v.description ?? null,
      p_due_at: required(v.dueAt, "dueAt"),
      p_priority: v.priority ?? "normal",
      p_source_type: v.sourceType ?? "manual",
      p_source_id: v.sourceId ?? null,
    }, "createTask"),
    recordIncident: (v: any) => call("branch_ops_record_incident", {
      p_idempotency_key: required(v.idempotencyKey, "idempotencyKey"),
      p_category: required(v.category, "category"),
      p_description: required(v.description, "description"),
      p_severity: required(v.severity, "severity"),
      p_occurred_at: v.occurredAt ?? null,
      p_evidence_asset_ids: Array.isArray(v.evidenceAssetIds) ? [...new Set(v.evidenceAssetIds)] : [],
    }, "recordIncident"),
    createMaintenanceOrder: (v: any) => call("branch_ops_create_maintenance_order", {
      p_equipment_id: required(v.equipmentId, "equipmentId"),
      p_idempotency_key: required(v.idempotencyKey, "idempotencyKey"),
      p_maintenance_type: required(v.maintenanceType, "maintenanceType"),
      p_scheduled_at: required(v.scheduledAt, "scheduledAt"),
      p_description: required(v.description, "description"),
      p_assigned_to: v.assignedTo ?? null,
    }, "createMaintenanceOrder"),
    registerEvidenceAsset: (v: any) => call("branch_ops_register_evidence_asset", {
      p_object_path: required(v.objectPath, "objectPath"),
      p_purpose: required(v.purpose, "purpose"),
      p_mime_type: required(v.mimeType, "mimeType"),
      p_size_bytes: v.sizeBytes,
    }, "registerEvidenceAsset"),
    submitComplianceCheck: (v: any) => call("branch_ops_submit_compliance_check", {
      p_check_key: required(v.checkKey, "checkKey"),
      p_title: required(v.title, "title"),
      p_weight: Number(v.weight),
      p_business_date: required(v.businessDate, "businessDate"),
      p_evidence_asset_id: required(v.evidenceAssetId, "evidenceAssetId"),
    }, "submitComplianceCheck"),
    reviewComplianceCheck: (v: any) => call("branch_ops_review_compliance_check", {
      p_check_id: required(v.checkId, "checkId"),
      p_result: required(v.result, "result"),
    }, "reviewComplianceCheck"),
    publishComplianceSnapshot: (v: any) => call("branch_ops_publish_compliance_snapshot", {
      p_period_start: required(v.periodStart, "periodStart"),
      p_period_end: required(v.periodEnd, "periodEnd"),
      p_idempotency_key: required(v.idempotencyKey, "idempotencyKey"),
      p_source_revision: required(v.sourceRevision, "sourceRevision"),
    }, "publishComplianceSnapshot"),
    async list(kind: string) {
      const map: Record<string, [string, string]> = {
        tasks: ["branch_ops_tasks", "due_at"],
        incidents: ["branch_ops_incidents", "created_at"],
        maintenance: ["branch_ops_work_orders", "scheduled_at"],
        compliance: ["branch_ops_compliance_snapshots", "period_end"],
        "compliance-checks": ["branch_ops_compliance_checks", "business_date"],
        equipment: ["branch_ops_equipment", "name"],
      };
      const selected = map[kind];
      if (!selected) throw new Error("Unsupported list kind");
      const query = scoped(selected[0]).order(selected[1], { ascending: kind === "tasks" || kind === "maintenance" }).limit(200);
      return unwrap(await query, `list:${kind}`) ?? [];
    },
  };
}
