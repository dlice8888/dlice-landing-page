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
