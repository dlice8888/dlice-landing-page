#!/usr/bin/env node
/**
 * Manual positive-path staging E2E for POS -> payment -> KDS -> recipe stock -> report.
 * Uses only the fixed QA-DLICE-A branch and inactive QA fixture product. The product is
 * activated only for the duration of this test and is restored to inactive in finally.
 */
import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";

const required = [
  "STAGING_SUPABASE_URL",
  "STAGING_SUPABASE_PUBLIC_KEY",
  "STAGING_EDGE_FUNCTION_URL",
  "STAGING_TEST_OWNER_USERNAME",
  "STAGING_TEST_OWNER_PASSWORD",
  "STAGING_TEST_BRANCH_A_USERNAME",
  "STAGING_TEST_BRANCH_A_PASSWORD",
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
let recipeWasDraft = false;

async function tokenFor(username, password, label) {
  const response = await fetch(`${base}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anon, "content-type": "application/json" },
    body: JSON.stringify({ email: `${username.toLowerCase()}@accounts.dlice.internal`, password }),
  });
  const body = await response.json().catch(() => ({}));
  assert.equal(response.status, 200, `${label} QA token must be issued by staging Auth`);
  assert.equal(typeof body.access_token, "string", `${label} token must be present`);
  return body.access_token;
}

async function userId(token) {
  const response = await fetch(`${base}/auth/v1/user`, {
    headers: { apikey: anon, authorization: `Bearer ${token}` },
  });
  const body = await response.json().catch(() => ({}));
  assert.equal(response.status, 200, "Staging Auth user lookup must succeed");
  assert.equal(typeof body.id, "string", "Authenticated user ID must be present");
  return body.id;
}

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


async function ensureChecklist(checklistType) {
  const listed = await call("erp-list-branch-checklists", { branch_id: branchId }, managerToken);
  let run = (listed.runs || []).find((row) => row.checklist_type === checklistType);
  if (!run) {
    const started = await call("erp-start-branch-checklist", { branch_id: branchId, checklist_type: checklistType }, managerToken);
    run = started.run;
  }
  assert.ok(run?.id, `${checklistType} checklist must exist`);
  if (run.status !== "completed") {
    for (const item of (run.items || [])) {
      if (item.status !== "passed") {
        await call("erp-update-branch-checklist-item", {
          run_id: run.id,
          item_key: item.key,
          item_status: "passed",
          notes: `AUTOMATED QA E2E checklist ${checklistType}; ${suffix}`,
        }, managerToken);
      }
    }
    const completed = await call("erp-complete-branch-checklist", { run_id: run.id }, managerToken);
    const latest = completed.run || completed;
    assert.equal(latest.status || completed.status, "completed", `${checklistType} checklist must complete with all critical checks passed`);
  }
  pass(`Branch ${checklistType} checklist completes with critical checks passed`, { checklist_id: run.id });
}

async function restoreQaProduct() {
  if (!ownerToken) return;
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

async function retireQaRecipe() {
  if (!ownerToken || !recipeWasDraft) return;
  try {
    const result = await call("erp-retire-recipe", { recipe_id: recipeId }, ownerToken);
    assert.ok(["draft", "retired"].includes(result.status), "QA recipe must be restored to draft or retired");
    pass("QA recipe activation is reverted after product cleanup", { recipe_status: result.status });
  } catch (error) {
    evidence.cleanup_errors.push(`QA recipe retirement: ${error.message}`);
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
  ownerToken = await tokenFor(process.env.STAGING_TEST_OWNER_USERNAME, process.env.STAGING_TEST_OWNER_PASSWORD, "Owner");
  managerToken = await tokenFor(process.env.STAGING_TEST_BRANCH_A_USERNAME, process.env.STAGING_TEST_BRANCH_A_PASSWORD, "Branch A manager");
  managerUserId = await userId(managerToken);
  ownerUserId = await userId(ownerToken);

  // Preflight fixture identity and state before any write; refuse to mutate a product that is already active.
  const catalog = await call("admin-list-products", {}, ownerToken);
  const fixtureProduct = (catalog.products || []).find((row) => row.id === productId);
  assert.ok(fixtureProduct, "Fixed QA product must exist in the staging catalog");
  assert.equal(fixtureProduct.slug, productSlug, "QA product ID must still map to the expected QA-only slug");
  assert.equal(fixtureProduct.is_active, false, "Refuse to run if the QA fixture product is already active");

  // Safe negative runtime checks: malformed payloads ensure a broken gate cannot create data.
  await expectStatus("erp-create-tenant", { slug: "x", legal_name: "QA" }, ownerToken, 423);
  await expectStatus("erp-invite-tenant-member", {
    tenant_id: "00000000-0000-4000-8000-000000000001",
    email: "not-an-email",
    role: "viewer",
  }, ownerToken, 423);
  pass("Tenant creation and invitation fail closed until cross-tenant isolation is accepted");

  await ensureChecklist("opening");

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
  recipeWasDraft = recipe.status === "draft";
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

  const shifts = await call("erp-list-shifts", { branch_id: branchId }, managerToken);
  let shift = (shifts.shifts || []).find((row) => row.status === "open" && row.opened_by === managerUserId);
  if (!shift) {
    const opened = await call("erp-open-shift", { branch_id: branchId, opening_cash_idr: 0 }, managerToken);
    shift = opened.shift;
    createdShiftId = shift.id;
  }
  assert.ok(shift?.id, "An open QA shift must be available to the Branch A manager");

  const operation = {
    type: "pos-sale",
    branch_id: branchId,
    shift_id: shift.id,
    items: [{ slug: productSlug, quantity: 1 }],
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
  pass("POS sale commits with paid status", { sale_id: saleId, transaction_code: sale.transaction_code });

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

  const wasteKey = `qa-waste-${suffix}`;
  const wastePayload = { branch_id: branchId, inventory_item_id: flourId, quantity: 1, reason_code: "other", reason: note, idempotency_key: wasteKey };
  const waste = await call("erp-record-waste", wastePayload, ownerToken);
  assert.ok(waste.waste_id, "Waste event must be recorded");
  const wasteReplay = await call("erp-record-waste", wastePayload, ownerToken);
  assert.equal(wasteReplay.waste_id, waste.waste_id);
  assert.equal(wasteReplay.replayed, true);
  await expectStatus("erp-record-waste", { ...wastePayload, quantity: 2 }, ownerToken, 409);
  const wasteLedger = await call("erp-list-waste-events", { branch_id: branchId }, ownerToken);
  assert.ok((wasteLedger.events || []).some((event) => event.id === waste.waste_id && Number(event.quantity) === 1));
  assert.ok((wasteLedger.stock_movements || []).some((movement) => movement.reference_id === waste.waste_id && movement.movement_type === "waste" && Number(movement.quantity) === 1));
  assert.ok((wasteLedger.audit_events || []).some((event) => event.entity_id === waste.waste_id && event.action === "inventory_waste_posted"));
  const afterWasteInventory = await call("erp-list-inventory", { branch_id: branchId }, managerToken);
  assert.equal(Number((afterFlour - balanceOf(afterWasteInventory, flourId)).toFixed(3)), 1, "Waste must deduct exactly one additional gram");
  assert.equal(Number((afterSecond - balanceOf(afterWasteInventory, secondIngredientId)).toFixed(3)), 0, "Waste must not alter the unrelated ingredient");
  pass("Waste ledger is idempotent and decrements the matching stock only", { waste_id: waste.waste_id });

  const currentShifts = await call("erp-list-shifts", { branch_id: branchId }, managerToken);
  const currentShift = (currentShifts.shifts || []).find((row) => row.id === shift.id);
  const handovers = await call("erp-list-shift-handovers", { branch_id: branchId }, managerToken);
  let handover = (handovers.handovers || []).find((row) => row.shift_id === shift.id);
  if (!handover) {
    const created = await call("erp-create-shift-handover", {
      shift_id: shift.id,
      incoming_user_id: ownerUserId,
      cash_counted_idr: Math.max(0, Math.round(Number(currentShift?.expected_cash_idr || 0))),
      pending_orders: [],
      waste_summary: [{ waste_id: waste.waste_id, inventory_item_id: flourId, quantity: 1, reason_code: "other" }],
      open_issues: "",
      notes: `AUTOMATED QA E2E handover; ${suffix}`,
    }, managerToken);
    handover = created.handover;
  }
  assert.ok(handover?.id, "Shift handover must exist");
  if (handover.status === "submitted") {
    const ack = await call("erp-acknowledge-shift-handover", { handover_id: handover.id, decision: "acknowledged" }, ownerToken);
    handover = ack.handover;
  }
  assert.equal(handover.status, "acknowledged", "Incoming user must acknowledge the shift handover");
  assert.notEqual(handover.outgoing_user_id, handover.incoming_user_id);
  pass("Shift handover is acknowledged by a different user", { handover_id: handover.id });
  await closeCreatedShift();
  await ensureChecklist("closing");

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

  evidence.status = "PASS";
  evidence.sale_id = saleId;
  evidence.transaction_code = sale.transaction_code;
  evidence.ticket_id = ticket.id;
  evidence.waste_id = waste.waste_id;
  evidence.handover_id = handover.id;
  evidence.stock_before = { flour_g: beforeFlour, second_ingredient_g: beforeSecond };
  evidence.stock_after_sale = { flour_g: afterFlour, second_ingredient_g: afterSecond };
  evidence.stock_after_waste = { flour_g: balanceOf(afterWasteInventory, flourId), second_ingredient_g: balanceOf(afterWasteInventory, secondIngredientId) };
}

try {
  await main();
} catch (error) {
  evidence.status = "FAIL";
  evidence.error = String(error?.stack || error);
  console.error(error);
  process.exitCode = 1;
} finally {
  await closeCreatedShift();
  await restoreQaProduct();
  await retireQaRecipe();
  if (evidence.cleanup_errors.length) {
    evidence.status = evidence.status === "PASS" ? "PASS_WITH_CLEANUP_WARNING" : evidence.status;
  }
  await mkdir("artifacts", { recursive: true });
  await writeFile("artifacts/kds-pos-stock-reconciliation.json", JSON.stringify(evidence, null, 2));
  console.log(`E2E evidence status: ${evidence.status}`);
}
