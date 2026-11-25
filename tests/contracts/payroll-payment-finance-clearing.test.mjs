import test from "node:test";
import assert from "node:assert/strict";
import {
  postReconciledPayrollPaymentFinanceClearing,
  matchPayrollPaymentBankStatement,
  quarantineReversedPayrollPaymentClearing,
} from "../../src/fnb-transactional-workflows.mjs";

const base = { tenantId: "tenant-a", branchId: "branch-a", actorId: "finance-reviewer",
  idempotencyKey: "finance-clearing-001" };
const batch = { id: "batch-a", tenantId: "tenant-a", branchId: "branch-a",
  financePostingId: "posting-a", status: "reconciled", amountIdr: 300000, itemCount: 2 };
const items = [
  { id: "item-a", tenantId: "tenant-a", branchId: "branch-a", status: "settled", providerReference: "po-a" },
  { id: "item-b", tenantId: "tenant-a", branchId: "branch-a", status: "settled", providerReference: "po-b" },
];
function transactionDeps(overrides = {}) {
  const calls = [];
  return {
    calls,
    withTenantTransaction: async (_scope, callback) => callback({}),
    authorize: async () => {},
    appendAudit: async (_tx, event) => calls.push(["audit", event.action]),
    ...overrides,
  };
}

test("posts Finance payout clearing only after provider batch and payroll source are reconciled", async () => {
  const deps = transactionDeps({
    loadPayrollPaymentFinanceClearingSource: async () => ({
      batch, payrollRun: { status: "reconciled" },
      financePosting: { id: "posting-a", status: "reconciled" }, items,
    }),
    postPayrollPaymentFinanceClearing: async (_tx, args) => {
      assert.equal(args.paymentBatchId, "batch-a");
      return { status: "provider_cleared", amountIdr: 300000, itemCount: 2 };
    },
  });
  const result = await postReconciledPayrollPaymentFinanceClearing({ ...base, paymentBatchId: "batch-a" }, deps);
  assert.equal(result.status, "provider_cleared");
  assert.equal(result.bankStatementReconciliationRequired, true);
  assert.equal(deps.calls.length, 1);
});

test("blocks clearing if the payroll Finance posting is not reconciled", async () => {
  const deps = transactionDeps({
    loadPayrollPaymentFinanceClearingSource: async () => ({
      batch, payrollRun: { status: "reconciled" },
      financePosting: { id: "posting-a", status: "posted" }, items,
    }),
  });
  await assert.rejects(
    postReconciledPayrollPaymentFinanceClearing({ ...base, paymentBatchId: "batch-a" }, deps),
    { code: "PAYROLL_PROVIDER_AND_FINANCE_RECONCILIATION_REQUIRED" },
  );
  assert.equal(deps.calls.length, 0);
});

test("requires an exact independent bank statement match before closing payout clearing", async () => {
  const deps = transactionDeps({
    loadPayrollPaymentBankStatementMatch: async () => ({
      clearing: { id: "clear-a", tenantId: "tenant-a", branchId: "branch-a",
        status: "provider_cleared", providerReference: "po-a", amountIdr: 100000 },
      statementLine: { id: "statement-a", tenantId: "tenant-a", branchId: "branch-a",
        providerPayoutReference: "po-a", amountIdr: 100000, currency: "IDR" },
    }),
    matchPayrollPaymentBankStatement: async () => ({ status: "bank_matched", amountIdr: 100000 }),
  });
  const result = await matchPayrollPaymentBankStatement({
    ...base, clearingId: "clear-a", statementLineId: "statement-a",
  }, deps);
  assert.equal(result.status, "bank_matched");
  assert.equal(result.amountIdr, 100000);
});

test("rejects bank statement reference or amount mismatches", async () => {
  const deps = transactionDeps({
    loadPayrollPaymentBankStatementMatch: async () => ({
      clearing: { id: "clear-a", tenantId: "tenant-a", branchId: "branch-a",
        status: "provider_cleared", providerReference: "po-a", amountIdr: 100000 },
      statementLine: { id: "statement-a", tenantId: "tenant-a", branchId: "branch-a",
        providerPayoutReference: "po-b", amountIdr: 100000, currency: "IDR" },
    }),
  });
  await assert.rejects(
    matchPayrollPaymentBankStatement({ ...base, clearingId: "clear-a", statementLineId: "statement-a" }, deps),
    { code: "PAYROLL_BANK_STATEMENT_EVIDENCE_MISMATCH" },
  );
  assert.equal(deps.calls.length, 0);
});

test("quarantines authenticated provider reversals without mutating original clearing journals", async () => {
  const deps = transactionDeps({
    loadPayrollPaymentReversalEvidence: async () => ({
      item: { id: "item-a", tenantId: "tenant-a", branchId: "branch-a" },
      event: { id: "event-a", paymentItemId: "item-a", eventKind: "reversed", signatureVerified: true },
    }),
    quarantineReversedPayrollPaymentClearing: async () => ({ status: "reversal_exception" }),
  });
  const result = await quarantineReversedPayrollPaymentClearing({
    ...base, paymentItemId: "item-a", providerEventId: "event-a",
  }, deps);
  assert.equal(result.status, "reversal_exception");
  assert.equal(result.bankReturnEvidenceRequired, true);
});
