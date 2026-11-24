#!/usr/bin/env node
/**
 * Positive-path staging E2E for POS -> payment -> KDS -> recipe stock -> report.
 * Uses only the fixed QA-DLICE-A branch and inactive QA fixture product. The product is
 * activated only for the duration of this test and is restored to inactive in finally.
 */
import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { findActiveOwnerUserId, revokeLocalSession, tokenForExistingUser } from "../runtime/staging-passwordless-auth.mjs";

const required = [
  "STAGING_SUPABASE_URL",
  "STAGING_SUPABASE_PUBLIC_KEY",
  "STAGING_SUPABASE_SERVICE_ROLE_KEY",
];
const missing = required.filter((key) => !process.env[key]);
if (missing.length) {
  console.error("BLOCKED: missing required staging variables:", missing.join(", "));
  process.exit(2);
}

const base = process.env.STAGING_SUPABASE_URL.replace(/\/$/, "");
const edge = new URL(`${base}/functions/v1/dlice-orders`);
const expected = "https://higoadrzxnhzbbwhdbmh.supabase.co";
if (base !== expected || edge.origin !== expected || edge.pathname !== "/functions/v1/dlice-orders") {
  console.error("REFUSED: KDS/POS E2E is restricted to the known D'Lice staging project.");
  process.exit(2);
}

const branchId = "90000000-0000-4000-8000-000000000001"; // QA-DLICE-A
const productId = "90000000-0000-4000-8000-000000000100"; // inactive QA-only product
const productSlug = "qa-staging-only-fixture";
const recipeId = "90000000-0000-4000-8000-000000000401";
const flourId = "90000000-0000-4000-8000-000000000201";
const secondIngredientId = "90000000-0000-4000-8000-000000000202";
const suffix = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
const operationId = `qa-pos-${suffix}`;
const deviceId = `qa-device-${suffix}`;
const note = `AUTOMATED QA E2E KDS/POS/stock; ${suffix}`;
const anon = process.env.STAGING_SUPABASE_PUBLIC_KEY;
const evidence = {
  status: "running",
  project: "dlice-staging",
  branch_id: branchId,
  product_id: productId,
  recipe_id: recipeId,
  operation_id: operationId,
  checks: [],
  cleanup_errors: [],
};
let ownerToken = "";
let managerToken = "";
let managerUserId = "";
let ownerUserId = "";
let createdShiftId = null;
let trackingTouched = false;
let productTouched = false;
let modifierId = null;
let modifierCode = "";
let modifierTouched = false;
let splitSaleId = null;

async function call(action, payload, token = managerToken) {
  const response = await fetch(edge, {
    method: "POST",
    headers: { apikey: anon, authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ action, ...payload }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`${action} failed HTTP ${response.status}: ${String(body.error || "no error detail")}`);
  return body;
}

async function expectStatus(action, payload, token, expectedStatus) {
  const response = await fetch(edge, {
    method: "POST",
    headers: { apikey: anon, authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ action, ...payload }),
  });
  const body = await response.json().catch(() => ({}));
  assert.equal(response.status, expectedStatus, `${action} must return HTTP ${expectedStatus}; response=${String(body.error || "")}`);
  return body;
}

function balanceOf(data, itemId) {
  return Number((data.balances || []).find((row) => row.inventory_item_id === itemId)?.on_hand ?? 0);
}

function pass(name, details = {}) {
  evidence.checks.push({ name, status: "PASS", ...details });
  console.log(`PASS ${name}`);
}


async function restoreQaProduct() {
  if (!ownerToken) return;
  if (modifierTouched && modifierId) {
    try {
      await call("erp-save-product-modifier", {
        modifier_id: modifierId, product_id: productId, modifier_group: "qa-e2e",
        modifier_code: modifierCode, name: "QA E2E modifier", price_delta_idr: 25,
        is_required: false, is_active: false,
      }, ownerToken);
    } catch (error) {
      evidence.cleanup_errors.push(`QA modifier deactivate: ${error.message}`);
    }
  }
  if (trackingTouched) {
    try {
      await call("erp-set-product-stock-tracking", { product_id: productId, enabled: false }, ownerToken);
    } catch (error) {
      evidence.cleanup_errors.push(`stock tracking disable: ${error.message}`);
    }
  }
  if (productTouched) {
    try {
      await call("admin-save-product", {
        id: productId,
        name: "[TEST ONLY] Staging QA Fixture Product",
        slug: productSlug,
        description: "Synthetic inactive product for staging acceptance tests; never a sellable menu item.",
        category: "other",
        display_order: 99999,
        unit_price_idr: 100,
        is_active: false,
        badge: "STAGING TEST ONLY",
        image_path: null,
      }, ownerToken);
    } catch (error) {
      evidence.cleanup_errors.push(`QA product deactivate: ${error.message}`);
    }
  }
}

async function closeCreatedShift() {
  if (!createdShiftId || !managerToken) return;
  try {
    const shifts = await call("erp-list-shifts", { branch_id: branchId });
    const shift = (shifts.shifts || []).find((row) => row.id === createdShiftId);
    if (shift?.status === "open") {
      await call("erp-close-shift", {
        shift_id: createdShiftId,
        counted_cash_idr: Number(shift.expected_cash_idr),
        notes: `AUTOMATED QA E2E close; ${suffix}`,
      });
    }
  } catch (error) {
    evidence.cleanup_errors.push(`shift close: ${error.message}`);
  }
}

async function main() {
  try {
    ownerUserId = await findActiveOwnerUserId({
      baseUrl: base,
      serviceRoleKey: process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY,
    });
    const session = await tokenForExistingUser({
      baseUrl: base,
      publicKey: anon,
      serviceRoleKey: process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY,
      userId: ownerUserId,
    });
    ownerToken = session.accessToken;
    ownerUserId = session.userId;
  } catch {
    throw new Error("STAGING_AUTH_BLOCKED: Existing confirmed staging Owner identity could not authenticate through a one-time magic link.");
  }

  // Feature-first E2E: use the already-provisioned staging Owner identity for this vertical slice.
  // This removes a separate Branch A login dependency; branch-scoped behavior remains covered by
  // the existing role/authorization contract tests. Owner's platform access is used only on staging.
  managerToken = ownerToken;
  managerUserId = ownerUserId;

  // Preflight fixture identity and state before any write; refuse to mutate a product that is already active.
  const catalog = await call("admin-list-products", {}, ownerToken);
  const fixtureProduct = (catalog.products || []).find((row) => row.id === productId);
  assert.ok(fixtureProduct, "Fixed QA product must exist in the staging catalog");
  assert.equal(fixtureProduct.slug, productSlug, "QA product ID must still map to the expected QA-only slug");
  assert.equal(fixtureProduct.is_active, false, "Refuse to run if the QA fixture product is already active");

  // Activate the fixture only for this run. finally restores it to inactive.
  productTouched = true;
  await call("admin-save-product", {
    id: productId,
    name: "[TEST ONLY] Staging QA Fixture Product",
    slug: productSlug,
    description: "Synthetic inactive product for staging acceptance tests; never a sellable menu item.",
    category: "other",
    display_order: 99999,
    unit_price_idr: 100,
    is_active: true,
    badge: "STAGING TEST ONLY",
    image_path: null,
  }, ownerToken);

  const recipes = await call("erp-list-recipes", {}, ownerToken);
  const recipe = (recipes.recipes || []).find((row) => row.id === recipeId);
  assert.ok(recipe, "Fixed QA recipe must exist");
  assert.equal(recipe.product_id, productId, "QA recipe must belong to the inactive QA fixture product");
  const recipeIngredients = (recipe.recipe_ingredients || []).map((row) => ({
    inventory_item_id: row.inventory_item_id,
    quantity_per_yield: Number(row.quantity_per_yield),
    unit: row.unit,
    is_optional: row.is_optional,
  })).sort((a, b) => a.inventory_item_id.localeCompare(b.inventory_item_id));
  assert.deepEqual(recipeIngredients, [
    { inventory_item_id: flourId, quantity_per_yield: 500, unit: "g", is_optional: false },
    { inventory_item_id: secondIngredientId, quantity_per_yield: 100, unit: "g", is_optional: false },
  ].sort((a, b) => a.inventory_item_id.localeCompare(b.inventory_item_id)),
  "QA recipe ingredients and units must match the reviewed 500g/100g fixture before stock writes");
  assert.ok(["draft", "active"].includes(recipe.status), "QA recipe must be draft or active; retired fixtures require a one-time staging reset");
  if (recipe.status !== "active") await call("erp-activate-recipe", { recipe_id: recipeId }, ownerToken);
  trackingTouched = true;
  await call("erp-set-product-stock-tracking", { product_id: productId, enabled: true }, ownerToken);
  pass("QA fixture product has active recipe and stock tracking");

  // Ensure deterministic positive stock for the two QA recipe ingredients.
  let inventory = await call("erp-list-inventory", { branch_id: branchId }, managerToken);
  const targets = [{ id: flourId, target: 1000 }, { id: secondIngredientId, target: 300 }];
  for (const item of targets) {
    const current = balanceOf(inventory, item.id);
    if (current < item.target) {
      await call("erp-stock-movement", {
        branch_id: branchId,
        inventory_item_id: item.id,
        movement_type: current === 0 ? "opening_balance" : "adjustment_in",
        quantity: item.target - current,
        notes: `AUTOMATED QA seed stock; ${suffix}`,
      }, ownerToken);
    }
  }
  inventory = await call("erp-list-inventory", { branch_id: branchId }, managerToken);
  const beforeFlour = balanceOf(inventory, flourId);
  const beforeSecond = balanceOf(inventory, secondIngredientId);
  assert.ok(beforeFlour >= 100 && beforeSecond >= 20, "QA recipe stock must be available");

  modifierCode = `qa-${suffix.replace(/[^a-z0-9]/gi, "").slice(-20).toLowerCase()}`;
  const modifierResult = await call("erp-save-product-modifier", {
    product_id: productId, modifier_group: "qa-e2e", modifier_code: modifierCode,
    name: "QA E2E modifier", price_delta_idr: 25, is_required: false, is_active: true,
  }, ownerToken);
  modifierId = modifierResult.modifier?.id;
  assert.ok(modifierId, "Owner must create an isolated QA modifier");
  modifierTouched = true;
  pass("Modifier option is created through the audited catalog mutation path");

  const shifts = await call("erp-list-shifts", { branch_id: branchId }, managerToken);
  let shift = (shifts.shifts || []).find((row) => row.status === "open" && row.opened_by === managerUserId);
  if (!shift) {
    const opened = await call("erp-open-shift", { branch_id: branchId, opening_cash_idr: 0 }, managerToken);
    shift = opened.shift;
    createdShiftId = shift.id;
  }
  assert.ok(shift?.id, "An open QA shift must be available to the configured staging branch manager");

  const operation = {
    type: "pos-sale",
    branch_id: branchId,
    shift_id: shift.id,
    items: [{ slug: productSlug, quantity: 1, modifiers: [{ code: modifierCode }] }],
    payment_method: "cash",
    customer_reference: `QA-${suffix}`,
    notes: note,
    discount_idr: 0,
  };
  const sale = await call("erp-create-pos-sale", {
    ...operation,
    idempotency_key: operationId,
  }, managerToken);
  const saleId = sale.sale_id || sale.result?.sale_id;
  assert.ok(saleId, "POS sale must return a sale ID");
  assert.equal(sale.payment_status || "paid", "paid");
  assert.equal(Number(sale.total_idr), 125, "modifier price delta must be included in the committed sale total");
  pass("POS sale commits with selected modifier and adjusted price", { sale_id: saleId, transaction_code: sale.transaction_code, total_idr: sale.total_idr });

  const directReplay = await call("erp-create-pos-sale", { ...operation, idempotency_key: operationId }, managerToken);
  assert.equal(directReplay.sale_id, saleId, "Same idempotency key must return the original sale");
  assert.equal(directReplay.idempotent_replay, true);
  await expectStatus("erp-create-pos-sale", {
    ...operation,
    items: [{ slug: productSlug, quantity: 2 }],
    idempotency_key: operationId,
  }, managerToken, 409);
  pass("POS idempotency replays exactly once and rejects changed payload");

  // Simulate a response lost after server commit: replay the exact operation through the offline sync API.
  const synced = await call("erp-sync-offline-operation", {
    device_id: deviceId,
    client_operation_id: operationId,
    operation,
  }, managerToken);
  assert.equal(synced.result?.sale_id, saleId, "Offline replay must return the same committed sale");
  const syncedReplay = await call("erp-sync-offline-operation", {
    device_id: deviceId,
    client_operation_id: operationId,
    operation,
  }, managerToken);
  assert.equal(syncedReplay.replayed, true, "Repeated offline replay must use the receipt");
  await expectStatus("erp-sync-offline-operation", {
    device_id: deviceId,
    client_operation_id: operationId,
    operation: { ...operation, notes: note + " changed" },
  }, managerToken, 409);
  pass("Offline recovery shares the POS idempotency key and deduplicates receipt replay");

  const ticketResponse = await call("erp-list-kitchen-tickets", { branch_id: branchId }, managerToken);
  const ticket = (ticketResponse.tickets || []).find((row) => row.pos_sale_id === saleId);
  assert.ok(ticket, "A paid POS sale must create exactly one KDS ticket");
  assert.equal((ticket.kitchen_ticket_items || []).length, 1, "KDS ticket must contain the committed sale line");
  assert.equal(ticket.kitchen_ticket_items[0].product_name_snapshot, "[TEST ONLY] Staging QA Fixture Product");
  assert.equal(ticket.kitchen_ticket_items[0].modifier_snapshot?.[0]?.code, modifierCode, "KDS ticket must preserve the selected modifier snapshot");
  const ticketCount = (ticketResponse.tickets || []).filter((row) => row.pos_sale_id === saleId).length;
  assert.equal(ticketCount, 1, "POS sale must create exactly one ticket");
  for (const status of ["accepted", "preparing", "ready", "served"]) {
    await call("erp-transition-kitchen-ticket", { ticket_id: ticket.id, status }, managerToken);
  }
  const afterKitchen = await call("erp-list-kitchen-tickets", { branch_id: branchId }, managerToken);
  const served = (afterKitchen.tickets || []).find((row) => row.id === ticket.id);
  assert.equal(served?.status, "served");
  assert.ok(Number(served.version) >= 5);
  pass("KDS ticket contains sale lines and transitions queued → accepted → preparing → ready → served", { ticket_id: ticket.id });

  const afterInventory = await call("erp-list-inventory", { branch_id: branchId }, managerToken);
  const afterFlour = balanceOf(afterInventory, flourId);
  const afterSecond = balanceOf(afterInventory, secondIngredientId);
  assert.equal(Number((beforeFlour - afterFlour).toFixed(3)), 50, "Recipe must consume 50g flour for one unit");
  assert.equal(Number((beforeSecond - afterSecond).toFixed(3)), 10, "Recipe must consume 10g second ingredient for one unit");
  pass("Recipe stock ledger deducts the exact recipe quantity once", {
    flour_before: beforeFlour, flour_after: afterFlour,
    second_ingredient_before: beforeSecond, second_ingredient_after: afterSecond,
  });

  // Keep the shift open through split-tender and held-order acceptance; finally closes only a shift created by this run.

  const sales = await call("erp-list-sales", { branch_id: branchId }, managerToken);
  assert.equal((sales.sales || []).filter((row) => row.id === saleId).length, 1, "Sales report must show exactly one sale");
  const reconciliation = await call("erp-reconcile-pos-sale", { branch_id: branchId, sale_id: saleId }, ownerToken);
  assert.equal(reconciliation.sale?.payment_status, "paid");
  assert.equal(reconciliation.kitchen_ticket?.id, ticket.id);
  assert.equal(reconciliation.kitchen_ticket?.status, "served");
  assert.equal((reconciliation.items || []).length, 1);
  assert.equal((reconciliation.stock_movements || []).length, 2);
  assert.ok((reconciliation.audit_events || []).some((event) => event.action === "pos_sale_created"));
  assert.ok((reconciliation.audit_events || []).some((event) => event.action === "kitchen_ticket_transition"));
  pass("POS report, KDS, stock movements, balances and audit reconcile", {
    sale_id: saleId,
    ticket_id: ticket.id,
    stock_movement_count: reconciliation.stock_movements.length,
    audit_actions: [...new Set((reconciliation.audit_events || []).map((event) => event.action))],
  });

  const receipt = await call("erp-get-pos-receipt", { branch_id: branchId, sale_id: saleId }, ownerToken);
  assert.equal(receipt.replayed, false, "first receipt retrieval must create a new immutable snapshot");
  assert.equal(receipt.snapshot.transaction_code, sale.transaction_code);
  assert.equal(receipt.snapshot.items[0].modifiers[0].code, modifierCode);
  const receiptReplay = await call("erp-get-pos-receipt", { branch_id: branchId, sale_id: saleId }, ownerToken);
  assert.equal(receiptReplay.receipt_id, receipt.receipt_id, "reprinting must reuse the immutable receipt snapshot");
  assert.equal(receiptReplay.replayed, true, "subsequent receipt retrieval must be marked as replay");
  pass("Digital receipt snapshot is immutable and repeat retrieval reuses the same receipt", { receipt_id: receipt.receipt_id });

  const held = await call("erp-hold-pos-order", {
    branch_id: branchId, shift_id: shift.id, hold_key: `hold-${suffix}`,
    payload: { items: [{ slug: productSlug, quantity: 1 }], payment_method: "cash", notes: note },
  }, ownerToken);
  assert.equal(held.status, "held");
  const resumed = await call("erp-resume-pos-order", { branch_id: branchId, hold_id: held.hold_id }, ownerToken);
  assert.equal(resumed.status, "resumed");
  assert.equal(resumed.payload.items[0].slug, productSlug);
  const resumedReplay = await call("erp-resume-pos-order", { branch_id: branchId, hold_id: held.hold_id }, ownerToken);
  assert.equal(resumedReplay.sale_idempotency_key, resumed.sale_idempotency_key);
  assert.equal(resumedReplay.idempotent_replay, true);
  pass("Held order resumes once and returns a stable sale idempotency key on retry", { hold_id: held.hold_id });

  const shiftBeforeSplit = (await call("erp-list-shifts", { branch_id: branchId }, ownerToken)).shifts.find((row) => row.id === shift.id);
  assert.ok(shiftBeforeSplit, "active shift must be visible before split tender");
  const cashBeforeSplit = Number(shiftBeforeSplit.expected_cash_idr);
  const splitKey = `split-${suffix}`;
  const split = await call("erp-create-pos-sale-split", {
    branch_id: branchId, shift_id: shift.id,
    items: [{ slug: productSlug, quantity: 1 }], discount_idr: 0,
    customer_reference: `QA-SPLIT-${suffix}`, notes: note,
    idempotency_key: splitKey,
    tenders: [
      { payment_method: "cash", amount_idr: 40, reference: `CASH-${suffix}` },
      { payment_method: "qris", amount_idr: 60, reference: `QRIS-${suffix}` },
    ],
  }, ownerToken);
  splitSaleId = split.sale_id;
  assert.ok(splitSaleId);
  assert.equal(split.payment_method, "split");
  assert.equal(Number(split.total_idr), 100);
  assert.equal(split.tenders.reduce((sum, tender) => sum + Number(tender.amount_idr), 0), 100);
  const splitReplay = await call("erp-create-pos-sale-split", {
    branch_id: branchId, shift_id: shift.id,
    items: [{ slug: productSlug, quantity: 1 }], discount_idr: 0,
    customer_reference: `QA-SPLIT-${suffix}`, notes: note,
    idempotency_key: splitKey,
    tenders: [
      { payment_method: "cash", amount_idr: 40, reference: `CASH-${suffix}` },
      { payment_method: "qris", amount_idr: 60, reference: `QRIS-${suffix}` },
    ],
  }, ownerToken);
  assert.equal(splitReplay.sale_id, splitSaleId);
  assert.equal(splitReplay.idempotent_replay, true);
  const shiftAfterSplit = (await call("erp-list-shifts", { branch_id: branchId }, ownerToken)).shifts.find((row) => row.id === shift.id);
  assert.equal(Number(shiftAfterSplit.expected_cash_idr) - cashBeforeSplit, 40, "cash drawer expectation must increase only by the cash tender allocation");
  await expectStatus("erp-create-pos-sale-split", {
    branch_id: branchId, shift_id: shift.id,
    items: [{ slug: productSlug, quantity: 1 }], discount_idr: 0,
    customer_reference: `QA-SPLIT-${suffix}`, notes: note,
    idempotency_key: splitKey,
    tenders: [
      { payment_method: "cash", amount_idr: 50, reference: `CASH-${suffix}` },
      { payment_method: "qris", amount_idr: 50, reference: `QRIS-${suffix}` },
    ],
  }, ownerToken, 409);
  const splitOfflineOperation = {
    type: "pos-sale", branch_id: branchId, shift_id: shift.id,
    items: [{ slug: productSlug, quantity: 1 }], payment_method: "split",
    discount_idr: 0, customer_reference: `QA-SPLIT-${suffix}`, notes: note,
    tenders: [
      { payment_method: "cash", amount_idr: 40, reference: `CASH-${suffix}` },
      { payment_method: "qris", amount_idr: 60, reference: `QRIS-${suffix}` },
    ],
  };
  const splitSynced = await call("erp-sync-offline-operation", {
    device_id: deviceId, client_operation_id: splitKey, operation: splitOfflineOperation,
  }, ownerToken);
  assert.equal(splitSynced.result?.sale_id, splitSaleId, "Offline split replay must return the original sale");
  const splitSyncedReplay = await call("erp-sync-offline-operation", {
    device_id: deviceId, client_operation_id: splitKey, operation: splitOfflineOperation,
  }, ownerToken);
  assert.equal(splitSyncedReplay.replayed, true, "Repeated split offline replay must use its receipt");
  await expectStatus("erp-sync-offline-operation", {
    device_id: deviceId, client_operation_id: splitKey,
    operation: { ...splitOfflineOperation, tenders: [
      { payment_method: "cash", amount_idr: 50, reference: `CASH-${suffix}` },
      { payment_method: "qris", amount_idr: 50, reference: `QRIS-${suffix}` },
    ] },
  }, ownerToken, 409);
  const splitReconciliation = await call("erp-reconcile-pos-sale", { branch_id: branchId, sale_id: splitSaleId }, ownerToken);
  assert.equal(splitReconciliation.sale?.payment_status, "paid");
  assert.equal(splitReconciliation.sale?.payment_method, "split");
  assert.equal(splitReconciliation.payment_reconciliation.status, "RECONCILED");
  assert.equal(splitReconciliation.payment_reconciliation.expected_total_idr, 100);
  assert.equal(splitReconciliation.payment_reconciliation.allocated_total_idr, 100);
  assert.equal(splitReconciliation.payment_reconciliation.cash_tender_idr, 40);
  assert.equal(splitReconciliation.payment_reconciliation.noncash_tender_idr, 60);
  assert.deepEqual([...splitReconciliation.payment_reconciliation.distinct_methods].sort(), ["cash", "qris"]);
  assert.equal((splitReconciliation.tender_allocations || []).length, 2);
  assert.equal((splitReconciliation.items || []).length, 1);
  assert.ok(splitReconciliation.kitchen_ticket?.id, "split POS sale must create a KDS ticket");
  assert.equal((splitReconciliation.kitchen_ticket?.kitchen_ticket_items || []).length, 1);
  assert.equal((splitReconciliation.stock_movements || []).length, 2, "split sale must create recipe stock movements");
  assert.ok((splitReconciliation.audit_events || []).some((event) => event.action === "pos_sale_created"), "split sale must have an audit event");
  const splitStock = { balances: splitReconciliation.stock_balances || [] };
  assert.equal(Number((afterFlour - balanceOf(splitStock, flourId)).toFixed(3)), 50, "split sale must consume 50g flour");
  assert.equal(Number((afterSecond - balanceOf(splitStock, secondIngredientId)).toFixed(3)), 10, "split sale must consume 10g second ingredient");
  const splitReceipt = await call("erp-get-pos-receipt", { branch_id: branchId, sale_id: splitSaleId }, ownerToken);
  assert.equal(splitReceipt.replayed, false, "first split receipt retrieval must persist the immutable snapshot");
  assert.equal(splitReceipt.snapshot.payment_method, "split");
  assert.equal(splitReceipt.snapshot.tenders.length, 2);
  const splitReceiptReplay = await call("erp-get-pos-receipt", { branch_id: branchId, sale_id: splitSaleId }, ownerToken);
  assert.equal(splitReceiptReplay.receipt_id, splitReceipt.receipt_id);
  assert.equal(splitReceiptReplay.replayed, true);
  pass("Split tender exact-sum, cash/noncash reconciliation, direct/offline idempotency and receipt pass", { sale_id: splitSaleId, receipt_id: splitReceipt.receipt_id });

  evidence.status = "PASS";
  evidence.sale_id = saleId;
  evidence.transaction_code = sale.transaction_code;
  evidence.ticket_id = ticket.id;
  evidence.split_sale_id = splitSaleId;
  evidence.receipt_id = receipt.receipt_id;
  evidence.hold_id = held.hold_id;
  evidence.stock_before = { flour_g: beforeFlour, second_ingredient_g: beforeSecond };
  evidence.stock_after_sale = { flour_g: afterFlour, second_ingredient_g: afterSecond };
}

try {
  await main();
} catch (error) {
  const blocked = String(error?.message || "").startsWith("STAGING_AUTH_BLOCKED:");
  evidence.status = blocked ? "BLOCKED" : "FAIL";
  evidence.error = blocked ? String(error.message) : String(error?.stack || error);
  console.error(blocked ? error.message : error);
  process.exitCode = 1;
} finally {
  await closeCreatedShift();
  await restoreQaProduct();
  if (ownerToken) {
    try {
      const revoked = await revokeLocalSession({
        baseUrl: base,
        publicKey: anon,
        accessToken: ownerToken,
      });
      if (!revoked) evidence.cleanup_errors.push("Owner temporary session revocation was not confirmed");
    } catch {
      evidence.cleanup_errors.push("Owner temporary session revocation failed");
    }
  }
  if (evidence.cleanup_errors.length) {
    evidence.status = "FAIL";
    evidence.error = [evidence.error, "QA fixture cleanup failed; inspect cleanup_errors before rerun."]
      .filter(Boolean).join(" ");
    process.exitCode = 1;
  }
  await mkdir("artifacts", { recursive: true });
  await writeFile("artifacts/kds-pos-stock-reconciliation.json", JSON.stringify(evidence, null, 2) + "\n");
  console.log(`E2E evidence status: ${evidence.status}`);
}