import assert from "node:assert/strict";

const base = (process.env.STAGING_SUPABASE_URL || "").replace(/\/$/, "");
const apiKey = process.env.STAGING_SUPABASE_PUBLIC_KEY || "";
assert.equal(base, "https://higoadrzxnhzbbwhdbmh.supabase.co", "Refusing to target anything except the fixed staging project");
assert.ok(apiKey.startsWith("sb_publishable_") || apiKey.startsWith("eyJ"), "Missing public/anon API key");

const tables = [
  "backup_restore_runs", "branch_settings", "integration_connections", "integration_outbox",
  "inventory_waste_events", "kitchen_ticket_items", "kitchen_tickets", "offline_sync_receipts",
  "order_stock_consumptions", "pos_idempotency_requests", "product_modifiers",
  "recipe_substitutions", "shift_handover_records", "tenant_invites", "tenant_memberships",
  "tenants", "warehouses",
];
const zero = "00000000-0000-0000-0000-000000000000";
const failures = [];
let passed = 0;

async function probe(table, method) {
  const query = method === "GET" ? "?select=id&limit=1"
    : method === "PATCH" || method === "DELETE" ? "?id=eq." + zero : "";
  const url = base + "/rest/v1/" + table + query;
  const init = {
    method,
    headers: { apikey: apiKey, "content-type": "application/json", prefer: "return=minimal" },
  };
  if (method === "POST") init.body = JSON.stringify({});
  if (method === "PATCH") init.body = JSON.stringify({ id: zero });
  const response = await fetch(url, init);
  const text = await response.text();
  let body = {};
  try { body = JSON.parse(text); } catch {}
  const denied = [401, 403].includes(response.status) && String(body.code || "") === "42501";
  const result = { table, method, status: response.status, code: body.code || null, denied };
  console.log(JSON.stringify(result));
  if (!denied) failures.push({ ...result, detail: String(body.message || text).slice(0, 160) });
  else passed++;
}

for (const table of tables) {
  for (const method of ["GET", "POST", "PATCH", "DELETE"]) {
    try { await probe(table, method); }
    catch (error) { failures.push({ table, method, error: String(error) }); }
  }
}

console.log(JSON.stringify({ summary: "staging-direct-client-denial", passed, expected: tables.length * 4, failures: failures.length }));
assert.equal(failures.length, 0, "Some direct-client operations were not denied at the database privilege layer");
