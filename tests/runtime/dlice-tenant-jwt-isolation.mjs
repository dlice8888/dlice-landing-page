// Authenticated tenant-boundary probes for staging Supabase Data API.
// Configure only with two legitimate QA users from different tenants.
// No secrets or JWTs are printed. This script performs read-only REST probes and
// calls only the explicitly selected negative RPC/Edge actions supplied by env.
import assert from "node:assert/strict";

const base = process.env.STAGING_SUPABASE_URL?.replace(/\/$/, "");
const key = process.env.STAGING_SUPABASE_ANON_KEY;
const tokenA = process.env.STAGING_TENANT_A_JWT;
const tokenB = process.env.STAGING_TENANT_B_JWT;
const tenantA = process.env.STAGING_TENANT_A_ID;
const tenantB = process.env.STAGING_TENANT_B_ID;
const branchA = process.env.STAGING_TENANT_A_BRANCH_ID;
const branchB = process.env.STAGING_TENANT_B_BRANCH_ID;
if (![base, key, tokenA, tokenB, tenantA, tenantB, branchA, branchB].every(Boolean)) {
  console.error("Missing required staging URL/key, two user JWTs, tenant IDs, or branch fixture IDs. No probes run.");
  process.exit(2);
}
assert.notEqual(tenantA, tenantB, "Tenant A and B must be distinct");
assert.ok(tenantA && tenantB, "Both tenant fixture IDs must be configured");
assert.notEqual(branchA, branchB, "Branch fixtures must be distinct");
for (const [label, token] of [["STAGING_TENANT_A_JWT", tokenA], ["STAGING_TENANT_B_JWT", tokenB]]) {
  if (token.split(".").length !== 3 || token.startsWith("Bearer ")) {
    console.error(`${label} must contain only a raw Supabase access_token JWT (three dot-separated segments), not a refresh token, JSON session, API key, or "Bearer " prefix. Secret values were not printed.`);
    process.exit(2);
  }
}

async function request(name, path, token, init = {}) {
  const response = await fetch(`${base}${path}`, {
    ...init,
    headers: {
      apikey: key,
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
    redirect: "manual",
  });
  const text = await response.text();
  let safeError = {};
  if (!response.ok) {
    try {
      const payload = JSON.parse(text);
      const code = payload.code ?? payload.error_code ?? payload.error;
      const message = payload.msg ?? payload.message ?? payload.error_description;
      if (typeof code === "string") safeError.errorCode = code.slice(0, 80);
      if (typeof message === "string") safeError.errorMessage = message.slice(0, 180);
    } catch {
      safeError.errorBody = "non_json";
    }
  }
  console.log(JSON.stringify({ name, status: response.status, bodyBytes: text.length, ...safeError }));
  return { response, text };
}
async function verifyIdentity(label, token, expectedUserId) {
  const { response, text } = await request(`${label}-identity`, "/auth/v1/user", token);
  assert.equal(response.status, 200, `${label} JWT must resolve to a real user`);
  const user = JSON.parse(text);
  assert.ok(user.id, `${label} identity response missing id`);
  if (expectedUserId) assert.equal(user.id, expectedUserId, `${label} JWT user mismatch`);
  return user.id;
}

const userA = await verifyIdentity("tenant-a", tokenA, process.env.STAGING_TENANT_A_USER_ID);
const userB = await verifyIdentity("tenant-b", tokenB, process.env.STAGING_TENANT_B_USER_ID);
assert.notEqual(userA, userB, "Tenant fixtures must use different user identities");

async function verifyBusinessInventoryScope(label, token, ownBranchId, foreignBranchId) {
  const own = await request(`${label}-business-own-branch-inventory`, "/functions/v1/dlice-orders", token, {
    method: "POST",
    body: JSON.stringify({ action: "erp-list-inventory", branch_id: ownBranchId }),
  });
  assert.equal(own.response.status, 200, `${label} must be able to read inventory for its own branch`);
  const ownPayload = JSON.parse(own.text);
  assert.ok(Array.isArray(ownPayload.balances), `${label} own-branch response must include balances`);
  assert.ok(ownPayload.balances.every((row) => row.branch_id === ownBranchId), `${label} own-branch response leaked balances from another branch`);

  const foreign = await request(`${label}-business-foreign-branch-inventory-denied`, "/functions/v1/dlice-orders", token, {
    method: "POST",
    body: JSON.stringify({ action: "erp-list-inventory", branch_id: foreignBranchId }),
  });
  assert.equal(foreign.response.status, 403, `${label} must be denied access to a foreign tenant branch`);
}
await verifyBusinessInventoryScope("tenant-a", tokenA, branchA, branchB);
await verifyBusinessInventoryScope("tenant-b", tokenB, branchB, branchA);

// The current staging RLS policy deliberately denies direct client access to
// branches (including a user's own branch). Do not mistake this deny-all route
// for proof that the authenticated business API correctly scopes tenants.
async function branchDirectAccessDenied(label, token, branchId) {
  const { response, text } = await request(
    label,
    `/rest/v1/branches?id=eq.${encodeURIComponent(branchId)}&select=id,tenant_id`,
    token,
    { headers: { accept: "application/json" } },
  );
  assert.equal(response.status, 200, `${label} should return a filtered result, not an API error`);
  const rows = JSON.parse(text);
  assert.ok(Array.isArray(rows), `${label} response should be an array`);
  assert.equal(rows.some((row) => row.id === branchId), false, `${label} unexpectedly exposed a branch via direct REST`);
}
await branchDirectAccessDenied("tenant-a-direct-own-branch-denied", tokenA, branchA);
await branchDirectAccessDenied("tenant-a-direct-foreign-branch-denied", tokenA, branchB);
await branchDirectAccessDenied("tenant-b-direct-own-branch-denied", tokenB, branchB);
await branchDirectAccessDenied("tenant-b-direct-foreign-branch-denied", tokenB, branchA);

// The stock-transfer RPC is server-only in current staging ACLs. Confirm an
// authenticated client cannot bypass the Edge Function and call it directly.
for (const [label, token] of [["tenant-a", tokenA], ["tenant-b", tokenB]]) {
  const { response } = await request(`${label}-direct-stock-transfer-rpc-denied`, "/rest/v1/rpc/erp_create_stock_transfer", token, {
    method: "POST",
    body: JSON.stringify({
      p_transfer_number: "SECURITY-PROBE-NO-WRITE",
      p_source_branch_id: branchA,
      p_destination_branch_id: branchB,
      p_items: [],
      p_actor_user_id: label === "tenant-a" ? userA : userB,
      p_idempotency_key: `security-probe-${label}`,
      p_notes: "Negative security test; must not execute",
    }),
  });
  assert.ok([401, 403, 404, 405].includes(response.status), `${label} direct server-only RPC must be inaccessible (got ${response.status})`);
}

// Optional Edge Function negative probe: provide a known action and body which
// is expected to be rejected. Never defaults to a guessed business mutation.
const edgeAction = process.env.STAGING_NEGATIVE_EDGE_ACTION;
const edgeBody = process.env.STAGING_NEGATIVE_EDGE_BODY;
if (edgeAction || edgeBody) {
  assert.ok(edgeAction && edgeBody, "Set both STAGING_NEGATIVE_EDGE_ACTION and STAGING_NEGATIVE_EDGE_BODY");
  const parsedBody = JSON.parse(edgeBody);
  assert.equal(parsedBody.action, edgeAction, "Edge probe body action must match configured action");
  for (const [label, token] of [["tenant-a", tokenA], ["tenant-b", tokenB]]) {
    const { response } = await request(`${label}-edge-negative-${edgeAction}`, "/functions/v1/dlice-orders", token, {
      method: "POST",
      body: JSON.stringify(parsedBody),
    });
    assert.ok([401, 403, 404, 409, 423].includes(response.status), `${label} negative Edge probe unexpectedly succeeded (got ${response.status})`);
  }
} else {
  console.log(JSON.stringify({ name: "edge-negative-action", skipped: true, reason: "No explicitly approved negative action configured" }));
}
console.log("PASS: both JWT identities, own-branch inventory success, foreign-branch 403, direct REST isolation, and server-only stock-transfer RPC denial.");
console.log("Release gate remains closed: runtime CORS/JWT workflow evidence, independent migration review, staging migration replay, and stock/audit reconciliation are separate required gates.");

// Re-run staging runtime gates on push; no test behavior or credentials changed.
