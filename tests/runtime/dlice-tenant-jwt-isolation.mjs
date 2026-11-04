// Authenticated tenant-boundary probes for staging Supabase Data API.
// Configure only with two legitimate QA users from different tenants.
// No secrets or JWTs are printed. This script performs read-only REST probes and
// calls only the explicitly selected negative RPC/Edge actions supplied by env.
import assert from "node:assert/strict";

const base = process.env.STAGING_SUPABASE_URL?.replace(/\/$/, "");
const key = process.env.STAGING_SUPABASE_ANON_KEY;
const usernameA = process.env.STAGING_TENANT_A_USERNAME;
const passwordA = process.env.STAGING_TENANT_A_PASSWORD;
const usernameB = process.env.STAGING_TENANT_B_USERNAME;
const passwordB = process.env.STAGING_TENANT_B_PASSWORD;
const branchA = process.env.STAGING_TENANT_A_BRANCH_ID;
const branchB = process.env.STAGING_TENANT_B_BRANCH_ID;
const expectedUserA = process.env.STAGING_TENANT_A_USER_ID;
const expectedUserB = process.env.STAGING_TENANT_B_USER_ID;
const credentialSources = {
  tenantAUsername: process.env.STAGING_TENANT_A_USERNAME_SOURCE || "unknown",
  tenantAPassword: process.env.STAGING_TENANT_A_PASSWORD_SOURCE || "unknown",
  tenantBUsername: process.env.STAGING_TENANT_B_USERNAME_SOURCE || "unknown",
  tenantBPassword: process.env.STAGING_TENANT_B_PASSWORD_SOURCE || "unknown",
};
const missingInputs = [];
for (const [name, value] of [
  ["STAGING_SUPABASE_URL", base],
  ["STAGING_SUPABASE_PUBLIC_KEY", key],
  ["STAGING_TENANT_A_BRANCH_ID", branchA],
  ["STAGING_TENANT_B_BRANCH_ID", branchB],
  ["STAGING_TENANT_A_USER_ID", expectedUserA],
  ["STAGING_TENANT_B_USER_ID", expectedUserB],
  ["STAGING_TENANT_A_USERNAME", usernameA],
  ["STAGING_TENANT_A_PASSWORD", passwordA],
  ["STAGING_TENANT_B_USERNAME", usernameB],
  ["STAGING_TENANT_B_PASSWORD", passwordB],
]) {
  if (!value) missingInputs.push(name);
}
if (missingInputs.length) {
  console.error(JSON.stringify({
    name: "secret-preflight",
    status: "FAIL",
    missingInputNames: missingInputs,
    credentialSources,
    secretValuesPrinted: false,
  }));
  for (const name of [
    "tenant-a-login",
    "tenant-b-login",
    "tenant-identities-distinct",
    "tenant-a-own-branch-read",
    "tenant-b-own-branch-read",
    "tenant-a-cross-tenant-read-denied",
    "tenant-b-cross-tenant-read-denied",
    "tenant-a-cross-tenant-write-denied",
    "tenant-b-cross-tenant-write-denied",
  ]) {
    console.error(JSON.stringify({
      name,
      status: "BLOCKED",
      reason: "secret_preflight_failed",
      executed: false,
    }));
  }
  console.error("FAIL: runtime tenant-isolation gate blocked; no security probe is claimed as executed.");
  process.exit(2);
}
console.log(JSON.stringify({ name: "secret-preflight", status: "PASS", credentialSources, secretValuesPrinted: false }));
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const fixtureIds = [
  ["STAGING_TENANT_A_BRANCH_ID", branchA],
  ["STAGING_TENANT_B_BRANCH_ID", branchB],
  ["STAGING_TENANT_A_USER_ID", expectedUserA],
  ["STAGING_TENANT_B_USER_ID", expectedUserB],
];
const invalidFixtureIds = fixtureIds.filter(([, value]) => !uuidPattern.test(value)).map(([name]) => name);
if (invalidFixtureIds.length || branchA === branchB || expectedUserA === expectedUserB) {
  console.error(JSON.stringify({
    name: "fixture-preflight",
    status: "FAIL",
    invalidInputNames: invalidFixtureIds,
    branchIdsDistinct: branchA !== branchB,
    userIdsDistinct: expectedUserA !== expectedUserB,
  }));
  process.exit(2);
}

async function loginWithDliceUsername(label, username, password) {
  // Use the same username/password flow as the D'Lice UI. The Edge Function
  // maps username to its internal Supabase Auth identity and returns a session.
  const response = await fetch(`${base}/functions/v1/dlice-orders`, {
    method: "POST",
    headers: { apikey: key, "content-type": "application/json" },
    body: JSON.stringify({ action: "admin-login", username, password }),
    redirect: "manual",
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload.session?.access_token) {
    console.error(JSON.stringify({
      name: `${label}-dlice-login-failed`,
      status: response.status,
      error: typeof payload.error === "string" ? payload.error.slice(0, 160) : "missing_session",
    }));
    return null;
  }
  const token = payload.session.access_token;
  if (typeof token !== "string" || token.split(".").length !== 3 || token.startsWith("Bearer ")) {
    console.error(`${label} D'Lice login did not return a raw three-segment Supabase access_token. No token value was printed.`);
    process.exit(2);
  }
  console.log(JSON.stringify({ name: `${label}-dlice-username-login`, status: response.status, accessTokenShapeValid: true }));
  return token;
}
// Both QA identities must perform an actual username/password login. JWT-only
// fallback is intentionally disallowed so the release evidence proves two logins.
const tokenA = await loginWithDliceUsername("tenant-a", usernameA, passwordA);
const tokenB = await loginWithDliceUsername("tenant-b", usernameB, passwordB);
assert.ok(tokenA, "Tenant A username/password login must succeed");
assert.ok(tokenB, "Tenant B username/password login must succeed");

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

const userA = await verifyIdentity("tenant-a", tokenA, expectedUserA);
const userB = await verifyIdentity("tenant-b", tokenB, expectedUserB);
assert.notEqual(userA, userB, "Tenant fixtures must use different user identities");

async function verifyBusinessInventoryScope(label, token, ownBranchId, foreignBranchId) {
  // The current handler returns catalog metadata but an empty balance list
  // when branch_id is omitted. This is not a 422 denial, so do not mislabel it
  // as an authorization test; tenant isolation is proven by the explicit
  // foreign-branch probe below.
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
  assert.ok([401, 403].includes(response.status), `${label} direct server-only RPC must return an explicit authentication/authorization denial; 404/405 are not accepted as proof (got ${response.status})`);
}

// Mandatory negative write probes: the handler checks branchAccess for BOTH
// source and destination before invoking the stock-transfer RPC. A foreign
// destination must be rejected with 403 and must never reach the mutation RPC.
async function verifyForeignWriteDenied(label, token, ownBranchId, foreignBranchId) {
  const probeNumber = `SECURITY-DENY-${label.toUpperCase()}-${Date.now()}`;
  const { response } = await request(`${label}-foreign-stock-transfer-write-denied`, "/functions/v1/dlice-orders", token, {
    method: "POST",
    body: JSON.stringify({
      action: "erp-create-stock-transfer",
      transfer_number: probeNumber,
      source_branch_id: ownBranchId,
      destination_branch_id: foreignBranchId,
      inventory_item_id: "00000000-0000-4000-8000-000000000099",
      quantity: 1,
      idempotency_key: `deny-${label}-${Date.now()}`,
      notes: "Automated tenant-isolation negative test; must be rejected before mutation",
    }),
  });
  assert.equal(response.status, 403, `${label} must be denied before creating a cross-tenant stock transfer`);
}
await verifyForeignWriteDenied("tenant-a", tokenA, branchA, branchB);
await verifyForeignWriteDenied("tenant-b", tokenB, branchB, branchA);
console.log("PASS: both real username/password logins, distinct users, own-branch inventory success, foreign-branch read denial, foreign-branch write denial, direct REST isolation, and server-only stock-transfer RPC denial.");
console.log("Release gate remains closed: runtime CORS/JWT workflow evidence, independent migration review, staging migration replay, and stock/audit reconciliation are separate required gates.");

// Re-run staging runtime gates on push; no test behavior or credentials changed.
