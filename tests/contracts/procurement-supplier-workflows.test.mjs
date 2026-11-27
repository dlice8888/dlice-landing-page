import test from "node:test";
import assert from "node:assert/strict";
import {
  resolveEffectiveSupplierPrice, consolidateBranchDemand,
  requestSupplierReturn, approveSupplierReturn,
} from "../../src/procurement-supplier-workflows.mjs";

const base = { tenantId: "tenant-a", branchId: "branch-a", actorId: "buyer-a", idempotencyKey: "return-key-0001" };
const common = (overrides = {}) => ({
  withTenantTransaction: async (_scope, callback) => callback({ tx: true }),
  authorize: async (_tx, scope) => { assert.equal(scope.tenantId, "tenant-a"); assert.equal(scope.branchId, "branch-a"); },
  appendAudit: async (_tx, event) => { assert.ok(event.action.startsWith("procurement.")); },
  ...overrides,
});

test("effective supplier price selects approved branch/date/quantity contract", () => {
  const result = resolveEffectiveSupplierPrice({ tenantId: "tenant-a", branchId: "branch-a", supplierId: "supplier-a",
    itemId: "flour", date: "2026-11-27", quantity: 20, contracts: [
      { id: "expired", tenantId: "tenant-a", supplierId: "supplier-a", itemId: "flour", status: "approved",
        effectiveFrom: "2026-01-01", effectiveTo: "2026-10-31", currency: "IDR", unitPriceIdr: 1000 },
      { id: "active", tenantId: "tenant-a", supplierId: "supplier-a", itemId: "flour", status: "approved",
        effectiveFrom: "2026-11-01", effectiveTo: "2026-12-31", branchIds: ["branch-a"], minimumQuantity: 10,
        currency: "IDR", unitPriceIdr: 900 },
      { id: "other-tenant", tenantId: "tenant-b", supplierId: "supplier-a", itemId: "flour", status: "approved",
        effectiveFrom: "2026-11-01", currency: "IDR", unitPriceIdr: 1 },
    ] });
  assert.equal(result.contractId, "active");
  assert.equal(result.unitPriceIdr, 900);
});

test("effective supplier price rejects conflicting approved contracts", () => {
  const contract = { tenantId: "tenant-a", supplierId: "supplier-a", itemId: "flour", status: "approved",
    effectiveFrom: "2026-11-01", currency: "IDR", unitPriceIdr: 900 };
  assert.throws(() => resolveEffectiveSupplierPrice({ tenantId: "tenant-a", branchId: "branch-a",
    supplierId: "supplier-a", itemId: "flour", date: "2026-11-27", quantity: 2,
    contracts: [{ ...contract, id: "a" }, { ...contract, id: "b", unitPriceIdr: 950 }] }),
  { code: "PROCUREMENT_PRICE_CONTRACT_AMBIGUOUS" });
});

test("consolidated demand nets branch available stock and open purchase orders", () => {
  const result = consolidateBranchDemand({ tenantId: "tenant-a", rows: [
    { tenantId: "tenant-a", branchId: "branch-a", itemId: "flour", baseUnit: "kg",
      forecastQuantity: 100, onHandQuantity: 30, reservedQuantity: 10, openPurchaseOrderQuantity: 20, safetyStockQuantity: 5 },
    { tenantId: "tenant-a", branchId: "branch-b", itemId: "flour", baseUnit: "kg",
      forecastQuantity: 50, onHandQuantity: 10, reservedQuantity: 0, openPurchaseOrderQuantity: 0, safetyStockQuantity: 5 },
  ] });
  assert.equal(result[0].branchCount, 2);
  assert.equal(result[0].forecastQuantity, 150);
  assert.equal(result[0].consolidatedPurchaseQuantity, 110);
});

test("demand consolidation rejects cross-tenant rows and impossible inventory quantities", () => {
  assert.throws(() => consolidateBranchDemand({ tenantId: "tenant-a", rows: [
    { tenantId: "tenant-b", branchId: "branch-b", itemId: "flour", baseUnit: "kg", forecastQuantity: 1, onHandQuantity: 0 },
  ] }), { code: "PROCUREMENT_DEMAND_SCOPE_MISMATCH" });
  assert.throws(() => consolidateBranchDemand({ tenantId: "tenant-a", rows: [
    { tenantId: "tenant-a", branchId: "branch-a", itemId: "flour", baseUnit: "kg",
      forecastQuantity: 1, onHandQuantity: 2, reservedQuantity: 3 },
  ] }), { code: "PROCUREMENT_DEMAND_QUANTITY_INVALID" });
});

test("supplier return request is limited to unreturned receipt quantity and creates pending approval", async () => {
  const deps = common({
    findSupplierReturnByIdempotencyKey: async () => null,
    loadSupplierReceiptLineForUpdate: async () => ({ tenantId: "tenant-a", branchId: "branch-a",
      receivedQuantity: 10, previouslyReturnedQuantity: 2, approvedUnitPriceIdr: 1200 }),
    persistSupplierReturnRequest: async (_tx, row) => { assert.equal(row.creditAmountIdr, 9600); return { id: "return-a" }; },
  });
  const result = await requestSupplierReturn({ ...base, receiptLineId: "grn-line-a", quantity: 8, reason: "Damaged packaging" }, deps);
  assert.deepEqual(result, { status: "pending_approval", returnId: "return-a", creditAmountIdr: 9600 });
});

test("supplier return request rejects cross-branch receipt and excess quantity", async () => {
  const deps = common({ findSupplierReturnByIdempotencyKey: async () => null,
    loadSupplierReceiptLineForUpdate: async () => ({ tenantId: "tenant-a", branchId: "branch-b",
      receivedQuantity: 5, previouslyReturnedQuantity: 0, approvedUnitPriceIdr: 1000 }) });
  await assert.rejects(requestSupplierReturn({ ...base, receiptLineId: "line-b", quantity: 1, reason: "Damage" }, deps),
    { code: "PROCUREMENT_SCOPE_MISMATCH" });
  const sameBranch = common({ findSupplierReturnByIdempotencyKey: async () => null,
    loadSupplierReceiptLineForUpdate: async () => ({ tenantId: "tenant-a", branchId: "branch-a",
      receivedQuantity: 5, previouslyReturnedQuantity: 3, approvedUnitPriceIdr: 1000 }) });
  await assert.rejects(requestSupplierReturn({ ...base, receiptLineId: "line-a", quantity: 3, reason: "Damage" }, sameBranch),
    { code: "PROCUREMENT_RETURN_QUANTITY_EXCEEDS_RECEIPT" });
});

test("supplier return approval requires independent approver and atomic stock/AP evidence", async () => {
  const deps = common({
    loadSupplierReturnForUpdate: async () => ({ tenantId: "tenant-a", branchId: "branch-a", status: "pending_approval", requestedBy: "buyer-b" }),
    approveSupplierReturn: async () => ({ approved: true }),
    postSupplierReturnStockMovement: async () => ({ movementId: "movement-a" }),
    postSupplierCreditNoteToAp: async () => ({ journalId: "journal-a", status: "posted" }),
  });
  const result = await approveSupplierReturn({ ...base, actorId: "finance-a", returnId: "return-a", creditNoteReference: "CN-001" }, deps);
  assert.deepEqual(result, { status: "approved", returnId: "return-a", stockMovementId: "movement-a", apJournalId: "journal-a" });
});

test("supplier return requester cannot approve own request", async () => {
  const deps = common({ loadSupplierReturnForUpdate: async () => ({ tenantId: "tenant-a", branchId: "branch-a",
    status: "pending_approval", requestedBy: "buyer-a" }) });
  await assert.rejects(approveSupplierReturn({ ...base, returnId: "return-a", creditNoteReference: "CN-001" }, deps),
    { code: "PROCUREMENT_RETURN_SELF_APPROVAL_DENIED" });
});
