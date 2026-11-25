import test from "node:test";
import assert from "node:assert/strict";
import {
  recordFoodSafetyInspection,
  initiateFoodRecall,
  recordSupplierQualityInspection,
  verifySupplierCorrectiveAction,
} from "../../src/quality-compliance-workflows.mjs";

const base = { tenantId: "tenant-a", branchId: "branch-a", actorId: "qa-a", idempotencyKey: "quality-key-0001" };
const policy = { id: "policy-a", tenantId: "tenant-a", branchId: "branch-a", status: "approved",
  minTempC: 0, maxTempC: 5, requiredAllergens: ["milk", "soy"] };

function common(overrides = {}) {
  const calls = [];
  return {
    calls,
    withTenantTransaction: async (_scope, cb) => cb({ tx: true }),
    authorize: async (_tx, scope) => calls.push(["authorize", scope.action]),
    appendAudit: async (_tx, event) => calls.push(["audit", event.action]),
    ...overrides,
  };
}

test("food safety inspection accepts only policy-compliant temperature and allergen declarations", async () => {
  const deps = common({
    findFoodSafetyInspectionByIdempotencyKey: async () => null,
    loadApprovedFoodSafetyPolicy: async () => policy,
    persistFoodSafetyInspection: async (_tx, row) => { depsRow = row; return { id: "inspection-a" }; },
    quarantineFoodLot: async () => ({ id: "quarantine-a" }),
  });
  let depsRow;
  const result = await recordFoodSafetyInspection({ ...base, sourceType: "receipt_item", sourceId: "receipt-item-a",
    lotCode: "LOT-A", policyId: "policy-a", measuredTempC: 4, declaredAllergens: ["milk", "soy"] }, deps);
  assert.equal(result.disposition, "accepted");
  assert.equal(depsRow.temperatureInRange, true);
  assert.equal(deps.calls.some(([kind]) => kind === "audit"), true);
});

test("out-of-policy temperature quarantines the food lot in the same transaction", async () => {
  const deps = common({
    findFoodSafetyInspectionByIdempotencyKey: async () => null,
    loadApprovedFoodSafetyPolicy: async () => policy,
    persistFoodSafetyInspection: async () => ({ id: "inspection-b" }),
    quarantineFoodLot: async (_tx, row) => { deps.quarantine = row; return { id: "quarantine-b" }; },
  });
  const result = await recordFoodSafetyInspection({ ...base, idempotencyKey: "quality-key-0002",
    sourceType: "production_batch", sourceId: "batch-a", lotCode: "LOT-B", policyId: "policy-a",
    measuredTempC: 9, declaredAllergens: ["milk", "soy"] }, deps);
  assert.equal(result.disposition, "quarantined");
  assert.deepEqual(deps.quarantine.reasonCodes, ["TEMPERATURE_OUT_OF_POLICY"]);
});

test("food safety refuses missing or unapproved policy before persistence", async () => {
  const deps = common({ findFoodSafetyInspectionByIdempotencyKey: async () => null,
    loadApprovedFoodSafetyPolicy: async () => ({ ...policy, status: "draft" }) });
  await assert.rejects(recordFoodSafetyInspection({ ...base, sourceType: "branch_check", sourceId: "check-a",
    lotCode: "LOT-C", policyId: "policy-a", measuredTempC: 3, declaredAllergens: [] }, deps),
  { code: "APPROVED_FOOD_SAFETY_POLICY_REQUIRED" });
});

test("food recall requires tenant-scoped lot and complete affected-order traceability", async () => {
  const deps = common({
    findFoodRecallByIdempotencyKey: async () => null,
    loadFoodLotForUpdate: async () => ({ tenantId: "tenant-a", branchId: "branch-a", lotCode: "LOT-D" }),
    findFoodLotDistributionImpact: async () => ({ affectedBranches: ["branch-a"], affectedOrders: ["order-a", "order-b"] }),
    persistFoodRecall: async () => ({ id: "recall-a" }),
    quarantineFoodLot: async () => ({ id: "quarantine-d" }),
  });
  const result = await initiateFoodRecall({ ...base, lotCode: "LOT-D", reason: "verified contamination", severity: "critical" }, deps);
  assert.equal(result.affectedBranchCount, 1);
  assert.equal(result.affectedOrderCount, 2);
});

test("supplier quality quarantines major/critical findings and opens a CAPA", async () => {
  const deps = common({
    findSupplierQualityInspectionByIdempotencyKey: async () => null,
    loadSupplierReceiptItemForUpdate: async () => ({ tenantId: "tenant-a", branchId: "branch-a", supplierId: "supplier-a", quantityReceived: 12 }),
    loadApprovedSupplierQualityPolicy: async () => ({ tenantId: "tenant-a", branchId: "branch-a", status: "approved", criticalFindingCodes: ["foreign-object"] }),
    persistSupplierQualityInspection: async () => ({ id: "inspection-supplier-a" }),
    quarantineSupplierReceiptQuantity: async () => ({ id: "supplier-quarantine-a" }),
    createSupplierCorrectiveAction: async () => ({ id: "capa-a" }),
  });
  const result = await recordSupplierQualityInspection({ ...base, receiptItemId: "receipt-item-a", policyId: "supplier-policy-a",
    findings: [{ code: "damaged-packaging", severity: "major" }] }, deps);
  assert.equal(result.disposition, "quarantined");
  assert.equal(result.capaId, "capa-a");
});

test("supplier quality requires a tenant-linked approved policy", async () => {
  const deps = common({
    findSupplierQualityInspectionByIdempotencyKey: async () => null,
    loadSupplierReceiptItemForUpdate: async () => ({ tenantId: "tenant-a", branchId: "branch-a", supplierId: "supplier-a", quantityReceived: 1 }),
    loadApprovedSupplierQualityPolicy: async () => ({ tenantId: "tenant-b", branchId: "branch-a", status: "approved", criticalFindingCodes: [] }),
  });
  await assert.rejects(recordSupplierQualityInspection({ ...base, receiptItemId: "receipt-a", policyId: "policy-a",
    findings: [{ code: "damage", severity: "minor" }] }, deps), { code: "QUALITY_SCOPE_MISMATCH" });
});

test("CAPA verification requires independent reviewer and evidence reference", async () => {
  const deps = common({
    loadSupplierCorrectiveActionForUpdate: async () => ({ tenantId: "tenant-a", branchId: "branch-a", id: "capa-a",
      status: "submitted", createdBy: "qa-a", submittedBy: "worker-b" }),
  });
  await assert.rejects(verifySupplierCorrectiveAction({ ...base, capaId: "capa-a", decision: "verified",
    evidenceReference: "private://capa/evidence" }, deps), { code: "INDEPENDENT_SUPPLIER_CAPA_REVIEWER_REQUIRED" });
});

test("CAPA quarantine release requires successful independent verification", async () => {
  const deps = common({
    loadSupplierCorrectiveActionForUpdate: async () => ({ tenantId: "tenant-a", branchId: "branch-a", id: "capa-a",
      status: "submitted", createdBy: "qa-b", submittedBy: "qa-c" }),
    recordSupplierCorrectiveActionVerification: async () => ({ id: "verification-a", status: "verified" }),
    releaseSupplierQuarantineAfterCapa: async () => ({ released: true }),
  });
  const result = await verifySupplierCorrectiveAction({ ...base, capaId: "capa-a", decision: "verified",
    evidenceReference: "private://capa/evidence", releaseQuarantine: true }, deps);
  assert.equal(result.status, "verified");
  assert.equal(result.quarantineReleaseRequested, true);
});
