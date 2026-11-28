/**
 * Deterministic payroll calculation kernel.
 *
 * This module deliberately contains no statutory tax tables, default rates,
 * overtime multipliers, or local labour-law assumptions. All compensation
 * inputs must be effective-dated and approved by the caller before use.
 *
 * The caller must separately enforce employee/tenant/branch authorization,
 * approval of time records, payroll period policy, and Finance posting.
 */

const DAY_MS = 86_400_000;

function fail(code, message) {
  const error = new Error(message);
  error.code = code;
  throw error;
}

function parseDate(value, field) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    fail("INVALID_DATE", `${field} must be YYYY-MM-DD`);
  }
  const date = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    fail("INVALID_DATE", `${field} is not a calendar date`);
  }
  return date;
}

function assertMoney(value, field, { allowZero = true } = {}) {
  if (!Number.isSafeInteger(value) || value < (allowZero ? 0 : 1)) {
    fail("INVALID_MONEY", `${field} must be a safe integer IDR amount`);
  }
  return value;
}

function roundIdr(value, field) {
  if (!Number.isFinite(value) || value < 0 || value > Number.MAX_SAFE_INTEGER) {
    fail("INVALID_CALCULATION", `${field} produced an invalid amount`);
  }
  return Math.round(value);
}

function assertEffective(component, start, end) {
  const effectiveFrom = parseDate(component.effectiveFrom, "component.effectiveFrom");
  const effectiveTo = component.effectiveTo == null
    ? null
    : parseDate(component.effectiveTo, "component.effectiveTo");
  if (effectiveFrom > start || (effectiveTo && effectiveTo < end)) {
    fail("COMPENSATION_NOT_EFFECTIVE_FOR_FULL_PERIOD", component.code);
  }
}

function calculateComponent(component, baseGross, start, end) {
  if (!component || typeof component.code !== "string" || !component.code.trim()) {
    fail("INVALID_COMPONENT", "Every payroll component needs a stable code");
  }
  assertEffective(component, start, end);

  const kind = component.kind;
  if (!["earning", "deduction", "employer_contribution"].includes(kind)) {
    fail("INVALID_COMPONENT_KIND", component.code);
  }

  let amount;
  if (component.calculation === "fixed_idr") {
    amount = assertMoney(component.amountIdr, `${component.code}.amountIdr`);
  } else if (component.calculation === "percent_of_base_gross") {
    if (typeof component.rateBps !== "number" ||
        !Number.isInteger(component.rateBps) ||
        component.rateBps < 0 || component.rateBps > 100_000) {
      fail("INVALID_COMPONENT_RATE", component.code);
    }
    amount = roundIdr(baseGross * component.rateBps / 10_000, component.code);
  } else {
    fail("UNSUPPORTED_COMPONENT_CALCULATION", component.code);
  }

  return {
    code: component.code,
    kind,
    amountIdr: amount,
    sourceRef: component.sourceRef ?? null,
  };
}

/**
 * @param {object} input
 * @param {string} input.employeeId
 * @param {string} input.periodStart YYYY-MM-DD
 * @param {string} input.periodEnd YYYY-MM-DD
 * @param {object} input.compensation Effective-dated approved compensation.
 * @param {object} input.approvedTime { regularMinutes, overtimeMinutes }.
 * @param {Array<object>} input.components Approved effective-dated components.
 * @param {object|null} input.monthlyProration Explicit { numerator, denominator }
 *   when monthly salary is prorated. No implicit calendar/workday convention.
 */
export function calculatePayrollLine(input) {
  if (!input || typeof input.employeeId !== "string" || !input.employeeId.trim()) {
    fail("EMPLOYEE_REQUIRED", "employeeId is required");
  }

  const start = parseDate(input.periodStart, "periodStart");
  const end = parseDate(input.periodEnd, "periodEnd");
  if (end < start) fail("INVALID_PAYROLL_PERIOD", "periodEnd precedes periodStart");

  const compensation = input.compensation;
  if (!compensation || compensation.approved !== true || !compensation.id) {
    fail("APPROVED_COMPENSATION_REQUIRED", "Compensation must be approved and identified");
  }
  assertEffective(compensation, start, end);

  const approvedTime = input.approvedTime ?? {};
  const regularMinutes = assertMoney(approvedTime.regularMinutes ?? 0, "regularMinutes");
  const overtimeMinutes = assertMoney(approvedTime.overtimeMinutes ?? 0, "overtimeMinutes");

  let baseGrossIdr = 0;
  let regularWagesIdr = 0;
  let overtimeWagesIdr = 0;

  if (compensation.payType === "hourly") {
    const hourlyRateIdr = assertMoney(compensation.hourlyRateIdr, "hourlyRateIdr", { allowZero: false });
    regularWagesIdr = roundIdr(hourlyRateIdr * regularMinutes / 60, "regularWages");
    if (overtimeMinutes > 0) {
      const multiplierBps = compensation.overtimeMultiplierBps;
      if (!Number.isInteger(multiplierBps) || multiplierBps <= 0 || multiplierBps > 100_000) {
        fail("APPROVED_OVERTIME_MULTIPLIER_REQUIRED", "An approved overtime multiplier is required");
      }
      overtimeWagesIdr = roundIdr(hourlyRateIdr * overtimeMinutes / 60 * multiplierBps / 10_000, "overtimeWages");
    }
    baseGrossIdr = regularWagesIdr + overtimeWagesIdr;
  } else if (compensation.payType === "monthly") {
    const monthlySalaryIdr = assertMoney(compensation.monthlySalaryIdr, "monthlySalaryIdr", { allowZero: false });
    const fullPeriodDays = Math.round((end - start) / DAY_MS) + 1;
    const proration = input.monthlyProration;
    if (!proration || !Number.isSafeInteger(proration.numerator) ||
        !Number.isSafeInteger(proration.denominator) ||
        proration.numerator < 0 || proration.denominator <= 0 ||
        proration.numerator > proration.denominator) {
      fail("EXPLICIT_MONTHLY_PRORATION_REQUIRED",
        `Monthly payroll requires an approved proration ratio for ${fullPeriodDays} calendar days`);
    }
    baseGrossIdr = roundIdr(monthlySalaryIdr * proration.numerator / proration.denominator, "monthlySalary");
    regularWagesIdr = baseGrossIdr;
  } else {
    fail("UNSUPPORTED_PAY_TYPE", "payType must be hourly or monthly");
  }

  const seen = new Set();
  const calculatedComponents = (input.components ?? []).map((component) => {
    if (seen.has(component.code)) fail("DUPLICATE_COMPONENT", component.code);
    seen.add(component.code);
    return calculateComponent(component, baseGrossIdr, start, end);
  });

  const earningsIdr = calculatedComponents
    .filter((item) => item.kind === "earning")
    .reduce((sum, item) => sum + item.amountIdr, 0);
  const deductionsIdr = calculatedComponents
    .filter((item) => item.kind === "deduction")
    .reduce((sum, item) => sum + item.amountIdr, 0);
  const employerContributionsIdr = calculatedComponents
    .filter((item) => item.kind === "employer_contribution")
    .reduce((sum, item) => sum + item.amountIdr, 0);

  const grossAmountIdr = baseGrossIdr + earningsIdr;
  const netAmountIdr = grossAmountIdr - deductionsIdr;
  if (!Number.isSafeInteger(grossAmountIdr) || !Number.isSafeInteger(netAmountIdr) ||
      netAmountIdr < 0 || !Number.isSafeInteger(employerContributionsIdr)) {
    fail("PAYROLL_TOTAL_OUT_OF_RANGE", "Payroll totals are invalid or net pay is negative");
  }

  return Object.freeze({
    employeeId: input.employeeId,
    compensationId: compensation.id,
    periodStart: input.periodStart,
    periodEnd: input.periodEnd,
    currency: "IDR",
    regularMinutes,
    overtimeMinutes,
    regularWagesIdr,
    overtimeWagesIdr,
    baseGrossIdr,
    earningsIdr,
    grossAmountIdr,
    deductionsIdr,
    netAmountIdr,
    employerContributionsIdr,
    components: Object.freeze(calculatedComponents.map((item) => Object.freeze(item))),
    calculationVersion: "payroll-line-v1",
  });
}
