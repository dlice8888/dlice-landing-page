#!/usr/bin/env node
/**
 * Read-only / negative acceptance probes for the next FnB OS workflows.
 * Targets only the known D'Lice staging project. Never creates or transitions
 * business records; mutation probes use impossible IDs and invalid payloads.
 *
 * Required environment:
 *   STAGING_SUPABASE_URL, STAGING_SUPABASE_PUBLIC_KEY, STAGING_EDGE_FUNCTION_URL
 *   STAGING_TEST_OWNER_USERNAME, STAGING_TEST_OWNER_PASSWORD
 *   STAGING_TEST_BRANCH_A_USERNAME, STAGING_TEST_BRANCH_A_PASSWORD
 *   STAGING_TEST_NO_PERMISSION_USERNAME, STAGING_TEST_NO_PERMISSION_PASSWORD
 *   STAGING_TEST_INACTIVE_USERNAME, STAGING_TEST_INACTIVE_PASSWORD
 *   TEST_BRANCH_B_ID (staging-only UUID)
 */
import assert from "node:assert/strict";

const required = [
  "STAGING_SUPABASE_URL", "STAGING_SUPABASE_PUBLIC_KEY", "STAGING_EDGE_FUNCTION_URL",
  "STAGING_TEST_OWNER_USERNAME", "STAGING_TEST_OWNER_PASSWORD",
  "STAGING_TEST_BRANCH_A_USERNAME", "STAGING_TEST_BRANCH_A_PASSWORD",
  "STAGING_TEST_NO_PERMISSION_USERNAME", "STAGING_TEST_NO_PERMISSION_PASSWORD",
  "STAGING_TEST_INACTIVE_USERNAME", "STAGING_TEST_INACTIVE_PASSWORD", "TEST_BRANCH_B_ID",
];
const missing = required.filter((key) => !process.env[key]);
if (missing.length) {
  console.error("BLOCKED: missing required staging workflow test variables:", missing.join(", "));
  process.exit(2);
}

const base = process.env.STAGING_SUPABASE_URL.replace(/\/$/, "");
const edge = new URL(process.env.STAGING_EDGE_FUNCTION_URL);
const expected = "https://higoadrzxnhzbbwhdbmh.supabase.co";
if (base !== expected || edge.origin !== expected || edge.pathname !== "/functions/v1/dlice-orders") {
  console.error("REFUSED: workflow acceptance probes may target only the known D'Lice staging project.");
  process.exit(2);
}
const anon = process.env.STAGING_SUPABASE_PUBLIC_KEY;
const branchB = process.env.TEST_BRANCH_B_ID;
const impossibleId = "00000000-0000-0000-0000-000000000000";
const results = [];

async function tokenFor(username, password, label) {
  const response = await fetch(`${base}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anon, "content-type": "application/json" },
    body: JSON.stringify({ email: `${username.toLowerCase()}@accounts.dlice.internal`, password }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || typeof body.access_token !== "string") {
    throw new Error(`Could not obtain short-lived staging token for ${label}; HTTP ${response.status}.`);
  }
  return body.access_token;
}
async function call(action, payload = {}, token = null) {
  const response = await fetch(edge, {
    method: "POST",
    headers: {
      apikey: anon,
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ action, ...payload }),
  });
  const body = await response.json().catch(() => ({}));
  return { status: response.status, body };
}
async function check(id, expectedStatus, action, payload, token) {
  const result = await call(action, payload, token);
  const ok = result.status === expectedStatus;
  results.push({ id, status: ok ? "PASS" : "FAIL", actual: result.status, expected: expectedStatus });
  console.log(`${ok ? "PASS" : "FAIL"} ${id}: HTTP ${result.status}; expected ${expectedStatus}`);
  assert.equal(result.status, expectedStatus, `${id}: unexpected HTTP status`);
  return result;
}

try {
  const [owner, staff, noPermission, inactive] = await Promise.all([
    tokenFor(process.env.STAGING_TEST_OWNER_USERNAME, process.env.STAGING_TEST_OWNER_PASSWORD, "Owner"),
    tokenFor(process.env.STAGING_TEST_BRANCH_A_USERNAME, process.env.STAGING_TEST_BRANCH_A_PASSWORD, "branch manager"),
    tokenFor(process.env.STAGING_TEST_NO_PERMISSION_USERNAME, process.env.STAGING_TEST_NO_PERMISSION_PASSWORD, "no-permission staff"),
    tokenFor(process.env.STAGING_TEST_INACTIVE_USERNAME, process.env.STAGING_TEST_INACTIVE_PASSWORD, "inactive staff"),
  ]);

  // Purchase-to-pay: list access, branch scope, inactive/least-privilege denial.
  const poList = await check("P1-P2P-OWNER-LIST", 200, "erp-list-purchase-orders", {}, owner);
  assert.ok(Array.isArray(poList.body.purchase_orders), "Owner PO list response must include purchase_orders");
  await check("P1-P2P-BRANCH-A-LIST", 200, "erp-list-purchase-orders", {}, staff);
  await check("P1-P2P-CROSS-BRANCH-DENIED", 403, "erp-list-purchase-orders", { branch_id: branchB }, staff);
  await check("P1-P2P-NO-PERMISSION-DENIED", 403, "erp-list-purchase-orders", {}, noPermission);
  await check("P1-P2P-INACTIVE-DENIED", 401, "erp-list-purchase-orders", {}, inactive);

  // Order-to-fulfillment: authorized list and cross-branch read isolation.
  const fulfillment = await check("P1-O2C-OWNER-FULFILLMENT-LIST", 200, "erp-list-fulfillment-orders", {}, owner);
  assert.ok(Array.isArray(fulfillment.body.orders), "Fulfillment list response must include orders");
  await check("P1-O2C-BRANCH-A-LIST", 200, "erp-list-fulfillment-orders", {}, staff);
  await check("P1-O2C-CROSS-BRANCH-DENIED", 403, "erp-list-fulfillment-orders", { branch_id: branchB }, staff);
  await check("P1-O2C-NO-PERMISSION-DENIED", 403, "erp-list-fulfillment-orders", {}, noPermission);
  await check("P1-O2C-INACTIVE-DENIED", 401, "erp-list-fulfillment-orders", {}, inactive);

  // Finance: HQ-only settlement list, branch-scoped cash reconciliation, and SoD.
  const settlements = await check("P2-FINANCE-OWNER-SETTLEMENT-LIST", 200, "erp-list-settlements", {}, owner);
  assert.ok(Array.isArray(settlements.body.settlements), "Settlement list response must include settlements");
  await check("P2-FINANCE-BRANCH-CANNOT-CREATE-SETTLEMENT", 403, "erp-create-settlement", {
    settlement_code: "INVALID-ACCEPTANCE-PROBE", payment_method: "qris",
    settlement_date: new Date().toISOString().slice(0, 10), gross_amount_idr: 0, fee_amount_idr: 0,
  }, staff);
  await check("P2-FINANCE-NO-PERMISSION-DENIED", 403, "erp-list-settlements", {}, noPermission);
  await check("P2-FINANCE-INACTIVE-DENIED", 401, "erp-list-settlements", {}, inactive);
  await check("P2-CASH-RECON-CROSS-BRANCH-DENIED", 403, "erp-create-cash-reconciliation", {
    branch_id: branchB, business_date: new Date().toISOString().slice(0, 10),
    cash_expected_idr: 0, cash_counted_idr: 0, bank_expected_idr: 0,
    bank_received_idr: 0, qris_expected_idr: 0, qris_received_idr: 0,
  }, staff);
  await check("P2-CASH-RECON-NO-PERMISSION-DENIED", 403, "erp-create-cash-reconciliation", {
    branch_id: branchB, business_date: new Date().toISOString().slice(0, 10),
    cash_expected_idr: 0, cash_counted_idr: 0, bank_expected_idr: 0,
    bank_received_idr: 0, qris_expected_idr: 0, qris_received_idr: 0,
  }, noPermission);

  // Negative mutation probes use impossible IDs, so they cannot alter business rows.
  await check("P1-P2P-RECEIVE-UNKNOWN-PO-NOOP", 404, "erp-receive-purchase-order", {
    purchase_order_id: impossibleId, receipt_number: "NOOP-ACCEPTANCE", items: [],
  }, staff);
  await check("P1-O2C-UPDATE-UNKNOWN-ORDER-NOOP", 404, "erp-update-fulfillment", {
    order_id: impossibleId, fulfillment_status: "accepted", notes: "negative acceptance probe",
  }, staff);
  await check("P1-STOCK-TRANSITION-UNKNOWN-TRANSFER-NOOP", 404, "erp-transition-stock-transfer", {
    transfer_id: impossibleId, transition: "approve",
  }, owner);
  await check("P1-STOCK-POST-UNKNOWN-COUNT-NOOP", 404, "erp-post-stock-count", {
    count_id: impossibleId,
  }, staff);
  await check("P2-FINANCE-REVIEW-UNKNOWN-RECON-NOOP", 404, "erp-review-cash-reconciliation", {
    id: impossibleId, status: "approved",
  }, owner);

  const failed = results.filter((item) => item.status !== "PASS");
  console.log(`SUMMARY: ${results.length - failed.length} PASS, ${failed.length} FAIL; read-only and impossible-ID negative probes only.`);
  if (failed.length) process.exitCode = 1;
} catch (error) {
  console.error("BLOCKED/FAIL:", error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
