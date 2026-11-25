/**
 * Food safety and supplier quality orchestration.
 *
 * These workflows deliberately require injected tenant transaction, policy,
 * repository and audit adapters. No policy threshold is hard-coded: approved
 * tenant/product policy is the source of truth. Quarantine and recall are
 * fail-closed when durable adapters are absent.
 */
const fail = (code, message) => {
  const error = new Error(message);
  error.code = code;
  throw error;
};
const required = (value, field) => {
  if (typeof value !== "string" || !value.trim()) fail("QUALITY_INPUT_REQUIRED", field);
  return value.trim();
};
const adapter = (deps, name) => {
  if (typeof deps?.[name] !== "function") fail("QUALITY_ADAPTER_REQUIRED", name);
  return deps[name];
};
const scopeOf = (input, action) => ({
  tenantId: required(input?.tenantId, "tenantId"),
  branchId: required(input?.branchId, "branchId"),
  actorId: required(input?.actorId, "actorId"),
  idempotencyKey: required(input?.idempotencyKey, "idempotencyKey"),
  action,
});
const assertScope = (record, scope, label) => {
  if (!record || record.tenantId !== scope.tenantId || record.branchId !== scope.branchId) {
    fail("QUALITY_SCOPE_MISMATCH", label);
  }
};
const transact = async (deps, scope, operation) => {
  return adapter(deps, "withTenantTransaction")(scope, async (tx) => {
    if (!tx) fail("QUALITY_TRANSACTION_REQUIRED", "A tenant-scoped transaction is required");
    await adapter(deps, "authorize")(tx, scope);
    return operation(tx);
  });
};
const audit = (deps, tx, scope, event) => adapter(deps, "appendAudit")(tx, Object.freeze({
  tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
  ...event,
}));

/**
 * Evaluate a cold-chain / food-handling inspection using an approved policy.
 * Out-of-policy temperature or allergen declaration mismatch quarantines the
 * lot in the same transaction as the immutable inspection evidence.
 */
export async function recordFoodSafetyInspection(input, deps) {
  const scope = scopeOf(input, "quality.food_safety.inspect");
  const sourceType = required(input.sourceType, "sourceType");
  if (!["receipt_item", "production_batch", "branch_check"].includes(sourceType)) {
    fail("FOOD_SAFETY_SOURCE_TYPE_INVALID", "Unsupported food safety source type");
  }
  const sourceId = required(input.sourceId, "sourceId");
  const lotCode = required(input.lotCode, "lotCode");
  const policyId = required(input.policyId, "policyId");
  const measuredTempC = Number(input.measuredTempC);
  if (!Number.isFinite(measuredTempC)) fail("FOOD_SAFETY_TEMPERATURE_INVALID", "A finite temperature in Celsius is required");
  if (!Array.isArray(input.declaredAllergens)) fail("FOOD_SAFETY_ALLERGENS_INVALID", "Declared allergens must be an array");

  return transact(deps, scope, async (tx) => {
    const existing = await adapter(deps, "findFoodSafetyInspectionByIdempotencyKey")(tx, scope);
    if (existing) return Object.freeze({ status: "duplicate", inspectionId: existing.id, disposition: existing.disposition });
    const policy = await adapter(deps, "loadApprovedFoodSafetyPolicy")(tx, { tenantId: scope.tenantId, branchId: scope.branchId, policyId });
    assertScope(policy, scope, "foodSafetyPolicy");
    if (policy.status !== "approved" || !Number.isFinite(policy.minTempC) ||
        !Number.isFinite(policy.maxTempC) || policy.minTempC > policy.maxTempC ||
        !Array.isArray(policy.requiredAllergens)) {
      fail("APPROVED_FOOD_SAFETY_POLICY_REQUIRED", "An approved, complete food-safety policy is required");
    }
    const declared = new Set(input.declaredAllergens.map((value) => required(value, "declaredAllergen")));
    const missingAllergens = policy.requiredAllergens.filter((value) => !declared.has(value));
    const temperatureInRange = measuredTempC >= policy.minTempC && measuredTempC <= policy.maxTempC;
    const disposition = temperatureInRange && missingAllergens.length === 0 ? "accepted" : "quarantined";
    const saved = await adapter(deps, "persistFoodSafetyInspection")(tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
      idempotencyKey: scope.idempotencyKey, sourceType, sourceId, lotCode, policyId,
      measuredTempC, minTempC: policy.minTempC, maxTempC: policy.maxTempC,
      declaredAllergens: [...declared].sort(), missingAllergens,
      temperatureInRange, disposition,
    });
    if (!saved?.id) fail("FOOD_SAFETY_INSPECTION_PERSIST_FAILED", "Inspection evidence was not persisted");
    if (disposition === "quarantined") {
      const quarantine = await adapter(deps, "quarantineFoodLot")(tx, {
        tenantId: scope.tenantId, branchId: scope.branchId, lotCode,
        inspectionId: saved.id, reasonCodes: [
          ...(!temperatureInRange ? ["TEMPERATURE_OUT_OF_POLICY"] : []),
          ...(missingAllergens.length ? ["ALLERGEN_DECLARATION_MISMATCH"] : []),
        ],
        idempotencyKey: scope.idempotencyKey,
      });
      if (!quarantine?.id) fail("FOOD_LOT_QUARANTINE_FAILED", "Unsafe lot must be durably quarantined");
    }
    await audit(deps, tx, scope, {
      action: disposition === "accepted" ? "quality.food_safety.accepted" : "quality.food_safety.quarantined",
      entityType: "food_safety_inspection", entityId: saved.id,
      idempotencyKey: scope.idempotencyKey,
    });
    return Object.freeze({ status: "recorded", inspectionId: saved.id, disposition, missingAllergens });
  });
}

/** Initiate a traceable food recall from an identified tenant lot. */
export async function initiateFoodRecall(input, deps) {
  const scope = scopeOf(input, "quality.food_recall.initiate");
  const lotCode = required(input.lotCode, "lotCode");
  const reason = required(input.reason, "reason");
  const severity = required(input.severity, "severity");
  if (!["low", "medium", "high", "critical"].includes(severity)) fail("FOOD_RECALL_SEVERITY_INVALID", "Unsupported recall severity");
  return transact(deps, scope, async (tx) => {
    const existing = await adapter(deps, "findFoodRecallByIdempotencyKey")(tx, scope);
    if (existing) return Object.freeze({ status: "duplicate", recallId: existing.id });
    const lot = await adapter(deps, "loadFoodLotForUpdate")(tx, { tenantId: scope.tenantId, branchId: scope.branchId, lotCode });
    assertScope(lot, scope, "foodLot");
    const impact = await adapter(deps, "findFoodLotDistributionImpact")(tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, lotCode,
    });
    if (!impact || !Array.isArray(impact.affectedBranches) || !Array.isArray(impact.affectedOrders)) {
      fail("FOOD_RECALL_TRACEABILITY_INCOMPLETE", "Affected branch and order traceability is required");
    }
    const saved = await adapter(deps, "persistFoodRecall")(tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
      lotCode, reason, severity, impact, idempotencyKey: scope.idempotencyKey,
    });
    if (!saved?.id) fail("FOOD_RECALL_PERSIST_FAILED", "Recall record was not persisted");
    await adapter(deps, "quarantineFoodLot")(tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, lotCode,
      recallId: saved.id, reasonCodes: ["FOOD_RECALL"], idempotencyKey: scope.idempotencyKey,
    });
    await audit(deps, tx, scope, {
      action: "quality.food_recall.initiated", entityType: "food_recall",
      entityId: saved.id, idempotencyKey: scope.idempotencyKey,
    });
    return Object.freeze({ status: "initiated", recallId: saved.id,
      affectedBranchCount: impact.affectedBranches.length, affectedOrderCount: impact.affectedOrders.length });
  });
}

/** Inspect a received supplier line and quarantine non-conforming quantities. */
export async function recordSupplierQualityInspection(input, deps) {
  const scope = scopeOf(input, "quality.supplier.inspect");
  const receiptItemId = required(input.receiptItemId, "receiptItemId");
  const policyId = required(input.policyId, "policyId");
  if (!Array.isArray(input.findings) || input.findings.length === 0) {
    fail("SUPPLIER_QUALITY_FINDINGS_REQUIRED", "At least one inspection finding is required");
  }
  return transact(deps, scope, async (tx) => {
    const existing = await adapter(deps, "findSupplierQualityInspectionByIdempotencyKey")(tx, scope);
    if (existing) return Object.freeze({ status: "duplicate", inspectionId: existing.id, disposition: existing.disposition });
    const receipt = await adapter(deps, "loadSupplierReceiptItemForUpdate")(tx, { tenantId: scope.tenantId, branchId: scope.branchId, receiptItemId });
    assertScope(receipt, scope, "supplierReceiptItem");
    const policy = await adapter(deps, "loadApprovedSupplierQualityPolicy")(tx, { tenantId: scope.tenantId, branchId: scope.branchId, policyId, supplierId: receipt.supplierId });
    assertScope(policy, scope, "supplierQualityPolicy");
    if (policy.status !== "approved" || !Array.isArray(policy.criticalFindingCodes)) {
      fail("APPROVED_SUPPLIER_QUALITY_POLICY_REQUIRED", "An approved supplier quality policy is required");
    }
    const normalized = input.findings.map((finding) => {
      const code = required(finding?.code, "finding.code");
      const severity = required(finding?.severity, "finding.severity");
      if (!["minor", "major", "critical"].includes(severity)) fail("SUPPLIER_QUALITY_SEVERITY_INVALID", "Unsupported finding severity");
      return Object.freeze({ code, severity, note: typeof finding.note === "string" ? finding.note.trim() : "" });
    });
    const critical = normalized.some((finding) => finding.severity === "critical" || policy.criticalFindingCodes.includes(finding.code));
    const nonConforming = critical || normalized.some((finding) => finding.severity === "major");
    const disposition = nonConforming ? "quarantined" : "accepted_with_observation";
    const saved = await adapter(deps, "persistSupplierQualityInspection")(tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, actorId: scope.actorId,
      supplierId: receipt.supplierId, receiptItemId, policyId, findings: normalized,
      disposition, idempotencyKey: scope.idempotencyKey,
    });
    if (!saved?.id) fail("SUPPLIER_QUALITY_INSPECTION_PERSIST_FAILED", "Supplier inspection evidence was not persisted");
    let capaId = null;
    if (nonConforming) {
      const quarantine = await adapter(deps, "quarantineSupplierReceiptQuantity")(tx, {
        tenantId: scope.tenantId, branchId: scope.branchId, receiptItemId,
        quantity: receipt.quantityReceived, inspectionId: saved.id,
        reasonCodes: normalized.map((finding) => finding.code),
        idempotencyKey: scope.idempotencyKey,
      });
      if (!quarantine?.id) fail("SUPPLIER_QUARANTINE_FAILED", "Non-conforming receipt quantity must be quarantined");
      const capa = await adapter(deps, "createSupplierCorrectiveAction")(tx, {
        tenantId: scope.tenantId, branchId: scope.branchId, supplierId: receipt.supplierId,
        inspectionId: saved.id, findings: normalized, createdBy: scope.actorId,
        status: "open", idempotencyKey: scope.idempotencyKey,
      });
      if (!capa?.id) fail("SUPPLIER_CAPA_CREATE_FAILED", "A corrective action record is required for non-conforming supply");
      capaId = capa.id;
    }
    await audit(deps, tx, scope, {
      action: nonConforming ? "quality.supplier.quarantined" : "quality.supplier.accepted_with_observation",
      entityType: "supplier_quality_inspection", entityId: saved.id,
      idempotencyKey: scope.idempotencyKey,
    });
    return Object.freeze({ status: "recorded", inspectionId: saved.id, disposition, capaId });
  });
}

/** Close a supplier CAPA only after independent verification and evidence review. */
export async function verifySupplierCorrectiveAction(input, deps) {
  const scope = scopeOf(input, "quality.supplier.capa.verify");
  const capaId = required(input.capaId, "capaId");
  const decision = required(input.decision, "decision");
  if (!["verified", "rejected"].includes(decision)) fail("SUPPLIER_CAPA_DECISION_INVALID", "Decision must be verified or rejected");
  const evidenceReference = required(input.evidenceReference, "evidenceReference");
  return transact(deps, scope, async (tx) => {
    const capa = await adapter(deps, "loadSupplierCorrectiveActionForUpdate")(tx, { tenantId: scope.tenantId, branchId: scope.branchId, capaId });
    assertScope(capa, scope, "supplierCapa");
    if (capa.status !== "submitted") fail("SUPPLIER_CAPA_NOT_SUBMITTED", "CAPA must be submitted before independent verification");
    if (capa.createdBy === scope.actorId || capa.submittedBy === scope.actorId) {
      fail("INDEPENDENT_SUPPLIER_CAPA_REVIEWER_REQUIRED", "CAPA creator and submitter cannot verify their own corrective action");
    }
    const updated = await adapter(deps, "recordSupplierCorrectiveActionVerification")(tx, {
      tenantId: scope.tenantId, branchId: scope.branchId, capaId, reviewerId: scope.actorId,
      decision, evidenceReference,
    });
    if (!updated?.id || updated.status !== decision) fail("SUPPLIER_CAPA_VERIFICATION_FAILED", "Independent CAPA decision was not persisted");
    if (decision === "verified" && input.releaseQuarantine === true) {
      const release = await adapter(deps, "releaseSupplierQuarantineAfterCapa")(tx, {
        tenantId: scope.tenantId, branchId: scope.branchId, capaId,
        reviewerId: scope.actorId, verificationId: updated.id,
      });
      if (!release?.released) fail("SUPPLIER_QUARANTINE_RELEASE_FAILED", "Quarantined stock remains held until release is confirmed");
    }
    await audit(deps, tx, scope, {
      action: "quality.supplier.capa." + decision, entityType: "supplier_corrective_action",
      entityId: capaId, idempotencyKey: scope.idempotencyKey,
    });
    return Object.freeze({ status: decision, capaId, quarantineReleaseRequested: input.releaseQuarantine === true });
  });
}
