// Authenticated tenant-boundary probes for staging Supabase Data API.
// Credentials are accepted only from the trusted staging GitHub Environment.
// Tokens, passwords, usernames, and response bodies are never written to logs.
import { randomUUID } from "node:crypto";
import { performance } from "node:perf_hooks";

const base = process.env.STAGING_SUPABASE_URL?.replace(/\/$/, "");
const key = process.env.STAGING_SUPABASE_ANON_KEY;
const usernameA = process.env.STAGING_TENANT_A_USERNAME;
const passwordA = process.env.STAGING_TENANT_A_PASSWORD;
const usernameB = process.env.STAGING_TENANT_B_USERNAME;
const passwordB = process.env.STAGING_TENANT_B_PASSWORD;
const tenantA = process.env.STAGING_TENANT_A_ID;
const tenantB = process.env.STAGING_TENANT_B_ID;
const branchA = process.env.STAGING_TENANT_A_BRANCH_ID;
const branchB = process.env.STAGING_TENANT_B_BRANCH_ID;
const branchCodeA = process.env.STAGING_TENANT_A_BRANCH_CODE;
const branchCodeB = process.env.STAGING_TENANT_B_BRANCH_CODE;
const userIdA = process.env.STAGING_TENANT_A_USER_ID;
const userIdB = process.env.STAGING_TENANT_B_USER_ID;

const requiredProbes = [
  ["P01", "Tenant A username/password login", "Tenant A", tenantA ?? "unconfigured", branchA ?? "unconfigured", "D'Lice admin-login"],
  ["P02", "Tenant B username/password login", "Tenant B", tenantB ?? "unconfigured", branchB ?? "unconfigured", "D'Lice admin-login"],
  ["P03", "Distinct identities, active tenant memberships, and branch assignments", "Tenant A and Tenant B", `${tenantA ?? "unconfigured"},${tenantB ?? "unconfigured"}`, `${branchA ?? "unconfigured"},${branchB ?? "unconfigured"}`, "Auth user, erp-list-tenant-memberships, and erp-list-branches"],
  ["P04", "Tenant A own-branch inventory read", "Tenant A", tenantA ?? "unconfigured", branchA ?? "unconfigured", "erp-list-inventory"],
  ["P05", "Tenant A cross-tenant inventory read denied", "Tenant A", tenantA ?? "unconfigured", branchB ?? "unconfigured", "erp-list-inventory"],
  ["P06", "Tenant B own-branch inventory read", "Tenant B", tenantB ?? "unconfigured", branchB ?? "unconfigured", "erp-list-inventory"],
  ["P07", "Tenant B cross-tenant inventory read denied", "Tenant B", tenantB ?? "unconfigured", branchA ?? "unconfigured", "erp-list-inventory"],
  ["P08", "Tenant A cross-tenant stock-transfer write denied", "Tenant A", tenantA ?? "unconfigured", branchB ?? "unconfigured", "erp-create-stock-transfer"],
  ["P09", "Tenant B cross-tenant stock-transfer write denied", "Tenant B", tenantB ?? "unconfigured", branchA ?? "unconfigured", "erp-create-stock-transfer"],
];

const results = [];
function recordProbe({
  id,
  authIdentity,
  tenantScope,
  branchScope,
  operation,
  expectedResult,
  actualResult,
  httpStatus = null,
  evidence = {},
  startedAt,
  status,
}) {
  const result = {
    probeId: id,
    authIdentity,
    tenantScope,
    branchScope,
    operation,
    expectedResult,
    actualResult,
    httpStatus,
    evidence,
    durationMs: Math.max(0, Math.round(performance.now() - startedAt)),
    status,
  };
  results.push(result);
  console.log(JSON.stringify(result));
  return result;
}

async function runProbe(definition, authIdentity, operation) {
  const startedAt = performance.now();
  try {
    const outcome = await operation();
    return recordProbe({
      ...definition,
      authIdentity,
      ...outcome,
      startedAt,
      status: outcome.passed ? "PASS" : "FAIL",
    });
  } catch (error) {
    return recordProbe({
      ...definition,
      authIdentity,
      actualResult: `request_error:${error instanceof Error ? error.name : "UnknownError"}`,
      httpStatus: null,
      evidence: { requestCompleted: false },
      startedAt,
      status: "FAIL",
    });
  }
}

function recordBlocked(definition, reason) {
  return recordProbe({
    ...definition,
    authIdentity: definition.authIdentity,
    actualResult: `not_executed:${reason}`,
    httpStatus: null,
    evidence: { executed: false },
    startedAt: performance.now(),
    status: "BLOCKED",
  });
}

function isUuid(value) {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

function isPublicSupabaseKey(value) {
  if (value.startsWith("sb_secret_")) return false;
  const parts = value.split(".");
  if (parts.length !== 3) return /^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(value);
  try {
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    return payload.role === "anon";
  } catch {
    return false;
  }
}

function configurationProblems() {
  const inputs = [
    ["STAGING_SUPABASE_URL", process.env.STAGING_SUPABASE_URL],
    ["STAGING_SUPABASE_PUBLIC_KEY", key],
    ["STAGING_TENANT_A_USERNAME", usernameA],
    ["STAGING_TENANT_A_PASSWORD", passwordA],
    ["STAGING_TENANT_B_USERNAME", usernameB],
    ["STAGING_TENANT_B_PASSWORD", passwordB],
    ["STAGING_TENANT_A_ID", tenantA],
    ["STAGING_TENANT_B_ID", tenantB],
    ["STAGING_TENANT_A_BRANCH_ID", branchA],
    ["STAGING_TENANT_B_BRANCH_ID", branchB],
    ["STAGING_TENANT_A_BRANCH_CODE", branchCodeA],
    ["STAGING_TENANT_B_BRANCH_CODE", branchCodeB],
    ["STAGING_TENANT_A_USER_ID", userIdA],
    ["STAGING_TENANT_B_USER_ID", userIdB],
  ];
  const missingInputNames = inputs.filter(([, value]) => value === undefined).map(([name]) => name);
  const emptyInputNames = inputs.filter(([, value]) => value === "").map(([name]) => name);
  const configurationErrors = [];

  if (base) {
    try {
      const url = new URL(base);
      if (url.protocol !== "https:" || url.hostname !== "higoadrzxnhzbbwhdbmh.supabase.co") {
        configurationErrors.push("STAGING_SUPABASE_URL must target the approved staging project over HTTPS");
      }
    } catch {
      configurationErrors.push("STAGING_SUPABASE_URL is not a valid URL");
    }
  }
  if (key && !isPublicSupabaseKey(key)) {
    configurationErrors.push("STAGING_SUPABASE_PUBLIC_KEY is not a supported public key");
  }
  if (usernameA && usernameB && usernameA.trim().toLowerCase() === usernameB.trim().toLowerCase()) {
    configurationErrors.push("Tenant A and Tenant B usernames must be distinct");
  }
  const fixtureIds = [tenantA, tenantB, branchA, branchB, userIdA, userIdB];
  if (fixtureIds.every((value) => value !== undefined && value !== "")) {
    if (!fixtureIds.every(isUuid)) {
      configurationErrors.push("Tenant, branch, and user fixture identifiers must be UUIDs");
    }
  }
  if (tenantA && tenantB && tenantA === tenantB) {
    configurationErrors.push("Tenant fixture identifiers must be distinct");
  }
  if (branchA && branchB && branchA === branchB) {
    configurationErrors.push("Branch fixture identifiers must be distinct");
  }
  if (userIdA && userIdB && userIdA === userIdB) {
    configurationErrors.push("User fixture identities must be distinct");
  }
  return { missingInputNames, emptyInputNames, configurationErrors };
}

const configuration = configurationProblems();
if (
  configuration.missingInputNames.length ||
  configuration.emptyInputNames.length ||
  configuration.configurationErrors.length
) {
  console.log(JSON.stringify({
    probeId: "CONFIG",
    status: "FAIL",
    missingInputNames: configuration.missingInputNames,
    emptyInputNames: configuration.emptyInputNames,
    configurationErrors: configuration.configurationErrors,
    secretValuesPrinted: false,
  }));
  for (const [id, expectedResult, authIdentity, tenantScope, branchScope, operation] of requiredProbes) {
    recordBlocked({
      id,
      expectedResult,
      authIdentity,
      tenantScope,
      branchScope,
      operation,
    }, "configuration_preflight_failed");
  }
  console.log(JSON.stringify({
    probeId: "SUMMARY",
    status: "FAIL",
    pass: 0,
    fail: 0,
    blocked: requiredProbes.length,
    skipped: 0,
    secretValuesPrinted: false,
  }));
  process.exitCode = 2;
} else {
  console.log(JSON.stringify({
    probeId: "CONFIG",
    status: "PASS",
    missingInputNames: [],
    emptyInputNames: [],
    configurationErrors: [],
    secretValuesPrinted: false,
  }));

  const tokenByTenant = { A: null, B: null };
  const identityByTenant = { A: null, B: null };
  const probeById = new Map(requiredProbes.map((entry) => [entry[0], entry]));

  async function login(tenant) {
    const isTenantA = tenant === "A";
    const id = isTenantA ? "P01" : "P02";
    const [, expectedResult, authIdentity, tenantScope, branchScope, operation] = probeById.get(id);
    await runProbe({
      id,
      expectedResult,
      tenantScope,
      branchScope,
      operation,
    }, authIdentity, async () => {
      const response = await fetch(`${base}/functions/v1/dlice-orders`, {
        method: "POST",
        headers: { apikey: key, "content-type": "application/json" },
        body: JSON.stringify({
          action: "admin-login",
          username: isTenantA ? usernameA : usernameB,
          password: isTenantA ? passwordA : passwordB,
        }),
        redirect: "manual",
      });
      const text = await response.text();
      let payload = null;
      try {
        payload = JSON.parse(text);
      } catch {
        payload = null;
      }
      const token = payload?.session?.access_token;
      const validTokenShape = typeof token === "string" && token.split(".").length === 3 && !token.startsWith("Bearer ");
      const passed = response.ok && validTokenShape;
      if (passed) tokenByTenant[tenant] = token;
      return {
        passed,
        actualResult: passed ? `HTTP ${response.status}; authenticated session returned` : `HTTP ${response.status}; ${token ? "invalid_session_token_shape" : "login_failed_or_session_missing"}`,
        httpStatus: response.status,
        evidence: { responseBodyBytes: text.length, validAccessTokenShape: validTokenShape, tokenPrinted: false },
      };
    });
  }

  async function authorizedRequest(token, path, init = {}) {
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
    let payload = null;
    try {
      payload = JSON.parse(text);
    } catch {
      payload = null;
    }
    return {
      response,
      text,
      payload,
      evidence: {
        responseBodyBytes: text.length,
        responseContentType: response.headers.get("content-type") ?? "unknown",
        responseJson: payload !== null,
      },
    };
  }

  async function verifyIdentityAndMembership() {
    const definition = probeById.get("P03");
    const [, expectedResult, authIdentity, tenantScope, branchScope, operation] = definition;
    if (!tokenByTenant.A || !tokenByTenant.B) {
      recordBlocked({ id: "P03", expectedResult, authIdentity, tenantScope, branchScope, operation }, "one_or_both_logins_failed");
      return;
    }
    await runProbe({ id: "P03", expectedResult, tenantScope, branchScope, operation }, authIdentity, async () => {
      const [
        identityAResult,
        identityBResult,
        membershipAResult,
        membershipBResult,
        branchesAResult,
        branchesBResult,
      ] = await Promise.all([
        authorizedRequest(tokenByTenant.A, "/auth/v1/user"),
        authorizedRequest(tokenByTenant.B, "/auth/v1/user"),
        authorizedRequest(tokenByTenant.A, "/functions/v1/dlice-orders", {
          method: "POST",
          body: JSON.stringify({ action: "erp-list-tenant-memberships" }),
        }),
        authorizedRequest(tokenByTenant.B, "/functions/v1/dlice-orders", {
          method: "POST",
          body: JSON.stringify({ action: "erp-list-tenant-memberships" }),
        }),
        authorizedRequest(tokenByTenant.A, "/functions/v1/dlice-orders", {
          method: "POST",
          body: JSON.stringify({ action: "erp-list-branches" }),
        }),
        authorizedRequest(tokenByTenant.B, "/functions/v1/dlice-orders", {
          method: "POST",
          body: JSON.stringify({ action: "erp-list-branches" }),
        }),
      ]);
      const userA = identityAResult.payload?.id;
      const userB = identityBResult.payload?.id;
      identityByTenant.A = userA ?? null;
      identityByTenant.B = userB ?? null;
      const membershipsA = membershipAResult.payload?.memberships;
      const membershipsB = membershipBResult.payload?.memberships;
      const branchesA = branchesAResult.payload?.branches;
      const branchesB = branchesBResult.payload?.branches;
      const membershipAIsCorrect = Array.isArray(membershipsA) &&
        membershipsA.some((membership) =>
          membership.user_id === userA &&
          membership.tenant_id === tenantA &&
          membership.status === "active"
        ) &&
        !membershipsA.some((membership) => membership.tenant_id === tenantB);
      const membershipBIsCorrect = Array.isArray(membershipsB) &&
        membershipsB.some((membership) =>
          membership.user_id === userB &&
          membership.tenant_id === tenantB &&
          membership.status === "active"
        ) &&
        !membershipsB.some((membership) => membership.tenant_id === tenantA);
      const branchAAssignmentIsCorrect = Array.isArray(branchesA) &&
        branchesA.some((branch) => branch.id === branchA && branch.code === branchCodeA) &&
        !branchesA.some((branch) => branch.id === branchB);
      const branchBAssignmentIsCorrect = Array.isArray(branchesB) &&
        branchesB.some((branch) => branch.id === branchB && branch.code === branchCodeB) &&
        !branchesB.some((branch) => branch.id === branchA);
      const identityMatchesFixtures = userA === userIdA && userB === userIdB && userA !== userB;
      const passed = identityAResult.response.status === 200 &&
        identityBResult.response.status === 200 &&
        membershipAResult.response.status === 200 &&
        membershipBResult.response.status === 200 &&
        branchesAResult.response.status === 200 &&
        branchesBResult.response.status === 200 &&
        identityMatchesFixtures &&
        membershipAIsCorrect &&
        membershipBIsCorrect &&
        branchAAssignmentIsCorrect &&
        branchBAssignmentIsCorrect;
      return {
        passed,
        actualResult: passed
          ? "Both Auth identities, active tenant memberships, and branch assignments match their fixtures"
          : "Identity, active tenant membership, or branch assignment did not match the configured fixture",
        httpStatus: {
          identityA: identityAResult.response.status,
          identityB: identityBResult.response.status,
          tenantAMembership: membershipAResult.response.status,
          tenantBMembership: membershipBResult.response.status,
          tenantABranches: branchesAResult.response.status,
          tenantBBranches: branchesBResult.response.status,
        },
        evidence: {
          identityAUserId: userA ?? null,
          identityBUserId: userB ?? null,
          identityMatchesFixtures,
          membershipAActiveInTenantA: membershipAIsCorrect,
          membershipBActiveInTenantB: membershipBIsCorrect,
          branchAAssignmentMatchesFixture: branchAAssignmentIsCorrect,
          branchBAssignmentMatchesFixture: branchBAssignmentIsCorrect,
        },
      };
    });
  }

  async function verifyOwnBranchRead(tenant) {
    const isTenantA = tenant === "A";
    const id = isTenantA ? "P04" : "P06";
    const [, expectedResult, authIdentity, tenantScope, branchScope, operation] = probeById.get(id);
    const token = tokenByTenant[tenant];
    if (!token || !identityByTenant[tenant]) {
      recordBlocked({ id, expectedResult, authIdentity, tenantScope, branchScope, operation }, "identity_not_verified");
      return;
    }
    await runProbe({ id, expectedResult, tenantScope, branchScope, operation }, `${authIdentity} (${identityByTenant[tenant]})`, async () => {
      const requestedBranch = isTenantA ? branchA : branchB;
      const { response, payload, evidence } = await authorizedRequest(token, "/functions/v1/dlice-orders", {
        method: "POST",
        body: JSON.stringify({ action: "erp-list-inventory", branch_id: requestedBranch }),
      });
      const balances = payload?.balances;
      // Empty inventory is not proof of a working own-branch read. Require at least one real row.
      const validRows = Array.isArray(balances) && balances.length > 0 && balances.every((row) => row.branch_id === requestedBranch);
      const passed = response.status === 200 && validRows;
      return {
        passed,
        actualResult: `HTTP ${response.status}; ${Array.isArray(balances) ? balances.length : "invalid"} inventory rows; branch_scope_matches=${validRows}`,
        httpStatus: response.status,
        evidence: { ...evidence, inventoryRows: Array.isArray(balances) ? balances.length : null, branchScopeMatches: validRows },
      };
    });
  }

  async function verifyCrossTenantRead(tenant) {
    const isTenantA = tenant === "A";
    const id = isTenantA ? "P05" : "P07";
    const [, expectedResult, authIdentity, tenantScope, branchScope, operation] = probeById.get(id);
    const token = tokenByTenant[tenant];
    if (!token || !identityByTenant[tenant]) {
      recordBlocked({ id, expectedResult, authIdentity, tenantScope, branchScope, operation }, "identity_not_verified");
      return;
    }
    await runProbe({ id, expectedResult, tenantScope, branchScope, operation }, `${authIdentity} (${identityByTenant[tenant]})`, async () => {
      const foreignBranch = isTenantA ? branchB : branchA;
      const { response, evidence } = await authorizedRequest(token, "/functions/v1/dlice-orders", {
        method: "POST",
        body: JSON.stringify({ action: "erp-list-inventory", branch_id: foreignBranch }),
      });
      const passed = response.status === 403;
      return {
        passed,
        actualResult: `HTTP ${response.status}; cross-tenant read ${passed ? "denied" : "not denied"}`,
        httpStatus: response.status,
        evidence,
      };
    });
  }

  async function verifyCrossTenantWriteDenied(tenant) {
    const isTenantA = tenant === "A";
    const id = isTenantA ? "P08" : "P09";
    const [, expectedResult, authIdentity, tenantScope, branchScope, operation] = probeById.get(id);
    const token = tokenByTenant[tenant];
    if (!token || !identityByTenant[tenant]) {
      recordBlocked({ id, expectedResult, authIdentity, tenantScope, branchScope, operation }, "identity_not_verified");
      return;
    }
    await runProbe({ id, expectedResult, tenantScope, branchScope, operation }, `${authIdentity} (${identityByTenant[tenant]})`, async () => {
      const ownBranch = isTenantA ? branchA : branchB;
      const foreignBranch = isTenantA ? branchB : branchA;
      const control = await authorizedRequest(token, "/functions/v1/dlice-orders", {
        method: "POST",
        body: JSON.stringify({
          action: "erp-create-stock-transfer",
          transfer_number: `SECURITY-CONTROL-${tenant}-${randomUUID()}`,
          source_branch_id: ownBranch,
          destination_branch_id: ownBranch,
          inventory_item_id: "00000000-0000-4000-8000-000000000099",
          quantity: 1,
          idempotency_key: `tenant-isolation-control-${tenant.toLowerCase()}-${randomUUID()}`,
          notes: "Validation-only control; same-branch transfers must be rejected before mutation",
        }),
      });
      if (control.response.status !== 422) {
        return {
          passed: false,
          actualResult: `Same-branch authorization control returned HTTP ${control.response.status}; cross-tenant write was not used as a permission-only denial signal`,
          httpStatus: control.response.status,
          evidence: { ...control.evidence, writeProbeSkipped: true },
        };
      }
      const idempotencyKey = `tenant-isolation-${tenant.toLowerCase()}-${randomUUID()}`;
      const { response, evidence } = await authorizedRequest(token, "/functions/v1/dlice-orders", {
        method: "POST",
        body: JSON.stringify({
          action: "erp-create-stock-transfer",
          transfer_number: `SECURITY-DENY-${tenant}-${randomUUID()}`,
          source_branch_id: ownBranch,
          destination_branch_id: foreignBranch,
          inventory_item_id: "00000000-0000-4000-8000-000000000099",
          quantity: 1,
          idempotency_key: idempotencyKey,
          notes: "Automated tenant-isolation negative test; must be rejected before mutation",
        }),
      });
      const passed = response.status === 403;
      return {
        passed,
        actualResult: `HTTP ${response.status}; cross-tenant write ${passed ? "denied" : "not denied"}`,
        httpStatus: response.status,
        evidence: {
          ...evidence,
          sameTenantAuthorizationControlStatus: control.response.status,
          sameTenantControlRejectedBeforeMutation: true,
          idempotencyKeyGenerated: true,
          requestIdentifiersPrinted: false,
        },
      };
    });
  }

  async function verifyDirectBranchRlsDenied(tenant, branchKind) {
    const isTenantA = tenant === "A";
    const branchId = branchKind === "own"
      ? (isTenantA ? branchA : branchB)
      : (isTenantA ? branchB : branchA);
    const tenantId = isTenantA ? tenantA : tenantB;
    const authIdentity = isTenantA ? "Tenant A" : "Tenant B";
    const definition = {
      id: `RLS-${tenant}-${branchKind.toUpperCase()}`,
      authIdentity,
      tenantScope: tenantId,
      branchScope: branchId,
      operation: "Direct REST GET /rest/v1/branches",
      expectedResult: "Direct client table access is denied or returns no matching branch row",
    };
    const token = tokenByTenant[tenant];
    if (!token || !identityByTenant[tenant]) {
      recordBlocked(definition, "identity_not_verified");
      return;
    }
    await runProbe(definition, `${authIdentity} (${identityByTenant[tenant]})`, async () => {
      const { response, text, payload, evidence } = await authorizedRequest(
        token,
        `/rest/v1/branches?id=eq.${encodeURIComponent(branchId)}&select=id,tenant_id`,
        { headers: { accept: "application/json" } },
      );
      const matchingBranchReturned = Array.isArray(payload) &&
        payload.some((row) => row.id === branchId);
      const filtered = response.status === 200 &&
        Array.isArray(payload) &&
        !matchingBranchReturned;
      const accessDenied = response.status === 401 || response.status === 403;
      const passed = filtered || accessDenied;
      return {
        passed,
        actualResult: `HTTP ${response.status}; direct row ${passed ? "not exposed" : "exposed or response invalid"}`,
        httpStatus: response.status,
        evidence: { ...evidence, responseBodyBytes: text.length, matchingBranchReturned },
      };
    });
  }

  async function verifyDirectStockTransferRpcDenied(tenant) {
    const isTenantA = tenant === "A";
    const authIdentity = isTenantA ? "Tenant A" : "Tenant B";
    const ownBranch = isTenantA ? branchA : branchB;
    const foreignBranch = isTenantA ? branchB : branchA;
    const definition = {
      id: `RPC-${tenant}-CROSS-TENANT-WRITE`,
      authIdentity,
      tenantScope: isTenantA ? tenantA : tenantB,
      branchScope: foreignBranch,
      operation: "Direct REST POST /rest/v1/rpc/erp_create_stock_transfer",
      expectedResult: "Server-only stock-transfer RPC is inaccessible to the authenticated client",
    };
    const token = tokenByTenant[tenant];
    if (!token || !identityByTenant[tenant]) {
      recordBlocked(definition, "identity_not_verified");
      return;
    }
    await runProbe(definition, `${authIdentity} (${identityByTenant[tenant]})`, async () => {
      const { response, evidence } = await authorizedRequest(
        token,
        "/rest/v1/rpc/erp_create_stock_transfer",
        {
          method: "POST",
          body: JSON.stringify({
            p_transfer_number: `SECURITY-RPC-DENY-${randomUUID()}`,
            p_source_branch_id: ownBranch,
            p_destination_branch_id: foreignBranch,
            p_items: [],
            p_actor_user_id: identityByTenant[tenant],
            p_idempotency_key: `security-rpc-deny-${tenant.toLowerCase()}-${randomUUID()}`,
            p_notes: "Automated negative test; direct client RPC must not execute",
          }),
        },
      );
      const passed = [401, 403, 404, 405].includes(response.status);
      return {
        passed,
        actualResult: `HTTP ${response.status}; direct mutation RPC ${passed ? "inaccessible" : "unexpectedly reachable"}`,
        httpStatus: response.status,
        evidence,
      };
    });
  }

  await login("A");
  await login("B");
  await verifyIdentityAndMembership();
  await verifyOwnBranchRead("A");
  await verifyCrossTenantRead("A");
  await verifyOwnBranchRead("B");
  await verifyCrossTenantRead("B");
  await verifyCrossTenantWriteDenied("A");
  await verifyCrossTenantWriteDenied("B");
  await verifyDirectBranchRlsDenied("A", "own");
  await verifyDirectBranchRlsDenied("A", "foreign");
  await verifyDirectBranchRlsDenied("B", "own");
  await verifyDirectBranchRlsDenied("B", "foreign");
  await verifyDirectStockTransferRpcDenied("A");
  await verifyDirectStockTransferRpcDenied("B");

  const requiredResults = results.filter((result) => /^P\d\d$/.test(result.probeId));
  const supplementalResults = results.filter((result) => !/^P\d\d$/.test(result.probeId));
  const pass = requiredResults.filter((result) => result.status === "PASS").length;
  const fail = results.filter((result) => result.status === "FAIL").length;
  const blocked = results.filter((result) => result.status === "BLOCKED").length;
  const skipped = results.filter((result) => result.status === "SKIPPED").length;
  const allProbesPassed = requiredResults.length === requiredProbes.length &&
    pass === requiredProbes.length &&
    fail === 0 &&
    blocked === 0 &&
    skipped === 0 &&
    supplementalResults.every((result) => result.status === "PASS");
  console.log(JSON.stringify({
    probeId: "SUMMARY",
    status: allProbesPassed ? "PASS" : "FAIL",
    pass,
    fail,
    blocked,
    skipped,
    required: requiredProbes.length,
    supplemental: supplementalResults.length,
    secretValuesPrinted: false,
  }));
  if (!allProbesPassed) process.exitCode = 1;
}
