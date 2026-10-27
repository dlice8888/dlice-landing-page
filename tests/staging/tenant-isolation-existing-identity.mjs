import assert from "node:assert/strict";

const base = (process.env.STAGING_SUPABASE_URL || "").replace(/\/$/, "");
const edge = process.env.STAGING_EDGE_FUNCTION_URL || "";
const key = process.env.STAGING_SUPABASE_PUBLIC_KEY || "";
const username = process.env.STAGING_TEST_BRANCH_A_USERNAME || "";
const password = process.env.STAGING_TEST_BRANCH_A_PASSWORD || "";
assert.equal(base, "https://higoadrzxnhzbbwhdbmh.supabase.co", "Refusing non-staging target");
assert.equal(edge, base + "/functions/v1/dlice-orders", "Refusing non-staging Edge Function");
if (!username || !password) {
  console.error("BLOCKED: existing branch-scoped staging identity credentials are not configured; no account was created.");
  process.exit(2);
}
const branchA = "90000000-0000-4000-8000-000000000001";
const branchB = "d8672046-7029-489b-9223-df07007cdc69";
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
