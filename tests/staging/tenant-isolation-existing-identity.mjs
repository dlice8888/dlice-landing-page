import assert from "node:assert/strict";

const base = (process.env.STAGING_SUPABASE_URL || "").replace(/\/$/, "");
const edge = process.env.STAGING_EDGE_FUNCTION_URL || "";
const key = process.env.STAGING_SUPABASE_PUBLIC_KEY || "";
const username = process.env.STAGING_TENANT_A_USERNAME || "";
const password = process.env.STAGING_TENANT_A_PASSWORD || "";
const branchB = process.env.STAGING_TENANT_B_BRANCH_ID || "";
assert.equal(base, "https://higoadrzxnhzbbwhdbmh.supabase.co", "Refusing non-staging target");
assert.equal(edge, base + "/functions/v1/dlice-orders", "Refusing non-staging Edge Function");
if (!key || !username || !password || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(branchB)) {
  console.error("BLOCKED: staging public key, canonical Tenant A credentials, or Tenant B branch fixture are not configured; no account was created.");
  process.exit(2);
}
const zero = "00000000-0000-0000-0000-000000000000";
const email = username.trim().toLowerCase().includes("@")
  ? username.trim().toLowerCase()
  : username.trim().toLowerCase() + "@accounts.dlice.internal";

const login = await fetch(base + "/auth/v1/token?grant_type=password", {
  method: "POST",
  headers: { apikey: key, "content-type": "application/json" },
  body: JSON.stringify({ email, password }),
});
const session = await login.json().catch(() => ({}));
if (!login.ok || typeof session.access_token !== "string") {
  console.error(JSON.stringify({ status: "BLOCKED", stage: "login", http: login.status, code: session.error_code || session.code || session.error || "auth_error", note: "Existing account login failed; no user was created." }));
  process.exit(2);
}

async function expectDenied(label, action, payload) {
  const response = await fetch(edge, {
    method: "POST",
    headers: { apikey: key, authorization: "Bearer " + session.access_token, "content-type": "application/json" },
    body: JSON.stringify({ action, ...payload }),
  });
  const body = await response.json().catch(() => ({}));
  const passed = response.status === 403;
  console.log(JSON.stringify({ test: label, status: response.status, expected: 403, passed, error: body.error || null }));
  assert.equal(response.status, 403, label + " must be rejected before business mutation");
}

await expectDenied("authenticated-wrong-branch-read", "erp-list-inventory", { branch_id: branchB });
await expectDenied("authenticated-wrong-branch-write", "erp-save-branch-capacity", {
  branch_id: branchB,
  product_id: zero,
  service_date: "2026-10-27",
  capacity: 0,
});
await expectDenied("authenticated-without-finance-hq-permission", "erp-list-settlements", {});
console.log(JSON.stringify({ status: "PASS", tests: 3, accounts_created: 0, business_records_created: 0 }));
