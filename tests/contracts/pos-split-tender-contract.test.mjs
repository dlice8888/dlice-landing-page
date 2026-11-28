import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const html = readFileSync("erp.html", "utf8");
const edge = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");

test("POS UI exposes split tender allocations and validates distinct methods", () => {
  assert.match(html, /<option value="split">Split tender<\/option>/);
  assert.match(html, /id="posTenderMethod1"/);
  assert.match(html, /id="posTenderAmount1"/);
  assert.match(html, /id="posTenderMethod2"/);
  assert.match(html, /id="posTenderAmount2"/);
  assert.match(html, /tenders\[0\]\.payment_method===tenders\[1\]\.payment_method/);
  assert.match(html, /erp-create-pos-sale/);
});

test("authenticated POS Edge action calls the atomic split-tender RPC", () => {
  assert.match(edge, /if\(method==="split"\)/);
  assert.match(edge, /erp_create_pos_sale_split_tender_idempotent/);
  assert.match(edge, /p_tenders:cleanTenders/);
  assert.match(edge, /split_tender_total_mismatch/);
  assert.match(edge, /branchAccess\(branchId\)/);
  assert.match(edge, /p_actor_user_id:actor\.user\.id/);
  assert.match(edge, /p_idempotency_key:idempotencyKey/);
});

test("offline POS replay preserves split tender payload and idempotency", () => {
  const start = edge.indexOf('if (action === "erp-sync-offline-operation")');
  const end = edge.indexOf('if (action === "erp-reconcile-pos-sale")', start);
  assert.ok(start >= 0 && end > start);
  const offline = edge.slice(start, end);
  assert.match(offline, /operation\.tenders/);
  assert.match(offline, /erp_create_pos_sale_split_tender_idempotent/);
  assert.match(offline, /p_idempotency_key:key/);
  assert.match(offline, /payload_fingerprint/);
});

test("POS reconciliation endpoint includes tender, immutable receipt, shift, cash and Finance source rows", () => {
  const start = edge.indexOf('if (action === "erp-reconcile-pos-sale")');
  const end = edge.indexOf('if (action === "erp-list-sales")', start);
  assert.ok(start >= 0 && end > start);
  const reconciliation = edge.slice(start, end);
  for (const table of ["pos_sale_tenders", "pos_sale_receipts", "finance_journal_entries", "pos_shifts", "cash_reconciliations", "stock_movements", "admin_audit_logs"]) {
    assert.match(reconciliation, new RegExp('from\\("' + table + '"\\)'));
  }
  assert.match(reconciliation, /tender_total_idr/);
  assert.match(reconciliation, /tender_matches_sale_total/);
  assert.match(reconciliation, /pos_sales_single_method/);
  assert.match(reconciliation, /missing_split_tender_rows/);
  assert.match(reconciliation, /branchAccess\(branchId\)/);
});
