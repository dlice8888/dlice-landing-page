// Runtime CORS and auth smoke tests for the deployed dlice-orders Edge Function.
// Requires STAGING_SUPABASE_URL and STAGING_SUPABASE_ANON_KEY.
// This script does not mutate application data.
import assert from "node:assert/strict";

const base = process.env.STAGING_SUPABASE_URL?.replace(/\/$/, "");
const key = process.env.STAGING_SUPABASE_ANON_KEY;
if (!base || !key) {
  console.error("Missing STAGING_SUPABASE_URL or STAGING_SUPABASE_ANON_KEY; refusing to infer a target.");
  process.exit(2);
}
const endpoint = `${base}/functions/v1/dlice-orders`;
const allowedOrigin = process.env.STAGING_ALLOWED_ORIGIN;
const foreignOrigin = process.env.STAGING_FOREIGN_ORIGIN ?? "https://origin-not-allowlisted.invalid";

async function probe(name, init, check) {
  const response = await fetch(endpoint, { ...init, redirect: "manual" });
  const acao = response.headers.get("access-control-allow-origin");
  console.log(JSON.stringify({ name, status: response.status, acao }));
  check(response, acao);
}
const headers = { apikey: key, "content-type": "application/json" };

await probe("foreign-origin-preflight", {
  method: "OPTIONS",
  headers: { ...headers, origin: foreignOrigin, "access-control-request-method": "POST" },
}, (response, acao) => {
  assert.equal(response.status, 403, "foreign Origin must be rejected");
  assert.equal(acao, null, "foreign Origin must not receive ACAO");
});

await probe("no-origin-preflight", {
  method: "OPTIONS",
  headers: { ...headers, "access-control-request-method": "POST" },
}, (response, acao) => {
  assert.equal(response.status, 200, "no-Origin preflight should not be rejected by CORS");
  assert.equal(acao, null, "no-Origin request must not receive fallback ACAO");
});

if (allowedOrigin) {
  await probe("registered-origin-preflight", {
    method: "OPTIONS",
    headers: { ...headers, origin: allowedOrigin, "access-control-request-method": "POST" },
  }, (response, acao) => {
    assert.equal(response.status, 200, "registered Origin should be allowed");
    assert.equal(acao, allowedOrigin, "registered Origin must receive exact ACAO");
  });
} else {
  console.log(JSON.stringify({ name: "registered-origin-preflight", skipped: true, reason: "STAGING_ALLOWED_ORIGIN not supplied" }));
}

await probe("anonymous-admin-list-orders", {
  method: "POST",
  headers,
  body: JSON.stringify({ action: "admin-list-orders" }),
}, (response) => {
  assert.ok([401, 403, 423].includes(response.status), "anonymous admin action must fail closed");
});

console.log("Runtime smoke tests passed for all configured probes.");
