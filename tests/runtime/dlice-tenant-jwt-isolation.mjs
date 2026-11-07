// Nine independently recorded authenticated tenant-boundary probes.
// Credentials are never printed. A probe is PASS/FAIL only when its request ran;
// prerequisites that are absent are BLOCKED with executed:false.
const base = process.env.STAGING_SUPABASE_URL?.replace(/\/$/, "");
const key = process.env.STAGING_SUPABASE_ANON_KEY;
const cfg = {
  usernameA: process.env.STAGING_TENANT_A_USERNAME,
  passwordA: process.env.STAGING_TENANT_A_PASSWORD,
  usernameB: process.env.STAGING_TENANT_B_USERNAME,
  passwordB: process.env.STAGING_TENANT_B_PASSWORD,
  branchA: process.env.STAGING_TENANT_A_BRANCH_ID,
  branchB: process.env.STAGING_TENANT_B_BRANCH_ID,
  userA: process.env.STAGING_TENANT_A_USER_ID,
  userB: process.env.STAGING_TENANT_B_USER_ID,
};
const probes = new Map();
function record(name, status, executed, evidence = {}) {
  const item = { name, status, executed, evidence };
  probes.set(name, item);
  console.log(JSON.stringify({ probe: name, ...item }));
  return item;
}
function blocked(name, reason) { return record(name, "BLOCKED", false, { reason }); }
function pass(name, evidence) { return record(name, "PASS", true, evidence); }
function fail(name, evidence) { return record(name, "FAIL", true, evidence); }
const required = [
  ["STAGING_SUPABASE_URL", base], ["STAGING_SUPABASE_PUBLIC_KEY", key],
  ["STAGING_TENANT_A_USERNAME", cfg.usernameA], ["STAGING_TENANT_A_PASSWORD", cfg.passwordA],
  ["STAGING_TENANT_B_USERNAME", cfg.usernameB], ["STAGING_TENANT_B_PASSWORD", cfg.passwordB],
  ["STAGING_TENANT_A_BRANCH_ID", cfg.branchA], ["STAGING_TENANT_B_BRANCH_ID", cfg.branchB],
  ["STAGING_TENANT_A_USER_ID", cfg.userA], ["STAGING_TENANT_B_USER_ID", cfg.userB],
];
const missing = required.filter(([, value]) => !value).map(([name]) => name);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const invalid = required.filter(([name, value]) => name.includes("_ID") && value && !uuid.test(value)).map(([name]) => name);
const fixtureOk = !invalid.length && cfg.branchA !== cfg.branchB && cfg.userA !== cfg.userB;
if (missing.length || !fixtureOk) {
  const reason = missing.length ? "missing_preflight_inputs" : "invalid_or_non_distinct_fixture_ids";
  for (const name of [
    "tenant-a-login", "tenant-b-login", "tenant-identities-distinct",
    "tenant-a-own-branch-read", "tenant-b-own-branch-read",
    "tenant-a-cross-tenant-read-denied", "tenant-b-cross-tenant-read-denied",
    "tenant-a-cross-tenant-write-denied", "tenant-b-cross-tenant-write-denied",
  ]) blocked(name, reason);
  console.error(JSON.stringify({ gate: "tenant-isolation", status: "FAIL", executedProbeCount: 0, blockedProbeCount: 9, missingInputNames: missing, invalidFixtureNames: invalid, secretValuesPrinted: false }));
  process.exit(2);
}
console.log(JSON.stringify({ preflight: "PASS", fixtureIdsDistinct: true, secretValuesPrinted: false }));
async function safeFetch(url, init) {
  try { return await fetch(url, { ...init, redirect: "manual" }); }
  catch (error) { return { status: 0, ok: false, _networkError: String(error?.name || "network_error") }; }
}
async function login(label, username, password) {
  const response = await safeFetch(`${base}/functions/v1/dlice-orders`, {
    method: "POST", headers: { apikey: key, "content-type": "application/json" },
    body: JSON.stringify({ action: "admin-login", username, password }),
  });
  const payload = response.status ? await response.json().catch(() => ({})) : {};
  const token = payload.session?.access_token;
  const ok = response.status === 200 && typeof token === "string" && token.split(".").length === 3;
  (ok ? pass : fail)(`${label}-login`, { httpStatus: response.status, tokenShapeValid: !!ok, error: typeof payload.error === "string" ? payload.error.slice(0,120) : undefined, networkError: response._networkError });
  return ok ? token : null;
}
async function apiProbe(name, path, token, init, predicate) {
  if (!token) return blocked(name, "required_login_not_successful");
  const response = await safeFetch(`${base}${path}`, {
    ...init, headers: { apikey: key, authorization: `Bearer ${token}`, "content-type": "application/json", ...(init?.headers || {}) },
  });
  const body = response.status ? await response.text().catch(() => "") : "";
  let payload = null; try { payload = JSON.parse(body); } catch {}
  const verdict = predicate({ response, body, payload });
  const evidence = { httpStatus: response.status, responseBytes: body.length, ...verdict.evidence, networkError: response._networkError };
  (verdict.ok ? pass : fail)(name, evidence);
  return { ok: verdict.ok, response, body, payload };
}
const tokenA = await login("tenant-a", cfg.usernameA, cfg.passwordA);
const tokenB = await login("tenant-b", cfg.usernameB, cfg.passwordB);
let identityA = null, identityB = null;
if (tokenA) {
  const r = await apiProbe("tenant-a-identity-check", "/auth/v1/user", tokenA, {}, ({response,payload}) => ({
    ok: response.status === 200 && payload?.id === cfg.userA,
    evidence: { expectedUserMatched: payload?.id === cfg.userA },
  }));
  if (r.ok) identityA = r.payload.id;
}
if (tokenB) {
  const r = await apiProbe("tenant-b-identity-check", "/auth/v1/user", tokenB, {}, ({response,payload}) => ({
    ok: response.status === 200 && payload?.id === cfg.userB,
    evidence: { expectedUserMatched: payload?.id === cfg.userB },
  }));
  if (r.ok) identityB = r.payload.id;
}
if (!identityA || !identityB) blocked("tenant-identities-distinct", "one_or_both_identity_checks_not_successful");
else (identityA !== identityB ? pass : fail)("tenant-identities-distinct", { identitiesDifferent: identityA !== identityB });
const ownRead = async (label, token, branch) => apiProbe(`${label}-own-branch-read`, "/functions/v1/dlice-orders", token, {
  method: "POST", body: JSON.stringify({ action: "erp-list-inventory", branch_id: branch }),
}, ({response,payload}) => {
  const balances = Array.isArray(payload?.balances) ? payload.balances : [];
  return { ok: response.status === 200 && balances.length > 0 && balances.every(x => x.branch_id === branch),
    evidence: { balanceRows: balances.length, allRowsMatchOwnBranch: balances.every(x => x.branch_id === branch) } };
});
await ownRead("tenant-a", tokenA, cfg.branchA);
await ownRead("tenant-b", tokenB, cfg.branchB);
const crossRead = async (label, token, foreignBranch) => apiProbe(`${label}-cross-tenant-read-denied`, "/functions/v1/dlice-orders", token, {
  method: "POST", body: JSON.stringify({ action: "erp-list-inventory", branch_id: foreignBranch }),
}, ({response}) => ({ ok: response.status === 403, evidence: { expectedHttpStatus: 403 } }));
await crossRead("tenant-a", tokenA, cfg.branchB);
await crossRead("tenant-b", tokenB, cfg.branchA);
const crossWrite = async (label, token, ownBranch, foreignBranch) => apiProbe(`${label}-cross-tenant-write-denied`, "/functions/v1/dlice-orders", token, {
  method: "POST", body: JSON.stringify({
    action: "erp-create-stock-transfer", transfer_number: `SECURITY-DENY-${label}-${Date.now()}`,
    source_branch_id: ownBranch, destination_branch_id: foreignBranch,
    inventory_item_id: "00000000-0000-4000-8000-000000000099", quantity: 1,
    idempotency_key: `deny-${label}-${crypto.randomUUID()}`,
    notes: "Negative security test; must be rejected before mutation",
  }),
}, ({response}) => ({ ok: response.status === 403, evidence: { expectedHttpStatus: 403, mutationMustNotRun: true } }));
await crossWrite("tenant-a", tokenA, cfg.branchA, cfg.branchB);
await crossWrite("tenant-b", tokenB, cfg.branchB, cfg.branchA);
const requiredNames = [
  "tenant-a-login", "tenant-b-login", "tenant-identities-distinct",
  "tenant-a-own-branch-read", "tenant-b-own-branch-read",
  "tenant-a-cross-tenant-read-denied", "tenant-b-cross-tenant-read-denied",
  "tenant-a-cross-tenant-write-denied", "tenant-b-cross-tenant-write-denied",
];
const summary = requiredNames.map(name => probes.get(name) || { name, status:"BLOCKED", executed:false, evidence:{reason:"probe_not_recorded"} });
const executedProbeCount = summary.filter(x => x.executed).length;
const failed = summary.filter(x => x.status !== "PASS");
console.log(JSON.stringify({ gate:"tenant-isolation", status: failed.length ? "FAIL" : "PASS", requiredProbeCount:9, executedProbeCount, passProbeCount:summary.filter(x=>x.status==="PASS").length, failProbeCount:summary.filter(x=>x.status==="FAIL").length, blockedProbeCount:summary.filter(x=>x.status==="BLOCKED").length, probes:summary }));
if (failed.length || summary.some(x => !x.executed)) process.exit(2);
