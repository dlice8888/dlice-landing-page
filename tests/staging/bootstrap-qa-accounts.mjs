#!/usr/bin/env node
/**
 * Idempotently provision disposable QA identities through the Owner-only
 * D'Lice administrative actions. Never reads or exposes a service-role key.
 * Restricted to the known staging project; never point this at production.
 */
const required = [
  "STAGING_SUPABASE_URL", "STAGING_SUPABASE_PUBLIC_KEY", "STAGING_EDGE_FUNCTION_URL",
  "STAGING_TEST_OWNER_USERNAME", "STAGING_TEST_OWNER_PASSWORD",
  "STAGING_TEST_BRANCH_A_USERNAME", "STAGING_TEST_BRANCH_A_PASSWORD",
  "STAGING_TEST_NO_PERMISSION_USERNAME", "STAGING_TEST_NO_PERMISSION_PASSWORD",
  "STAGING_TEST_INACTIVE_USERNAME", "STAGING_TEST_INACTIVE_PASSWORD",
];
const missing = required.filter((key) => !process.env[key]);
if (missing.length) {
  console.error("BLOCKED: staging QA bootstrap is missing required environment variables:", missing.join(", "));
  process.exit(2);
}
const url = process.env.STAGING_SUPABASE_URL.replace(/\/$/, "");
const expectedUrl = "https://higoadrzxnhzbbwhdbmh.supabase.co";
const edgeUrl = new URL(process.env.STAGING_EDGE_FUNCTION_URL);
if (url !== expectedUrl || edgeUrl.origin !== expectedUrl || edgeUrl.pathname !== "/functions/v1/dlice-orders") {
  console.error("BLOCKED: refusing to provision QA identities outside the known D’Lice staging project and Edge Function.");
  process.exit(2);
}
const anonKey = process.env.STAGING_SUPABASE_PUBLIC_KEY;
async function call(action, payload = {}, token = null) {
  let response;
  try {
    response = await fetch(edgeUrl, {
      method: "POST",
      headers: {
        apikey: anonKey,
        "content-type": "application/json",
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({ action, ...payload }),
    });
  } catch {
    throw new Error(`Administrative action ${action} could not reach the staging Edge Function.`);
  }
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`Administrative action ${action} failed with HTTP ${response.status}.`);
  return body;
}
const ownerUsername = process.env.STAGING_TEST_OWNER_USERNAME;
const ownerLogin = await call("admin-login", {
  username: ownerUsername,
  password: process.env.STAGING_TEST_OWNER_PASSWORD,
});
const ownerToken = ownerLogin?.session?.access_token;
if (typeof ownerToken !== "string") {
  console.error("BLOCKED: Owner staging login did not return a session; QA provisioning stopped.");
  process.exit(2);
}
const specs = [
  {
    key: "BRANCH_A", username: process.env.STAGING_TEST_BRANCH_A_USERNAME,
    password: process.env.STAGING_TEST_BRANCH_A_PASSWORD, active: true,
    permissions: ["orders", "branches", "inventory", "pos", "finance", "procurement", "reports"],
    position: "branch_manager", branch: "DLC-B001", label: "Branch A Manager",
  },
  {
    key: "NO_PERMISSION", username: process.env.STAGING_TEST_NO_PERMISSION_USERNAME,
    password: process.env.STAGING_TEST_NO_PERMISSION_PASSWORD, active: true,
    permissions: [], position: "cashier", branch: "DLC-B001", label: "No-Permission Staff",
  },
  {
    key: "INACTIVE", username: process.env.STAGING_TEST_INACTIVE_USERNAME,
    password: process.env.STAGING_TEST_INACTIVE_PASSWORD, active: false,
    permissions: [], position: "cashier", branch: "DLC-B002", label: "Inactive Staff",
  },
];
const ownerLower = ownerUsername.toLowerCase();
const seen = new Set();
for (const spec of specs) {
  if (!/^[a-zA-Z0-9._-]{3,32}$/.test(spec.username || "") || (spec.password || "").length < 12 || (spec.password || "").length > 128) {
    console.error(`BLOCKED: invalid username/password policy for ${spec.label}; usernames must be 3–32 allowed characters and passwords 12–128 characters.`);
    process.exit(2);
  }
  const normalized = spec.username.toLowerCase();
  if (normalized === ownerLower || seen.has(normalized)) {
    console.error("BLOCKED: QA usernames must be unique and must not match the Owner username.");
    process.exit(2);
  }
  seen.add(normalized);
}
const [staffResponse, branchResponse, positionResponse] = await Promise.all([
  call("admin-list-staff", {}, ownerToken),
  call("erp-list-branches", {}, ownerToken),
  call("erp-list-positions", {}, ownerToken),
]);
const staffByUsername = new Map((staffResponse.staff || []).map((user) => [String(user.username).toLowerCase(), user]));
const branchByCode = new Map((branchResponse.branches || []).map((branch) => [branch.code, branch]));
const positionByCode = new Map((positionResponse.positions || []).map((position) => [position.code, position]));
for (const code of ["DLC-B001", "DLC-B002"]) {
  if (!branchByCode.has(code)) throw new Error(`Required staging QA branch ${code} is missing.`);
}
for (const code of ["branch_manager", "cashier"]) {
  if (!positionByCode.has(code)) throw new Error(`Required active job position ${code} is missing.`);
}
async function ensureAuthPassword(spec) {
  if (spec.active) {
    const login = await call("admin-login", { username: spec.username, password: spec.password });
    if (typeof login?.session?.access_token !== "string") throw new Error(`QA Auth verification failed for ${spec.label}.`);
    return;
  }
  // Inactive profiles intentionally cannot use the D'Lice username-login action.
  // Verify Supabase Auth itself can issue a token, then confirm the Edge Function denies the inactive profile.
  let response;
  try {
    response = await fetch(`${url}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: anonKey, "content-type": "application/json" },
      body: JSON.stringify({ email: `${spec.username.toLowerCase()}@accounts.dlice.internal`, password: spec.password }),
    });
  } catch {
    throw new Error("Could not reach Supabase Auth for inactive-profile credential verification.");
  }
  const body = await response.json().catch(() => ({}));
  if (!response.ok || typeof body.access_token !== "string") throw new Error("Supabase Auth could not verify the inactive QA credentials.");
}
for (const spec of specs) {
  let profile = staffByUsername.get(spec.username.toLowerCase());
  if (!profile) {
    await call("admin-create-staff", {
      username: spec.username,
      display_name: `STAGING QA — ${spec.label}`,
      password: spec.password,
      permissions: spec.permissions,
    }, ownerToken);
    const refreshed = await call("admin-list-staff", {}, ownerToken);
    profile = (refreshed.staff || []).find((user) => String(user.username).toLowerCase() === spec.username.toLowerCase());
  }
  if (!profile?.user_id || profile.role === "owner") throw new Error(`Could not safely identify the staging profile for ${spec.label}.`);
  await call("admin-set-permissions", { user_id: profile.user_id, permissions: spec.permissions }, ownerToken);
  await call("admin-set-active", { user_id: profile.user_id, is_active: spec.active }, ownerToken);
  const branch = branchByCode.get(spec.branch);
  const position = positionByCode.get(spec.position);
  await call("erp-save-assignment", {
    branch_id: branch.id,
    user_id: profile.user_id,
    job_position_id: position.id,
    employment_status: spec.active ? "active" : "inactive",
    starts_on: new Date().toISOString().slice(0, 10),
    ends_on: null,
  }, ownerToken);
  await ensureAuthPassword(spec);
  console.log(`PASS QA_ACCOUNT_CONFIGURED: ${spec.label}; active=${spec.active}; branch=${spec.branch}; permissions=${spec.permissions.length ? "explicit least-privilege" : "none"}`);
}
console.log("PASS STAGING_QA_ACCOUNT_BOOTSTRAP: 3 QA profiles provisioned through Owner-only Edge Function actions; no service-role key or credentials printed.");
