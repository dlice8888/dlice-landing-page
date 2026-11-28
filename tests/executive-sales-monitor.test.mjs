import test from "node:test";
import assert from "node:assert/strict";
import {
  aggregateSalesMonitor,
  localDateTimeToUtc,
  resolveBusinessWindow,
} from "../src/executive-sales-monitor.mjs";

test("branch-local midnight boundaries cover WIB, WITA and WIT", () => {
  assert.equal(localDateTimeToUtc("2026-11-28", "Asia/Jakarta"), "2026-11-27T17:00:00.000Z");
  assert.equal(localDateTimeToUtc("2026-11-28", "Asia/Makassar"), "2026-11-27T16:00:00.000Z");
  assert.equal(localDateTimeToUtc("2026-11-28", "Asia/Jayapura"), "2026-11-27T15:00:00.000Z");
});

test("day window uses an exclusive next local midnight", () => {
  const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-28", timeZone: "Asia/Jakarta" });
  assert.equal(window.starts_at, "2026-11-27T17:00:00.000Z");
  assert.equal(window.ends_at, "2026-11-28T17:00:00.000Z");
});

test("week starts Monday and month includes the final calendar day", () => {
  const week = resolveBusinessWindow({ period: "week", anchorDate: "2026-11-28", timeZone: "Asia/Jakarta" });
  assert.equal(week.from_business_date, "2026-11-23");
  assert.equal(week.through_business_date, "2026-11-29");
  const month = resolveBusinessWindow({ period: "month", anchorDate: "2026-11-28", timeZone: "Asia/Jayapura" });
  assert.equal(month.from_business_date, "2026-11-01");
  assert.equal(month.through_business_date, "2026-11-30");
});

test("sales, discounts, processed refunds and settlement are reconciled independently", () => {
  const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-28", timeZone: "Asia/Jakarta" });
  const sale = { id: "s1", branch_id: "b1", payment_status: "paid", created_at: "2026-11-27T18:00:00Z", subtotal_idr: 100000, discount_idr: 10000, total_idr: 90000 };
  const result = aggregateSalesMonitor({
    window, branchIds: ["b1"],
    sales: [sale, sale, { ...sale, id: "late", created_at: window.ends_at }],
    refunds: [
      { id: "r1", pos_sale_id: "s1", branch_id: "b1", status: "processed", processed_at: "2026-11-27T19:00:00Z", amount_idr: 20000 },
      { id: "r1", pos_sale_id: "s1", branch_id: "b1", status: "processed", processed_at: "2026-11-27T19:00:00Z", amount_idr: 20000 },
      { id: "pending", pos_sale_id: "s1", branch_id: "b1", status: "approved", processed_at: "2026-11-27T19:00:00Z", amount_idr: 5000 },
    ],
    settlements: [{ id: "st1", created_at: "2026-11-27T19:30:00Z", gross_amount_idr: 90000, fee_amount_idr: 1000, net_amount_idr: 89000, status: "reconciled" }],
  });
  assert.deepEqual(result.totals, {
    gross_sales_idr: 100000, discounts_idr: 10000, refunds_idr: 20000,
    net_sales_idr: 70000, paid_transactions: 1,
    settlement_net_received_idr: 89000, settlement_vs_net_sales_idr: 19000,
  });
  assert.equal(result.sources.sales.length, 1);
  assert.equal(result.sources.refunds.length, 1);
});

test("rejects inconsistent sale totals and refunds larger than the paid sale", () => {
  const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-28", timeZone: "Asia/Jakarta" });
  const sale = { id: "s1", branch_id: "b1", payment_status: "paid", created_at: "2026-11-27T18:00:00Z", subtotal_idr: 100000, discount_idr: 10000, total_idr: 95000 };
  assert.throws(() => aggregateSalesMonitor({ window, branchIds: ["b1"], sales: [sale], refunds: [] }), /sale_total_mismatch/);
  assert.throws(() => aggregateSalesMonitor({
    window, branchIds: ["b1"], sales: [{ ...sale, total_idr: 90000 }],
    refunds: [{ id: "r1", pos_sale_id: "s1", branch_id: "b1", status: "processed", processed_at: "2026-11-27T19:00:00Z", amount_idr: 90001 }],
  }), /refund_exceeds_sale/);
});

test("does not include another branch even when a row is supplied", () => {
  const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-28", timeZone: "Asia/Jakarta" });
  const result = aggregateSalesMonitor({
    window, branchIds: ["branch-a"],
    sales: [{ id: "s1", branch_id: "branch-b", payment_status: "paid", created_at: "2026-11-27T18:00:00Z", subtotal_idr: 10, discount_idr: 0, total_idr: 10 }],
    refunds: [],
  });
  assert.equal(result.totals.net_sales_idr, 0);
});
