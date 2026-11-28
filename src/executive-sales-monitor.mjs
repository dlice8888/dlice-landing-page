/**
 * Executive sales monitor domain calculations.
 *
 * This module is deliberately data-source agnostic. Callers must resolve the
 * authenticated actor's tenant/branch scope on the server before loading rows.
 * Client-supplied tenant or branch identifiers are never an authorization input.
 */

export const KPI_DEFINITION_VERSION = "sales-monitor.v1";
export const SUPPORTED_BRANCH_TIMEZONES = Object.freeze([
  "Asia/Jakarta",
  "Asia/Makassar",
  "Asia/Jayapura",
]);

const DAY_MS = 86_400_000;

function assertDate(value, label = "date") {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new TypeError(`${label} must be YYYY-MM-DD`);
  }
  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    throw new RangeError(`${label} is not a calendar date`);
  }
  return parsed;
}

function dateString(date) {
  return date.toISOString().slice(0, 10);
}

function shiftDate(date, days) {
  return new Date(date.getTime() + days * DAY_MS);
}

function zonedParts(epochMs, timeZone) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(epochMs));
  return Object.fromEntries(parts.map(({ type, value }) => [type, value]));
}

/** Convert a branch-local wall-clock boundary to an unambiguous UTC instant. */
export function localDateTimeToUtc(date, timeZone, hour = 0) {
  assertDate(date);
  if (!SUPPORTED_BRANCH_TIMEZONES.includes(timeZone)) {
    throw new RangeError("unsupported_branch_timezone");
  }
  if (!Number.isInteger(hour) || hour < 0 || hour > 23) {
    throw new RangeError("hour must be between 0 and 23");
  }

  const target = Date.parse(`${date}T${String(hour).padStart(2, "0")}:00:00.000Z`);
  let candidate = target;
  // Iterate the IANA offset to converge to the requested local wall clock.
  for (let i = 0; i < 4; i += 1) {
    const p = zonedParts(candidate, timeZone);
    const represented = Date.UTC(
      Number(p.year), Number(p.month) - 1, Number(p.day),
      Number(p.hour), Number(p.minute), Number(p.second),
    );
    const delta = target - represented;
    candidate += delta;
    if (delta === 0) break;
  }
  const check = zonedParts(candidate, timeZone);
  if (
    check.year !== date.slice(0, 4) ||
    check.month !== date.slice(5, 7) ||
    check.day !== date.slice(8, 10) ||
    check.hour !== String(hour).padStart(2, "0")
  ) {
    throw new RangeError("business_date_boundary_unresolvable");
  }
  return new Date(candidate).toISOString();
}

function startOfWeek(date) {
  // ISO week: Monday is the first business day.
  const weekday = date.getUTCDay() || 7;
  return shiftDate(date, 1 - weekday);
}

/**
 * Resolve day/week/month into half-open UTC boundaries in the branch timezone.
 * The end boundary is exclusive, avoiding midnight double counting.
 */
export function resolveBusinessWindow({ period, anchorDate, timeZone }) {
  const anchor = assertDate(anchorDate, "anchorDate");
  if (!SUPPORTED_BRANCH_TIMEZONES.includes(timeZone)) {
    throw new RangeError("unsupported_branch_timezone");
  }
  let from = anchor;
  let through = anchor;
  if (period === "week") {
    from = startOfWeek(anchor);
    through = shiftDate(from, 6);
  } else if (period === "month") {
    from = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth(), 1));
    through = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() + 1, 0));
  } else if (period !== "day") {
    throw new RangeError("period must be day, week, or month");
  }

  const fromDate = dateString(from);
  const throughDate = dateString(through);
  const nextDate = dateString(shiftDate(through, 1));
  return Object.freeze({
    period,
    time_zone: timeZone,
    from_business_date: fromDate,
    through_business_date: throughDate,
    starts_at: localDateTimeToUtc(fromDate, timeZone),
    ends_at: localDateTimeToUtc(nextDate, timeZone),
    kpi_definition_version: KPI_DEFINITION_VERSION,
  });
}

function safeMoney(value, field) {
  const amount = Number(value);
  if (!Number.isSafeInteger(amount) || amount < 0) {
    throw new TypeError(`${field} must be a non-negative safe integer`);
  }
  return amount;
}

function insideWindow(timestamp, window) {
  const value = Date.parse(timestamp);
  return Number.isFinite(value) &&
    value >= Date.parse(window.starts_at) &&
    value < Date.parse(window.ends_at);
}

/**
 * Reconcile source transactions using the fields currently present in staging.
 * IMPORTANT: pos_sales has created_at + payment_status but no paid_at/business_date.
 * Therefore this is a created_at-attributed paid-sales proxy, not a certified
 * paid-time business-date ledger. Refunds use processed_at. Settlement remains
 * a separate cash-reconciliation measure and is never substituted for revenue.
 */
export function aggregateSalesMonitor({ sales, refunds, settlements = [], window, branchIds }) {
  if (!window?.starts_at || !window?.ends_at) throw new TypeError("window is required");
  const allowedBranches = new Set(branchIds || []);
  const seenSales = new Set();
  const seenRefunds = new Set();
  const saleById = new Map();
  const includedSales = [];
  const includedRefunds = [];
  const includedSettlements = [];

  for (const sale of sales || []) {
    if (!sale?.id || seenSales.has(sale.id)) continue;
    seenSales.add(sale.id);
    if (!allowedBranches.has(sale.branch_id) || sale.payment_status !== "paid") continue;
    const gross = safeMoney(sale.subtotal_idr, "subtotal_idr");
    const discount = safeMoney(sale.discount_idr, "discount_idr");
    const total = safeMoney(sale.total_idr, "total_idr");
    if (gross - discount !== total) {
      throw new Error(`sale_total_mismatch:${sale.id}`);
    }
    // Prefer an explicit business_date, then the actual payment timestamp.
    // created_at is retained only as a clearly labelled legacy proxy.
    const recognitionField = typeof sale.business_date === "string"
      ? "business_date"
      : (sale.paid_at ? "paid_at" : "created_at");
    const recognitionValue = sale[recognitionField];
    const isInBusinessDateWindow = recognitionField === "business_date"
      ? recognitionValue >= window.from_business_date && recognitionValue <= window.through_business_date
      : insideWindow(recognitionValue, window);
    const normalized = {
      id: sale.id,
      transaction_code: sale.transaction_code || null,
      branch_id: sale.branch_id,
      created_at: sale.created_at,
      paid_at: sale.paid_at || null,
      business_date: sale.business_date || null,
      recognition_field: recognitionField,
      recognition_value: recognitionValue,
      gross_idr: gross,
      discount_idr: discount,
      net_before_refunds_idr: total,
    };
    saleById.set(sale.id, normalized);
    if (isInBusinessDateWindow) includedSales.push({ ...normalized });
  }

  const allProcessedRefundsBySale = new Map();
  for (const refund of refunds || []) {
    if (!refund?.id || seenRefunds.has(refund.id)) continue;
    seenRefunds.add(refund.id);
    if (refund.status !== "processed") continue;
    const sourceSale = saleById.get(refund.pos_sale_id);
    if (!sourceSale || sourceSale.branch_id !== refund.branch_id) {
      throw new Error(`refund_source_scope_mismatch:${refund.id}`);
    }
    const amount = safeMoney(refund.amount_idr, "refund.amount_idr");
    allProcessedRefundsBySale.set(
      refund.pos_sale_id,
      (allProcessedRefundsBySale.get(refund.pos_sale_id) || 0) + amount,
    );
    if (insideWindow(refund.processed_at, window)) {
      includedRefunds.push({
        id: refund.id,
        pos_sale_id: refund.pos_sale_id,
        branch_id: refund.branch_id,
        processed_at: refund.processed_at,
        amount_idr: amount,
      });
    }
  }
  for (const [saleId, refunded] of allProcessedRefundsBySale) {
    const sourceSale = saleById.get(saleId);
    if (refunded > sourceSale.net_before_refunds_idr) {
      throw new Error(`refund_exceeds_sale:${saleId}`);
    }
  }
  const refundBySale = new Map();
  for (const refund of includedRefunds) {
    refundBySale.set(refund.pos_sale_id, (refundBySale.get(refund.pos_sale_id) || 0) + refund.amount_idr);
  }
  for (const sale of includedSales) {
    sale.refund_idr = refundBySale.get(sale.id) || 0;
    sale.net_sales_idr = sale.net_before_refunds_idr - sale.refund_idr;
  }

  const settlementIds = new Set();
  for (const settlement of settlements || []) {
    if (!settlement?.id || settlementIds.has(settlement.id)) continue;
    settlementIds.add(settlement.id);
    if (!allowedBranches.has(settlement.branch_id) || !insideWindow(settlement.created_at, window)) continue;
    includedSettlements.push({
      id: settlement.id,
      provider_reference: settlement.provider_reference || null,
      gross_amount_idr: safeMoney(settlement.gross_amount_idr, "settlement.gross_amount_idr"),
      fee_amount_idr: safeMoney(settlement.fee_amount_idr, "settlement.fee_amount_idr"),
      net_amount_idr: safeMoney(settlement.net_amount_idr, "settlement.net_amount_idr"),
      status: settlement.status,
    });
  }

  const grossSales = includedSales.reduce((sum, sale) => sum + sale.gross_idr, 0);
  const discounts = includedSales.reduce((sum, sale) => sum + sale.discount_idr, 0);
  const refundsTotal = includedRefunds.reduce((sum, refund) => sum + refund.amount_idr, 0);
  const netSales = includedSales.reduce((sum, sale) => sum + sale.net_before_refunds_idr, 0) - refundsTotal;
  const settlementNet = includedSettlements
    .filter((item) => item.status === "reconciled")
    .reduce((sum, item) => sum + item.net_amount_idr, 0);

  const recognitionFields = new Set(includedSales.map((sale) => sale.recognition_field));
  const salesBusinessDateCertified = includedSales.length > 0 &&
    [...recognitionFields].every((field) => field === "business_date" || field === "paid_at");
  const salesRecognitionSemantics = recognitionFields.size === 0
    ? "no_sales_in_window"
    : recognitionFields.size > 1
      ? "mixed_business_date_paid_at_and_legacy_created_at"
      : recognitionFields.has("business_date")
        ? "business_date"
        : recognitionFields.has("paid_at")
          ? "paid_at_branch_timezone"
          : "created_at_legacy_proxy";

  return Object.freeze({
    kpi_definition_version: KPI_DEFINITION_VERSION,
    sales_recognition_semantics: salesRecognitionSemantics,
    sales_recognition_timestamp_field: recognitionFields.size === 1 ? [...recognitionFields][0] : "per_sale",
    sales_business_date_certified: salesBusinessDateCertified,
    window,
    totals: Object.freeze({
      gross_sales_idr: grossSales,
      discounts_idr: discounts,
      refunds_idr: refundsTotal,
      net_sales_idr: netSales,
      paid_transactions: includedSales.length,
      settlement_net_received_idr: settlementNet,
      settlement_vs_net_sales_idr: settlementNet - netSales,
    }),
    sources: Object.freeze({
      sales: includedSales,
      refunds: includedRefunds,
      settlements: includedSettlements,
    }),
  });
}
