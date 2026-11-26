// Exercise the custom authentication boundary for every admin/ERP action.
// dlice-orders has verify_jwt=false, so protected actions must reject missing and
// invalid bearer tokens before privileged reads or mutations.
// admin-bootstrap-owner is intentionally different: it is a one-time bootstrap
// endpoint gated by DLICE_OWNER_BOOTSTRAP_SECRET before any account/database work.
// These probes omit that secret, so HTTP 403 is the expected fail-closed result.
// This test uses only the staging URL and publishable/anon key; no service-role key.
import { readFileSync } from "node:fs";

const base = process.env.STAGING_SUPABASE_URL?.replace(/\/$/, "");
const publicKey = process.env.STAGING_SUPABASE_ANON_KEY;
const expectedHost = "higoadrzxnhzbbwhdbmh.supabase.co";

function validPublicKey(value) {
  if (typeof value !== "string" || !value || value.startsWith("sb_secret_")) return false;
  if (/^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(value)) return true;
  try {
    const parts = value.split(".");
    if (parts.length !== 3) return false;
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    return payload.role === "anon";
  } catch {
    return false;
  }
}

if (!base || !publicKey || !validPublicKey(publicKey)) {
  console.error(JSON.stringify({
    probe: "EDGE_ACTION_AUTH_PREFLIGHT",
    status: "BLOCKED",
    reason: "missing_or_invalid_staging_url_or_public_key",
    valuesPrinted: false,
  }));
  process.exit(2);
}
const parsed = new URL(base);
if (parsed.protocol !== "https:" || parsed.hostname !== expectedHost || parsed.pathname !== "/" || parsed.search || parsed.hash) {
  console.error(JSON.stringify({
    probe: "EDGE_ACTION_AUTH_PREFLIGHT",
    status: "FAIL",
    reason: "staging_url_not_allowlisted",
    valuesPrinted: false,
  }));
  process.exit(2);
}

const source = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");
const actions = [...new Set(
  [...source.matchAll(/action\s*===\s*"([^"]+)"/g)]
    .map((match) => match[1])
    .filter((action) => action.startsWith("admin-") || action.startsWith("erp-")),
)].sort();
if (actions.length !== 222) {
  console.error(JSON.stringify({
    probe: "EDGE_ACTION_AUTH_INVENTORY",
    status: "FAIL",
    expectedActions: 222,
    actualActions: actions.length,
    valuesPrinted: false,
  }));
  process.exit(1);
}

const endpoint = `${base}/functions/v1/dlice-orders`;
const cases = actions.flatMap((action) => [
  { action, credential: "missing", authorization: null },
  { action, credential: "invalid", authorization: "Bearer invalid.invalid.invalid" },
]);
const results = [];
let cursor = 0;
const concurrency = 6;
async function worker() {
  while (cursor < cases.length) {
    const current = cases[cursor++];
    const headers = { apikey: publicKey, "content-type": "application/json" };
    if (current.authorization) headers.authorization = current.authorization;
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers,
        body: JSON.stringify({ action: current.action }),
        redirect: "manual",
      });
      const expectedStatus = current.action === "admin-bootstrap-owner" ? 403 : 401;
      results.push({
        action: current.action,
        credential: current.credential,
        status: response.status,
        expectedStatus,
        passed: response.status === expectedStatus,
      });
      // Never read or log response bodies; they may contain implementation details.
      await response.body?.cancel();
    } catch (error) {
      results.push({
        action: current.action,
        credential: current.credential,
        status: null,
        passed: false,
        error: error instanceof Error ? error.name : "UnknownError",
      });
    }
  }
}
await Promise.all(Array.from({ length: concurrency }, () => worker()));
results.sort((a, b) => a.action.localeCompare(b.action) || a.credential.localeCompare(b.credential));
const failures = results.filter((result) => !result.passed);
for (const result of results) {
  console.log(JSON.stringify({
    probe: "EDGE_ACTION_AUTH",
    action: result.action,
    credential: result.credential,
    httpStatus: result.status,
    expectedHttpStatus: result.expectedStatus,
    status: result.passed ? "PASS" : "FAIL",
    ...(result.error ? { error: result.error } : {}),
  }));
}
console.log(JSON.stringify({
  probe: "EDGE_ACTION_AUTH_SUMMARY",
  status: failures.length === 0 ? "PASS" : "FAIL",
  actions: actions.length,
  requests: results.length,
  passed: results.length - failures.length,
  failed: failures.length,
  expectedHttpStatus: { default: 401, "admin-bootstrap-owner": 403 },
  bootstrapOwnerGuard: "secret-required-before-any-bootstrap-side-effect",
  credentials: ["missing", "invalid"],
  responseBodiesLogged: false,
  secretValuesPrinted: false,
}));
if (failures.length) process.exitCode = 1;
