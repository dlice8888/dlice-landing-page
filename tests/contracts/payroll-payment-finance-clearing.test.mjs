import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  postReconciledPayrollPaymentFinanceClearing,
  matchPayrollPaymentBankStatement,
  reconcilePayrollPaymentBankBatch,
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

test("closes the bank batch only when every payout clearing has exact bank evidence", async () => {
  const clearings = [
    { id: "clear-a", tenantId: "tenant-a", branchId: "branch-a", paymentBatchId: "batch-a",
      status: "bank_matched", statementLineId: "line-a", bankJournalEntryId: "bank-journal-a",
      statementCurrency: "IDR", statementAmountIdr: 100000, statementProviderReference: "po-a",
      providerReference: "po-a", amountIdr: 100000 },
    { id: "clear-b", tenantId: "tenant-a", branchId: "branch-a", paymentBatchId: "batch-a",
      status: "bank_matched", statementLineId: "line-b", bankJournalEntryId: "bank-journal-b",
      statementCurrency: "IDR", statementAmountIdr: 200000, statementProviderReference: "po-b",
      providerReference: "po-b", amountIdr: 200000 },
  ];
  const deps = transactionDeps({
    loadPayrollPaymentBankBatchEvidence: async () => ({ batch, clearings }),
    reconcilePayrollPaymentBankBatch: async () => ({
      status: "bank_reconciled", reconciliationId: "bank-recon-a", amountIdr: 300000, itemCount: 2,
    }),
  });
  const result = await reconcilePayrollPaymentBankBatch({
    ...base, paymentBatchId: "batch-a",
  }, deps);
  assert.equal(result.status, "bank_reconciled");
  assert.equal(result.amountIdr, 300000);
});

test("does not close a bank batch with a missing or mismatched statement line", async () => {
  const deps = transactionDeps({
    loadPayrollPaymentBankBatchEvidence: async () => ({
      batch,
      clearings: [{ id: "clear-a", tenantId: "tenant-a", branchId: "branch-a",
        paymentBatchId: "batch-a", status: "provider_cleared", amountIdr: 300000,
        providerReference: "po-a" }],
    }),
  });
  await assert.rejects(
    reconcilePayrollPaymentBankBatch({ ...base, paymentBatchId: "batch-a" }, deps),
    { code: "PAYROLL_BANK_CLEARING_EVIDENCE_MISMATCH" },
  );
  assert.equal(deps.calls.length, 0);
});

test("Finance clearing SQL draft keeps payout, bank and reversal evidence service-role scoped", async () => {
  const sql = await readFile(new URL("../../docs/implementation/sql/HR_PAYROLL_PAYMENT_FINANCE_CLEARING_DRAFT.sql", import.meta.url), "utf8");
  for (const required of [
    "hr_payroll_payment_finance_mappings",
    "hr_payroll_payment_finance_clearings",
    "hr_payroll_bank_statement_lines",
    "hr_payroll_payment_bank_reconciliations",
    "hr_payroll_payment_reversal_exceptions",
    "hr_post_payroll_payment_finance_clearing",
    "hr_import_payroll_bank_statement_line",
    "hr_match_payroll_payment_bank_statement",
    "hr_reconcile_payroll_payment_bank_batch",
    "hr_mark_payroll_payment_reversal_exception",
    "bank_account_fingerprint_sha256",
    "signature_verified is distinct from true",
    "revoke all on function",
    "to service_role",
    "enable row level security",
  ]) assert.ok(sql.includes(required), `Finance clearing SQL contract missing: ${required}`);
  assert.match(sql, /before update on public\.hr_payroll_payment_finance_clearings/);
  assert.match(sql, /before update or delete on public\.hr_payroll_bank_statement_lines/);
});

test("treats database idempotency duplicates as safe no-op results", async () => {
  const postDeps = transactionDeps({
    loadPayrollPaymentFinanceClearingSource: async () => ({
      batch, payrollRun: { status: "reconciled" },
      financePosting: { id: "posting-a", status: "reconciled" }, items,
    }),
    postPayrollPaymentFinanceClearing: async () => ({
      status: "duplicate", amountIdr: 300000, itemCount: 2,
    }),
  });
  const posted = await postReconciledPayrollPaymentFinanceClearing({
    ...base, paymentBatchId: "batch-a",
  }, postDeps);
  assert.equal(posted.status, "duplicate");

  const bankDeps = transactionDeps({
    loadPayrollPaymentBankBatchEvidence: async () => ({
      batch,
      clearings: [
        { id: "clear-a", tenantId: "tenant-a", branchId: "branch-a", paymentBatchId: "batch-a",
          status: "bank_matched", statementLineId: "line-a", bankJournalEntryId: "journal-a",
          statementCurrency: "IDR", statementAmountIdr: 100000, statementProviderReference: "po-a",
          providerReference: "po-a", amountIdr: 100000 },
        { id: "clear-b", tenantId: "tenant-a", branchId: "branch-a", paymentBatchId: "batch-a",
          status: "bank_matched", statementLineId: "line-b", bankJournalEntryId: "journal-b",
          statementCurrency: "IDR", statementAmountIdr: 200000, statementProviderReference: "po-b",
          providerReference: "po-b", amountIdr: 200000 },
      ],
    }),
    reconcilePayrollPaymentBankBatch: async () => ({
      status: "duplicate", reconciliationId: "bank-recon-a", amountIdr: 300000, itemCount: 2,
    }),
  });
  const bankClosed = await reconcilePayrollPaymentBankBatch({
    ...base, paymentBatchId: "batch-a",
  }, bankDeps);
  assert.equal(bankClosed.status, "duplicate");
});
