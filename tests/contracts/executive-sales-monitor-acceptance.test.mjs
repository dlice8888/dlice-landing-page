import test from "node:test";
import assert from "node:assert/strict";
import { resolveBusinessWindow, aggregateSalesMonitor } from "../../src/executive-sales-monitor.mjs";

test("business-day boundaries use WIB, WITA and WIT local midnight", () => {
  const cases = [
    ["Asia/Jakarta", "2026-11-28T17:00:00.000Z"],
    ["Asia/Makassar", "2026-11-28T16:00:00.000Z"],
    ["Asia/Jayapura", "2026-11-28T15:00:00.000Z"],
  ];
  for (const [timeZone, expected] of cases) {
    const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-29", timeZone });
    assert.equal(window.starts_at, expected);
    assert.equal(Date.parse(window.ends_at) - Date.parse(window.starts_at), 86400000);
  }
});

test("week and month windows are half-open and use branch-local calendar dates", () => {
  const week = resolveBusinessWindow({ period: "week", anchorDate: "2026-11-29", timeZone: "Asia/Jakarta" });
  assert.equal(week.from_business_date, "2026-11-23");
  assert.equal(week.through_business_date, "2026-11-29");
  assert.equal(Date.parse(week.ends_at) - Date.parse(week.starts_at), 7 * 86400000);
  const month = resolveBusinessWindow({ period: "month", anchorDate: "2026-11-12", timeZone: "Asia/Jayapura" });
  assert.equal(month.from_business_date, "2026-11-01");
  assert.equal(month.through_business_date, "2026-11-30");
});

test("paid sales, discounts and processed refunds reconcile with duplicate protection", () => {
  const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-29", timeZone: "Asia/Jakarta" });
  const sales = [
    { id: "s1", branch_id: "b1", payment_status: "paid", created_at: "2026-11-28T17:00:00.000Z", subtotal_idr: 100000, discount_idr: 10000, total_idr: 90000 },
    { id: "s2", branch_id: "b1", payment_status: "paid", created_at: "2026-11-29T16:59:59.999Z", subtotal_idr: 50000, discount_idr: 0, total_idr: 50000 },
    { id: "s3", branch_id: "b1", payment_status: "pending", created_at: "2026-11-29T10:00:00.000Z", subtotal_idr: 10000, discount_idr: 0, total_idr: 10000 },
  ];
  const refunds = [
    { id: "r1", pos_sale_id: "s1", branch_id: "b1", status: "processed", processed_at: "2026-11-29T02:00:00.000Z", amount_idr: 20000 },
    { id: "r1", pos_sale_id: "s1", branch_id: "b1", status: "processed", processed_at: "2026-11-29T02:00:00.000Z", amount_idr: 20000 },
  ];
  const result = aggregateSalesMonitor({ sales: [...sales, sales[0]], refunds, window, branchIds: ["b1"] });
  assert.equal(result.totals.gross_sales_idr, 150000);
  assert.equal(result.totals.discounts_idr, 10000);
  assert.equal(result.totals.refunds_idr, 20000);
  assert.equal(result.totals.net_sales_idr, 120000);
  assert.equal(result.totals.paid_transactions, 2);
  assert.equal(result.sales_recognition_semantics, "paid_status_at_created_at_branch_timezone_proxy");
  assert.equal(result.sales_business_date_certified, false);
});

test("out-of-window delayed payment attribution cannot be inferred from unavailable paid_at", () => {
  const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-29", timeZone: "Asia/Jakarta" });
  const result = aggregateSalesMonitor({
    sales: [{ id: "late", branch_id: "b1", payment_status: "paid", created_at: "2026-11-28T16:59:59.999Z", subtotal_idr: 1000, discount_idr: 0, total_idr: 1000 }],
    refunds: [], window, branchIds: ["b1"],
  });
  assert.equal(result.totals.paid_transactions, 0);
  assert.equal(result.sales_business_date_certified, false);
});
