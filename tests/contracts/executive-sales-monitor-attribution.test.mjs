import test from "node:test";
import assert from "node:assert/strict";
import { aggregateSalesMonitor, resolveBusinessWindow } from "../../src/executive-sales-monitor.mjs";

const sale = (overrides = {}) => ({
  id: "sale-1", transaction_code: "DLC-28/11/2026-00001", branch_id: "branch-1",
  created_at: "2026-11-27T18:00:00.000Z", paid_at: "2026-11-27T18:05:00.000Z",
  business_date: "2026-11-28", payment_status: "paid",
  subtotal_idr: 100000, discount_idr: 10000, total_idr: 90000, ...overrides,
});

test("business-date attribution uses explicit business_date and reconciles processed refunds", () => {
  const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-28", timeZone: "Asia/Jakarta" });
  const result = aggregateSalesMonitor({
    sales: [sale(), sale()],
    refunds: [{
      id: "refund-1", pos_sale_id: "sale-1", branch_id: "branch-1",
      processed_at: "2026-11-28T05:00:00.000Z", amount_idr: 20000, status: "processed",
    }],
    window, branchIds: ["branch-1"],
  });
  assert.equal(result.totals.gross_sales_idr, 100000);
  assert.equal(result.totals.discounts_idr, 10000);
  assert.equal(result.totals.refunds_idr, 20000);
  assert.equal(result.totals.net_sales_idr, 70000);
  assert.equal(result.totals.paid_transactions, 1);
  assert.equal(result.sales_business_date_certified, true);
  assert.equal(result.sources.sales[0].recognition_field, "business_date");
});

test("paid_at wins over late created_at and is converted through branch timezone cutoff", () => {
  const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-28", timeZone: "Asia/Makassar" });
  const result = aggregateSalesMonitor({
    sales: [sale({
      business_date: null,
      created_at: "2026-11-28T17:00:00.000Z",
      paid_at: "2026-11-27T17:30:00.000Z",
    })],
    refunds: [], window, branchIds: ["branch-1"],
  });
  assert.equal(result.totals.paid_transactions, 1);
  assert.equal(result.sales_business_date_certified, true);
  assert.equal(result.sales_recognition_timestamp_field, "paid_at");
});

test("WIB, WITA and WIT use distinct local midnight boundaries", () => {
  const expected = {
    "Asia/Jakarta": "2026-11-27T17:00:00.000Z",
    "Asia/Makassar": "2026-11-27T16:00:00.000Z",
    "Asia/Jayapura": "2026-11-27T15:00:00.000Z",
  };
  for (const [timeZone, startsAt] of Object.entries(expected)) {
    const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-28", timeZone });
    assert.equal(window.starts_at, startsAt);
    assert.equal(window.ends_at, new Date(Date.parse(startsAt) + 86400000).toISOString());
  }
});

test("legacy created_at fallback is explicitly uncertified, and duplicate refunds are ignored", () => {
  const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-28", timeZone: "Asia/Jakarta" });
  const result = aggregateSalesMonitor({
    sales: [sale({ paid_at: null, business_date: null }), sale({ paid_at: null, business_date: null })],
    refunds: [
      { id: "refund-1", pos_sale_id: "sale-1", branch_id: "branch-1", processed_at: "2026-11-28T04:00:00Z", amount_idr: 10000, status: "processed" },
      { id: "refund-1", pos_sale_id: "sale-1", branch_id: "branch-1", processed_at: "2026-11-28T04:00:00Z", amount_idr: 10000, status: "processed" },
    ],
    window, branchIds: ["branch-1"],
  });
  assert.equal(result.totals.paid_transactions, 1);
  assert.equal(result.totals.refunds_idr, 10000);
  assert.equal(result.sales_business_date_certified, false);
  assert.equal(result.sales_recognition_semantics, "created_at_legacy_proxy");
});

test("cross-branch sale is excluded and cross-branch refund source is rejected", () => {
  const window = resolveBusinessWindow({ period: "day", anchorDate: "2026-11-28", timeZone: "Asia/Jakarta" });
  const result = aggregateSalesMonitor({ sales: [sale()], refunds: [], window, branchIds: ["branch-2"] });
  assert.equal(result.totals.paid_transactions, 0);
  assert.throws(() => aggregateSalesMonitor({
    sales: [sale()],
    refunds: [{ id: "r-1", pos_sale_id: "sale-1", branch_id: "branch-2", processed_at: "2026-11-28T04:00:00Z", amount_idr: 1000, status: "processed" }],
    window, branchIds: ["branch-1"],
  }), /refund_source_scope_mismatch/);
});
