#!/usr/bin/env node
/**
 * Staging runtime smoke. Uses only the public publishable key and read-only actions.
 * The public catalog actions intentionally remain blocked while PUBLIC_TENANT_ROUTING_RELEASED=false.
 */
import assert from "node:assert/strict";

const preview = process.env.PREVIEW_URL?.replace(/\/$/, "");
if (!preview) {
  console.error("BLOCKED: PREVIEW_URL is required.");
  process.exit(2);
}
const parsedPreview = new URL(preview);
if (parsedPreview.protocol !== "https:" || !parsedPreview.hostname.endsWith(".vercel.app") ||
    ["dlice.vercel.app", "dlice-landing-page.vercel.app"].includes(parsedPreview.hostname)) {
  console.error("REFUSED: PREVIEW_URL must be a non-production Vercel Preview URL.");
  process.exit(2);
}

const headers = {};
if (process.env.VERCEL_AUTOMATION_BYPASS_SECRET) {
  headers["x-vercel-protection-bypass"] = process.env.VERCEL_AUTOMATION_BYPASS_SECRET;
}
const checks = [];
const record = (id, status, detail) => {
  checks.push({ id, status });
  console.log(`${status} ${id}: ${detail}`);
};

const configResponse = await fetch(`${preview}/api/runtime-config`, { headers, cache: "no-store" });
assert.equal(configResponse.status, 200, `runtime config HTTP ${configResponse.status}`);
const config = await configResponse.json();
assert.equal(config.environment, "preview", "deployment must identify itself as Vercel Preview");
assert.equal(new URL(config.supabaseUrl).hostname, "higoadrzxnhzbbwhdbmh.supabase.co", "Preview must point only to staging Supabase");
assert.ok(typeof config.publishableKey === "string" && config.publishableKey.startsWith("sb_publishable_"), "publishable key is required");
assert.ok(!/service_role|sb_secret_/i.test(config.publishableKey), "secret/service-role key must never reach browser config");
record("RUNTIME-CONFIG", "PASS", "preview config is environment-matched and contains only a publishable key");

const edgeUrl = `${config.supabaseUrl}/functions/v1/dlice-orders`;
const publicKey = config.publishableKey;
const previewOrigin = parsedPreview.origin;
const allowedPreflight = await fetch(edgeUrl, {
  method: "OPTIONS",
  headers: {
    origin: previewOrigin,
    "access-control-request-method": "POST",
    "access-control-request-headers": "authorization, apikey, content-type",
  },
});
assert.ok(allowedPreflight.status >= 200 && allowedPreflight.status < 300, `allowed CORS preflight HTTP ${allowedPreflight.status}`);
assert.equal(allowedPreflight.headers.get("access-control-allow-origin"), previewOrigin, "CORS must echo the exact staging Preview origin");
record("CORS-EXACT-PREVIEW", "PASS", `exact ACAO returned for ${previewOrigin}`);

const foreignPreflight = await fetch(edgeUrl, {
  method: "OPTIONS",
  headers: {
    origin: "https://cors-probe-foreign.invalid",
    "access-control-request-method": "POST",
    "access-control-request-headers": "authorization, apikey, content-type",
  },
});
assert.equal(foreignPreflight.status, 403, "foreign Origin must be rejected");
assert.equal(foreignPreflight.headers.get("access-control-allow-origin"), null, "foreign Origin must not receive ACAO");
record("CORS-FOREIGN-ORIGIN", "PASS", "foreign origin rejected without ACAO");

const absentOriginPreflight = await fetch(edgeUrl, {
  method: "OPTIONS",
  headers: {
    "access-control-request-method": "POST",
    "access-control-request-headers": "authorization, apikey, content-type",
  },
});
assert.equal(absentOriginPreflight.headers.get("access-control-allow-origin"), null, "origin-less request must not receive fallback ACAO");
record("CORS-NO-ORIGIN", "PASS", "no fallback ACAO returned");

async function postAction(action, extra = {}) {
  const response = await fetch(edgeUrl, {
    method: "POST",
    headers: { apikey: publicKey, "content-type": "application/json" },
    body: JSON.stringify({ action, ...extra }),
  });
  const body = await response.json().catch(() => ({}));
  return { response, body };
}

for (const [id, action, extra] of [
  ["PUBLIC-CATALOG", "list-products", {}],
  ["PUBLIC-BRANCHES", "list-online-branches", { receiving_method: "pickup" }],
]) {
  const { response, body } = await postAction(action, extra);
  if (response.status === 200) {
    const rows = id === "PUBLIC-CATALOG" ? body.products : body.branches;
    assert.ok(Array.isArray(rows), `${id} must return an array`);
    assert.ok(rows.length > 0, `${id} returned no active records`);
    record(id, "PASS", `${rows.length} records returned`);
  } else if (response.status === 423 && /PUBLIC_TENANT_ROUTING_RELEASED|routing tenant|isolasi katalog/i.test(String(body.error || ""))) {
    record(id, "PASS", "API reachable; expected fail-closed 423 while public tenant routing remains unreleased. Catalog/branch data is not yet certified.");
  } else {
    record(id, "FAIL", `HTTP ${response.status}: ${String(body.error || "unexpected response").slice(0, 180)}`);
  }
}

const failures = checks.filter((x) => x.status === "FAIL");
console.log(`Runtime smoke summary: ${checks.filter((x) => x.status === "PASS").length} PASS, ${failures.length} FAIL.`);
if (failures.length) process.exit(1);
