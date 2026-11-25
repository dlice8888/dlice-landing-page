/**
 * Builds a balanced Finance journal batch from approved payroll line snapshots.
 *
 * This is a pure adapter: it does not post to Finance, choose account codes,
 * execute payments, or mark a payroll run reconciled. Account mappings must be
 * supplied by Finance governance and validated by the caller.
 */

function invalid(code, message) {
  const error = new Error(message);
  error.code = code;
  throw error;
}

function positiveIdr(value, field) {
  if (!Number.isSafeInteger(value) || value <= 0) {
    invalid("INVALID_JOURNAL_AMOUNT", `${field} must be a positive safe-integer IDR amount`);
  }
  return value;
}

function account(value, field) {
  if (typeof value !== "string" || !value.trim()) {
    invalid("FINANCE_ACCOUNT_MAPPING_REQUIRED", `${field} is not configured`);
  }
  return value.trim();
}

function appendLine(lines, { accountCode, side, amountIdr, componentCode, description }) {
  if (!amountIdr) return;
  lines.push(Object.freeze({
    lineNo: lines.length + 1,
    accountCode,
    side,
    amountIdr: positiveIdr(amountIdr, componentCode ?? description),
    componentCode: componentCode ?? null,
    description,
  }));
}

/**
 * @param {object} input
 * @param {object} input.payrollRun Approved payroll run identity and totals.
 * @param {Array<object>} input.payrollLines Immutable, approved payroll line snapshots.
 * @param {object} input.accountMapping Explicit Finance-approved account codes.
 * @param {string} input.idempotencyKey Stable source idempotency key.
 */
export function buildPayrollFinanceJournalBatch(input) {
  const run = input?.payrollRun;
  if (!run?.id || !run.tenantId || !run.branchId || run.status !== "approved") {
    invalid("APPROVED_PAYROLL_RUN_REQUIRED", "A tenant/branch-scoped approved payroll run is required");
  }
  if (!Array.isArray(input.payrollLines) || input.payrollLines.length === 0) {
    invalid("PAYROLL_LINES_REQUIRED", "At least one immutable payroll line snapshot is required");
  }
  if (typeof input.idempotencyKey !== "string" || input.idempotencyKey.trim().length < 8) {
    invalid("IDEMPOTENCY_KEY_REQUIRED", "A stable Finance posting idempotency key is required");
  }

  const mapping = input.accountMapping ?? {};
  const wageExpense = account(mapping.wageExpense, "wageExpense");
  const netPayable = account(mapping.netWagesPayable, "netWagesPayable");

  const lines = [];
  let grossTotal = 0;
  let deductionTotal = 0;
  let employerContributionTotal = 0;
  const employeeIds = new Set();

  for (const payrollLine of input.payrollLines) {
    if (!payrollLine?.employeeId || employeeIds.has(payrollLine.employeeId)) {
      invalid("DUPLICATE_OR_MISSING_EMPLOYEE_LINE", "Each employee must have exactly one approved payroll line");
    }
    employeeIds.add(payrollLine.employeeId);

    const gross = positiveIdr(payrollLine.grossAmountIdr, "grossAmountIdr");
    const deductions = payrollLine.deductionsIdr ?? 0;
    const net = positiveIdr(payrollLine.netAmountIdr, "netAmountIdr");
    const employerCosts = payrollLine.employerContributionsIdr ?? 0;
    if (!Number.isSafeInteger(deductions) || deductions < 0 ||
        !Number.isSafeInteger(employerCosts) || employerCosts < 0 ||
        gross - deductions !== net) {
      invalid("PAYROLL_LINE_TOTAL_MISMATCH", payrollLine.employeeId);
    }

    appendLine(lines, {
      accountCode: wageExpense,
      side: "debit",
      amountIdr: gross,
      description: `Wage expense payroll ${run.id}`,
    });

    const components = payrollLine.components ?? [];
    for (const component of components) {
      if (!component || !Number.isSafeInteger(component.amountIdr) || component.amountIdr < 0) {
        invalid("INVALID_PAYROLL_COMPONENT_SNAPSHOT", payrollLine.employeeId);
      }
      if (component.kind === "deduction") {
        if (component.amountIdr > 0) {
          const code = account(mapping.deductionLiabilities?.[component.code], `deductionLiabilities.${component.code}`);
          appendLine(lines, {
            accountCode: code, side: "credit", amountIdr: component.amountIdr,
            componentCode: component.code, description: `Payroll deduction ${component.code}`,
          });
        }
      } else if (component.kind === "employer_contribution") {
        if (component.amountIdr > 0) {
          const code = account(mapping.employerContributionExpenses?.[component.code], `employerContributionExpenses.${component.code}`);
          appendLine(lines, {
            accountCode: code, side: "debit", amountIdr: component.amountIdr,
            componentCode: component.code, description: `Employer contribution ${component.code}`,
          });
        }
      } else if (component.kind !== "earning") {
        invalid("UNKNOWN_PAYROLL_COMPONENT_KIND", String(component.kind));
      }
    }

    appendLine(lines, {
      accountCode: netPayable,
      side: "credit",
      amountIdr: net,
      description: `Net wages payable payroll ${run.id}`,
    });

    grossTotal += gross;
    deductionTotal += deductions;
    employerContributionTotal += employerCosts;
  }

  const debitTotal = lines.filter((line) => line.side === "debit").reduce((sum, line) => sum + line.amountIdr, 0);
  const creditTotal = lines.filter((line) => line.side === "credit").reduce((sum, line) => sum + line.amountIdr, 0);
  if (!Number.isSafeInteger(debitTotal) || !Number.isSafeInteger(creditTotal) ||
      debitTotal !== creditTotal || grossTotal - deductionTotal < 0) {
    invalid("UNBALANCED_PAYROLL_JOURNAL", "Payroll journal debit and credit totals do not balance");
  }
  if (debitTotal !== grossTotal + employerContributionTotal ||
      creditTotal !== grossTotal - deductionTotal + deductionTotal + employerContributionTotal) {
    invalid("PAYROLL_JOURNAL_COMPONENTS_DO_NOT_RECONCILE",
      "Payroll journal lines do not reconcile to payroll gross, deductions and employer contributions");
  }

  return Object.freeze({
    sourceType: "hr_payroll_run",
    sourceId: run.id,
    tenantId: run.tenantId,
    branchId: run.branchId,
    periodStart: run.periodStart,
    periodEnd: run.periodEnd,
    currency: "IDR",
    idempotencyKey: input.idempotencyKey,
    lineCount: lines.length,
    debitTotalIdr: debitTotal,
    creditTotalIdr: creditTotal,
    status: "draft",
    requiresIndependentApproval: true,
    requiresOpenFiscalPeriod: true,
    paymentStatus: "not_paid",
    reconciliationStatus: "not_reconciled",
    lines: Object.freeze(lines),
    journalVersion: "payroll-finance-batch-v1",
  });
}
