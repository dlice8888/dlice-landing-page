#!/usr/bin/env node
/**
 * D'Lice staging-only P0 HTTP smoke tests.
 *
 * Never point this script at production. It intentionally does not use service-role
 * credentials and does not submit successful business mutations. For write probes,
 * it targets an impossible UUID and sends invalid/empty payloads to avoid changing
 * rows even if a grant is accidentally present.
 *
 * Required:
 *   SUPABASE_URL=https://<staging-ref>.supabase.co
 *   SUPABASE_ANON_KEY=<staging anon/publishable key>
 *   STAGING_EDGE_FUNCTION_URL=https://<staging-ref>.supabase.co/functions/v1/dlice-orders
 *   ALLOWED_PREVIEW_ORIGIN=https://<current-preview-host>
 *   DISALLOWED_ORIGIN=https://dlice-p0-negative.invalid
 *
 * Optional disposable identity tokens:
 *   TEST_STAFF_JWT=<staging-only staff access token>
 *   TEST_OWNER_JWT=<staging-only owner access token>
 *   TEST_BRANCH_A_ID=<staging fixture UUID>
 *   TEST_BRANCH_B_ID=<staging fixture UUID>
 *
 * Run: node tests/staging/p0-http-smoke.mjs
 */
import assert from "node:assert/strict";

const required = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "STAGING_EDGE_FUNCTION_URL", "ALLOWED_PREVIEW_ORIGIN", "DISALLOWED_ORIGIN"];
const missing = required.filter((name) => !process.env[name]);
if (missing.length) {
  console.error("BLOCKED: missing environment variables:", missing.join(", "));
  process.exit(2);
}

const env = process.env;
const supabaseUrl = env.SUPABASE_URL.replace(/\/$/, "");
const edgeUrl = env.STAGING_EDGE_FUNCTION_URL;
const anonKey = env.SUPABASE_ANON_KEY;
const badUuid = "00000000-0000-0000-0000-000000000000";
const results = [];

function record(id, ok, detail) {
  results.push({ id, status: ok ? "PASS" : "FAIL", detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${id}: ${detail}`);
}
async function request(id, url, options = {}) {
  try {
    const response = await fetch(url, { redirect: "manual", ...options });
    const body = await response.text();
    return { response, body, headers: response.headers };
  } catch (error) {
    record(id, false, `network error: ${error instanceof Error ? error.message : String(error)}`);
    return null;
  }
}
function exactCors(response, origin) {
  return response.headers.get("access-control-allow-origin") === origin;
}
function corsNotWildcard(response) {
  return response.headers.get("access-control-allow-origin") !== "*";
}

const allowed = env.ALLOWED_PREVIEW_ORIGIN;
const denied = env.DISALLOWED_ORIGIN;
const preflightHeaders = {
  origin: allowed,
  "access-control-request-method": "POST",
  "access-control-request-headers": "authorization, apikey, content-type",
};
const allowedOptions = await request("P0-CORS-01", edgeUrl, { method: "OPTIONS", headers: preflightHeaders });
if (allowedOptions) {
  const ok = allowedOptions.response.status >= 200 && allowedOptions.response.status < 300 &&
    exactCors(allowedOptions.response, allowed) && corsNotWildcard(allowedOptions.response);
  record("P0-CORS-01", ok, `OPTIONS status=${allowedOptions.response.status}, ACAO=${allowedOptions.headers.get("access-control-allow-origin")}`);
}

const noAuthPost = await request("P0-AUTH-01", edgeUrl, {
  method: "POST",
  headers: { origin: allowed, apikey: anonKey, "content-type": "application/json" },
  body: JSON.stringify({ action: "erp-list-orders" }),
});
if (noAuthPost) {
  const ok = noAuthPost.response.status === 401 && exactCors(noAuthPost.response, allowed) && corsNotWildcard(noAuthPost.response);
  record("P0-AUTH-01", ok, `POST without bearer status=${noAuthPost.response.status}, ACAO=${noAuthPost.headers.get("access-control-allow-origin")}`);
}

const deniedOptions = await request("P0-CORS-02", edgeUrl, {
  method: "OPTIONS",
  headers: { ...preflightHeaders, origin: denied },
});
if (deniedOptions) {
  const ok = deniedOptions.response.status === 403 &&
    !exactCors(deniedOptions.response, denied) && corsNotWildcard(deniedOptions.response);
  record("P0-CORS-02", ok, `unlisted OPTIONS status=${deniedOptions.response.status}, ACAO=${deniedOptions.headers.get("access-control-allow-origin")}`);
}

const deniedPost = await request("P0-CORS-03", edgeUrl, {
  method: "POST",
  headers: { origin: denied, apikey: anonKey, "content-type": "application/json" },
  body: JSON.stringify({ action: "erp-list-orders" }),
});
if (deniedPost) {
  const ok = deniedPost.response.status === 403 &&
    !exactCors(deniedPost.response, denied) && corsNotWildcard(deniedPost.response);
  record("P0-CORS-03", ok, `unlisted POST status=${deniedPost.response.status}, ACAO=${deniedPost.headers.get("access-control-allow-origin")}`);
}

// Check direct Data API reads and harmless no-row/invalid writes using only the public key.
for (const table of ["orders", "order_items", "payment_records", "pos_sales", "inventory_items", "purchase_orders", "journal_entries"]) {
  const headers = { apikey: anonKey, authorization: `Bearer ${anonKey}`, "content-type": "application/json" };
  const read = await request(`P0-RLS-READ-${table}`, `${supabaseUrl}/rest/v1/${table}?select=*&limit=1`, { headers });
  if (read) {
    const ok = [401, 403].includes(read.response.status);
    record(`P0-RLS-READ-${table}`, ok, `GET status=${read.response.status}; direct read must be denied`);
  }
  const noRowUpdate = await request(`P0-RLS-UPDATE-${table}`, `${supabaseUrl}/rest/v1/${table}?id=eq.${badUuid}`, {
    method: "PATCH",
    headers: { ...headers, prefer: "return=minimal" },
    body: JSON.stringify({ updated_at: "2000-01-01T00:00:00Z" }),
  });
  if (noRowUpdate) {
    const ok = [401, 403].includes(noRowUpdate.response.status);
    record(`P0-RLS-UPDATE-${table}`, ok, `PATCH impossible UUID status=${noRowUpdate.response.status}; expected permission denial`);
  }
}

// A disposable staff JWT is optional at this stage. This proves valid-token processing,
// but does not by itself prove branch isolation; branch IDs are required for that.
if (env.TEST_STAFF_JWT) {
  const staff = await request("P0-AUTH-STAFF", edgeUrl, {
    method: "POST",
    headers: { origin: allowed, apikey: anonKey, authorization: `Bearer ${env.TEST_STAFF_JWT}`, "content-type": "application/json" },
    body: JSON.stringify({ action: "erp-list-orders" }),
  });
  if (staff) {
    const ok = [200, 403].includes(staff.response.status);
    record("P0-AUTH-STAFF", ok, `staff token request status=${staff.response.status}; capture body for expected permission scope`);
  }
} else {
  console.log("BLOCKED P0-AUTH-STAFF: TEST_STAFF_JWT not supplied");
}

if (env.TEST_STAFF_JWT && env.TEST_BRANCH_B_ID) {
  const crossBranch = await request("P0-AUTH-CROSS-BRANCH", edgeUrl, {
    method: "POST",
    headers: { origin: allowed, apikey: anonKey, authorization: `Bearer ${env.TEST_STAFF_JWT}`, "content-type": "application/json" },
    body: JSON.stringify({ action: "erp-list-branch-capacity", branch_id: env.TEST_BRANCH_B_ID }),
  });
  if (crossBranch) {
    const ok = [403, 200].includes(crossBranch.response.status);
    let parsed;
    try { parsed = JSON.parse(crossBranch.body); } catch {}
    const noCrossBranchData = crossBranch.response.status === 403 ||
      (crossBranch.response.status === 200 && Array.isArray(parsed?.capacities) && parsed.capacities.length === 0);
    record("P0-AUTH-CROSS-BRANCH", ok && noCrossBranchData,
      `cross-branch status=${crossBranch.response.status}; response body must be empty/scoped or denied`);
  }
} else {
  console.log("BLOCKED P0-AUTH-CROSS-BRANCH: disposable staff JWT and TEST_BRANCH_B_ID required");
}

if (env.TEST_OWNER_JWT) {
  console.log("INFO: Owner token supplied. Do not run privileged mutations in this smoke suite; use the acceptance protocol and reviewed disposable fixtures.");
}

const failures = results.filter((result) => result.status === "FAIL");
console.log(`\nSummary: ${results.filter((result) => result.status === "PASS").length} PASS, ${failures.length} FAIL, plus explicitly BLOCKED checks above.`);
if (failures.length) process.exit(1);
if (results.length === 0) process.exit(2);
