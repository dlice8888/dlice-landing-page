#!/usr/bin/env node
/**
 * Manual positive-path staging E2E for PO -> approval -> receipt -> stock ledger.
 * It writes only to the explicitly seeded QA-DLICE-A branch and QA flour item.
 * Records are retained for audit and carry an AUTOMATED QA note; never point
 * these variables at production.
 */
import assert from "node:assert/strict";

const required = [
  "STAGING_SUPABASE_URL",
  "STAGING_SUPABASE_PUBLIC_KEY",
  "STAGING_EDGE_FUNCTION_URL",
  "STAGING_TEST_OWNER_USERNAME",
  "STAGING_TEST_OWNER_PASSWORD",
];
const missing = required.filter((key) => !process.env[key]);
if (missing.length) {
  console.error("BLOCKED: missing required staging variables:", missing.join(", "));
  process.exit(2);
}

const base = process.env.STAGING_SUPABASE_URL.replace(/\/$/, "");
const edge = new URL(process.env.STAGING_EDGE_FUNCTION_URL);
const expected = "https://higoadrzxnhzbbwhdbmh.supabase.co";
if (base !== expected || edge.origin !== expected || edge.pathname !== "/functions/v1/dlice-orders") {
  console.error("REFUSED: positive-path test is restricted to the known D'Lice staging project.");
  process.exit(2);
}

const branchId = "90000000-0000-4000-8000-000000000001"; // QA-DLICE-A
const inventoryItemId = "90000000-0000-4000-8000-000000000201"; // QA-DLICE-FLOUR
const quantity = 7;
const suffix = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
const receiptNumber = `QA-RCV-${suffix}`;
const note = `AUTOMATED QA E2E; procurement receiving; ${suffix}`;
const anon = process.env.STAGING_SUPABASE_PUBLIC_KEY;

async function tokenForOwner() {
  const response = await fetch(`${base}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anon, "content-type": "application/json" },
    body: JSON.stringify({
      email: `${process.env.STAGING_TEST_OWNER_USERNAME.toLowerCase()}@accounts.dlice.internal`,
      password: process.env.STAGING_TEST_OWNER_PASSWORD,
    }),
  });
  const body = await response.json().catch(() => ({}));
  assert.equal(response.status, 200, "Owner QA token must be issued by staging Auth");
  assert.equal(typeof body.access_token, "string", "Owner token must be present");
  return body.access_token;
}

async function call(action, payload, token) {
  const response = await fetch(edge, {
    method: "POST",
    headers: {
      apikey: anon,
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ action, ...payload }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`${action} failed with HTTP ${response.status}: ${String(body.error || "no error detail")}`);
  }
  return body;
}

async function main() {
  const token = await tokenForOwner();
  const before = await call("erp-list-inventory", { branch_id: branchId }, token);
  const previous = Number(before.balances.find((x) => x.inventory_item_id === inventoryItemId)?.on_hand ?? 0);

  const created = await call("erp-create-purchase-order", {
    branch_id: branchId,
    items: [{ inventory_item_id: inventoryItemId, quantity, unit_cost_idr: 150 }],
    notes: note,
  }, token);
  const po = created.purchase_order;
  assert.ok(po?.id, "PO must be created");
  assert.equal(po.status, "draft");
  console.log("PASS P2P-01 create draft PO");

  await call("erp-update-purchase-order", { id: po.id, status: "submitted" }, token);
  await call("erp-update-purchase-order", { id: po.id, status: "approved" }, token);
  await call("erp-update-purchase-order", { id: po.id, status: "ordered" }, token);
  console.log("PASS P2P-02 submit -> Owner approval -> ordered");

  const listed = await call("erp-list-purchase-orders", { branch_id: branchId }, token);
  const listedPo = listed.purchase_orders.find((x) => x.id === po.id);
  assert.ok(listedPo, "PO must be visible in branch-scoped list");
  const line = (listedPo.purchase_order_items || []).find((x) => x.inventory_item_id === inventoryItemId);
  assert.ok(line?.id, "PO list must expose purchase_order_item_id for receiving");
  assert.equal(Number(line.quantity), quantity, "PO line quantity must match the requested amount");
  console.log("PASS P2P-03 PO list exposes receipt-ready line IDs");

  const received = await call("erp-receive-purchase-order", {
    purchase_order_id: po.id,
    receipt_number: receiptNumber,
    supplier_delivery_reference: `QA-DELIVERY-${suffix}`,
    notes: note,
    items: [{ purchase_order_item_id: line.id, quantity_received: quantity }],
  }, token);
  assert.equal(received.purchase_order_status, "received", "PO must become fully received");
  assert.equal(received.lines_received, 1, "Exactly one receipt line must post");
  console.log("PASS P2P-04 GRN posts and PO reaches received");

  const after = await call("erp-list-inventory", { branch_id: branchId }, token);
  const current = Number(after.balances.find((x) => x.inventory_item_id === inventoryItemId)?.on_hand ?? 0);
  assert.ok(Math.abs((current - previous) - quantity) < 0.0001,
    `Stock ledger delta must be ${quantity}; observed ${current - previous}`);
  console.log("PASS P2P-05 stock balance delta matches receipt quantity");
  console.log(`PASS P2P E2E complete; PO ${po.po_number}; receipt ${receiptNumber}; QA branch only.`);
}

main().catch((error) => {
  console.error("FAIL P2P positive-path E2E:", error.message);
  process.exitCode = 1;
});
