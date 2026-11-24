import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const edge = await readFile(new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../../supabase/migrations/20261124193500_pos_checkout_lifecycle.sql", import.meta.url), "utf8");

function actionBlock(name, nextAction) {
  const start = edge.indexOf(`if (action === "${name}")`);
  assert.notEqual(start, -1, `missing action ${name}`);
  const end = nextAction ? edge.indexOf(`if (action === "${nextAction}")`, start + 1) : edge.length;
  assert.ok(end > start, `could not delimit action ${name}`);
  return edge.slice(start, end);
}

test("split tender is branch-authorized and uses atomic service-role RPC", () => {
  const block = actionBlock("erp-create-pos-sale-split", "erp-hold-pos-order");
  assert.match(block, /hasPerm\("pos"\)/);
  assert.match(block, /branchAccess\(branchId\)/);
  assert.match(block, /tenders\.length < 2/);
  assert.match(block, /bank_transfer.*qris|cash.*bank_transfer/);
  assert.match(block, /erp_create_pos_sale_split_tender_idempotent/);
  assert.match(block, /p_actor_user_id:\s*actor\.user\.id/);
});

test("hold and resume are branch-authorized and actor-scoped", () => {
  const hold = actionBlock("erp-hold-pos-order", "erp-resume-pos-order");
  const resume = actionBlock("erp-resume-pos-order", "erp-get-pos-receipt");
  assert.match(hold, /branchAccess\(branchId\)/);
  assert.match(hold, /erp_hold_pos_order/);
  assert.match(hold, /p_actor_user_id:\s*actor\.user\.id/);
  assert.match(resume, /branchAccess\(branchId\)/);
  assert.match(resume, /erp_resume_pos_order/);
  assert.match(resume, /p_actor_user_id:\s*actor\.user\.id/);
  assert.match(resume, /data\?\.status === "expired"/);
});

test("digital receipt is branch-authorized and generated from immutable database snapshot", () => {
  const block = actionBlock("erp-get-pos-receipt", "erp-create-pos-sale");
  assert.match(block, /branchAccess\(branchId\)/);
  assert.match(block, /erp_get_pos_receipt/);
  assert.match(migration, /CREATE TABLE public\.pos_sale_receipts/);
  assert.match(migration, /CONSTRAINT pos_sale_receipts_sale_key UNIQUE \(sale_id\)/);
  assert.match(migration, /ON CONFLICT \(sale_id\) DO NOTHING/);
});

test("split tender cannot mark a sale settled unless allocations exactly equal total", () => {
  assert.match(migration, /v_tender_total <> v_total/);
  assert.match(migration, /split_tender_total_mismatch/);
  assert.match(migration, /cardinality\(v_methods\) < 2/);
  assert.match(migration, /v_cash_total/);
  assert.match(migration, /expected_cash_idr = expected_cash_idr \+ v_cash_total/);
});

test("held orders are payload-idempotent and cannot resume after expiry", () => {
  assert.match(migration, /hold_key_payload_mismatch/);
  assert.match(migration, /payload_fingerprint/);
  assert.match(migration, /expires_at <= now\(\)/);
  assert.match(migration, /status = 'expired'/);
  assert.match(migration, /sale_idempotency_key/);
});

test("new POS tables and RPCs remain service-role-only with RLS", () => {
  for (const table of ["pos_sale_tenders", "pos_checkout_idempotency_requests", "pos_held_orders", "pos_sale_receipts"]) {
    assert.match(migration, new RegExp(`ALTER TABLE public\\.${table} ENABLE ROW LEVEL SECURITY`));
    assert.match(migration, new RegExp(`${table}_deny_direct_client_access`));
  }
  for (const rpc of [
    "erp_create_pos_sale_split_tender_idempotent",
    "erp_hold_pos_order",
    "erp_resume_pos_order",
    "erp_get_pos_receipt",
  ]) {
    const idx = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${rpc}`);
    assert.notEqual(idx, -1);
    const fn = migration.slice(idx, migration.indexOf("$function$;", idx) + "$function$;".length);
    assert.match(fn, /SECURITY INVOKER/);
    assert.match(fn, /auth\.jwt\(\) ->> 'role'/);
    assert.match(fn, /SET search_path = public/);
  }
});

test("cashier UI exposes modifier, split tender, hold/resume and receipt actions", async () => {
  const ui = await readFile(new URL("../../erp.html", import.meta.url), "utf8");
  for (const marker of [
    "erp-list-pos-modifiers", "erp-list-held-pos-orders", "erp-create-pos-sale-split",
    "erp-hold-pos-order", "erp-resume-pos-order", "erp-get-pos-receipt",
    "posSplitTender", "holdPosOrder", "printPosReceipt",
  ]) assert.ok(ui.includes(marker), `ERP POS UI missing ${marker}`);
});

test("offline replay supports split tender with the same operation idempotency key", () => {
  const block = actionBlock("erp-sync-offline-operation", "erp-reconcile-pos-sale");
  assert.match(block, /operation\.tenders/);
  assert.match(block, /erp_create_pos_sale_split_tender_idempotent/);
  assert.match(block, /p_idempotency_key:key/);
  assert.match(block, /offline_sync_receipts/);
});

test("modifier and held-order discovery are branch-authorized", () => {
  const modifiers = actionBlock("erp-list-pos-modifiers", "erp-list-held-pos-orders");
  const held = actionBlock("erp-list-held-pos-orders", "erp-create-pos-sale-split");
  assert.match(modifiers, /hasPerm\("pos"\)/);
  assert.match(modifiers, /branchAccess\(branchId\)/);
  assert.match(modifiers, /product_modifiers/);
  assert.match(held, /branchAccess\(branchId\)/);
  assert.match(held, /actor_user_id.*actor\.user\.id/);
  assert.match(held, /status.*held/);
});

test("POS reconciliation computes tender allocation and cash drawer components", () => {
  const block = actionBlock("erp-reconcile-pos-sale", "erp-list-sales");
  assert.match(block, /pos_sale_tenders/);
  assert.match(block, /allocated_total_idr/);
  assert.match(block, /cash_tender_idr/);
  assert.match(block, /payment_reconciliation/);
  assert.match(block, /status:allocatedTotal===Number\(sale\.total_idr\)/);
});
