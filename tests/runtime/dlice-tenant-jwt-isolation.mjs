// Authenticated tenant-boundary probes for staging Supabase Data API.
// Credentials are accepted only from the trusted staging GitHub Environment.
// Tokens, passwords, usernames, and response bodies are never written to logs.
import { randomUUID } from "node:crypto";
import { performance } from "node:perf_hooks";
import { resolveTenantFixtures } from "./tenant-fixture-discovery.mjs";

const base = process.env.STAGING_SUPABASE_URL?.replace(/\/$/, "");
const key = process.env.STAGING_SUPABASE_ANON_KEY;
const serviceRoleKey = process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY;
const emailA = process.env.STAGING_TENANT_A_EMAIL;
const emailB = process.env.STAGING_TENANT_B_EMAIL;
let tenantA = null;
let tenantB = null;
let branchA = null;
let branchB = null;
let tenantFixturesVerified = false;
const branchCodeA = process.env.STAGING_TENANT_A_BRANCH_CODE;
const branchCodeB = process.env.STAGING_TENANT_B_BRANCH_CODE;
const maskId = (value) => typeof value === "string" && value.length >= 4 ? `…${value.slice(-4)}` : "unconfigured";

const requiredProbes = [
  ["P01", "Tenant A existing Supabase Auth magic-link session", "Tenant A", "resolved from authenticated identity", branchCodeA, "Auth Admin generateLink + verify OTP"],
  ["P02", "Tenant B existing Supabase Auth magic-link session", "Tenant B", "resolved from authenticated identity", branchCodeB, "Auth Admin generateLink + verify OTP"],
  ["P03", "Distinct identities, active tenant memberships, and branch assignments", "Tenant A and Tenant B", `${maskId(tenantA)},${maskId(tenantB)}`, `${maskId(branchA)},${maskId(branchB)}`, "Auth user, erp-list-tenant-memberships, and erp-list-branches"],
  ["P04", "Tenant A own-branch inventory read", "Tenant A", maskId(tenantA), maskId(branchA), "erp-list-inventory"],
  ["P05", "Tenant A cross-tenant inventory read denied", "Tenant A", maskId(tenantA), maskId(branchB), "erp-list-inventory"],
  ["P06", "Tenant B own-branch inventory read", "Tenant B", maskId(tenantB), maskId(branchB), "erp-list-inventory"],
  ["P07", "Tenant B cross-tenant inventory read denied", "Tenant B", maskId(tenantB), maskId(branchA), "erp-list-inventory"],
  ["P08", "Tenant A cross-tenant stock-transfer write denied", "Tenant A", maskId(tenantA), maskId(branchB), "erp-create-stock-transfer"],
  ["P09", "Tenant B cross-tenant stock-transfer write denied", "Tenant B", maskId(tenantB), maskId(branchA), "erp-create-stock-transfer"],
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
  executed = true,
}) {
  const result = {
    probeId: id,
    timestamp: new Date().toISOString(),
    authIdentity,
    tenantScope,
    branchScope,
    operation,
    expectedResult,
    actualResult,
    httpStatus,
    evidence,
    durationMs: Math.max(0, Math.round(performance.now() - startedAt)),
    executed,
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
    executed: false,
    startedAt: performance.now(),
    status: "BLOCKED",
  });
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

function isServiceRoleKey(value) {
  if (value.startsWith("sb_secret_")) return true;
  const parts = value.split(".");
  if (parts.length !== 3) return false;
  try {
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    return payload.role === "service_role";
  } catch {
    return false;
  }
}

function configurationProblems() {
  const inputs = [
    ["STAGING_SUPABASE_URL", process.env.STAGING_SUPABASE_URL],
    ["STAGING_SUPABASE_PUBLIC_KEY", key],
    ["STAGING_SUPABASE_SERVICE_ROLE_KEY", serviceRoleKey],
    ["STAGING_TENANT_A_EMAIL", emailA],
    ["STAGING_TENANT_B_EMAIL", emailB],
    ["STAGING_TENANT_A_BRANCH_CODE", branchCodeA],
    ["STAGING_TENANT_B_BRANCH_CODE", branchCodeB],
  ];
  const missingInputNames = inputs.filter(([, value]) => value === undefined).map(([name]) => name);
  const emptyInputNames = inputs.filter(([, value]) => typeof value === "string" && value.trim() === "").map(([name]) => name);
  const configurationErrors = [];
  const distinctEmails = emailA?.trim().toLowerCase() !== emailB?.trim().toLowerCase();
  const distinctBranchCodes = branchCodeA !== branchCodeB;
  const checks = inputs.map(([name, value]) => {
    let valid = typeof value === "string" && value.trim().length > 0;
    if (valid && name === "STAGING_SUPABASE_URL") {
      try {
        const url = new URL(value);
        valid = url.protocol === "https:" &&
          url.hostname === "higoadrzxnhzbbwhdbmh.supabase.co" &&
          url.pathname === "/" &&
          !url.search &&
          !url.hash;
      } catch {
        valid = false;
      }
    } else if (valid && name === "STAGING_SUPABASE_PUBLIC_KEY") {
      valid = isPublicSupabaseKey(value);
    } else if (valid && name === "STAGING_SUPABASE_SERVICE_ROLE_KEY") {
      valid = isServiceRoleKey(value);
    } else if (valid && name.endsWith("_EMAIL")) {
      valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim()) && distinctEmails;
    } else if (valid && name.endsWith("_BRANCH_CODE")) {
      valid = value === (name === "STAGING_TENANT_A_BRANCH_CODE" ? "QA-DLICE-A" : "QA-TENANT-B") && distinctBranchCodes;
    }
    return { name, status: valid ? "PASS" : "FAIL" };
  });

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
  if (emailA && emailB && !distinctEmails) {
    configurationErrors.push("Tenant A and Tenant B Auth emails must be distinct");
  }
  if (serviceRoleKey && !isServiceRoleKey(serviceRoleKey)) {
    configurationErrors.push("STAGING_SUPABASE_SERVICE_ROLE_KEY is not a supported Supabase service-role key");
  }
  if (branchCodeA && branchCodeB && !distinctBranchCodes) {
    configurationErrors.push("Tenant A and Tenant B branch codes must be distinct");
  }
  return { missingInputNames, emptyInputNames, configurationErrors, checks };
}
const configuration = configurationProblems();
for (const check of configuration.checks) {
  console.log(JSON.stringify({ probeId: "PREFLIGHT", ...check, valuePrinted: false }));
}
if (
  configuration.missingInputNames.length ||
  configuration.emptyInputNames.length ||
  configuration.configurationErrors.length ||
  configuration.checks.some((check) => check.status !== "PASS")
) {
  console.log(JSON.stringify({
    probeId: "CONFIG",
    timestamp: new Date().toISOString(),
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
    timestamp: new Date().toISOString(),
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
    timestamp: new Date().toISOString(),
    status: "PASS",
    missingInputNames: [],
    emptyInputNames: [],
    configurationErrors: [],
    secretValuesPrinted: false,
  }));

  const tokenByTenant = { A: null, B: null };
  const identityByTenant = { A: null, B: null };
  const probeById = new Map(requiredProbes.map((entry) => [entry[0], entry]));
  function refreshProbeScopes() {
    const scopes = {
      P03: [`${maskId(tenantA)},${maskId(tenantB)}`, `${maskId(branchA)},${maskId(branchB)}`],
      P04: [maskId(tenantA), maskId(branchA)],
      P05: [maskId(tenantA), maskId(branchB)],
      P06: [maskId(tenantB), maskId(branchB)],
      P07: [maskId(tenantB), maskId(branchA)],
      P08: [maskId(tenantA), maskId(branchB)],
      P09: [maskId(tenantB), maskId(branchA)],
    };
    for (const [id, [tenantScope, branchScope]] of Object.entries(scopes)) {
      const entry = probeById.get(id);
      if (entry) {
        entry[3] = tenantScope;
        entry[4] = branchScope;
      }
    }
  }

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
      const email = isTenantA ? emailA : emailB;
      const generated = await fetch(`${base}/auth/v1/admin/generate_link`, {
        method: "POST",
        headers: {
          apikey: serviceRoleKey,
          authorization: `Bearer ${serviceRoleKey}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ type: "magiclink", email }),
        redirect: "manual",
      });
      const generatedText = await generated.text();
      let generatedPayload = null;
      try { generatedPayload = JSON.parse(generatedText); } catch { generatedPayload = null; }
      const tokenHash = generatedPayload?.properties?.hashed_token ??
        generatedPayload?.hashed_token ??
        generatedPayload?.data?.properties?.hashed_token ??
        null;
      const verificationType = generatedPayload?.properties?.verification_type ??
        generatedPayload?.verification_type ??
        "magiclink";
      if (!generated.ok || typeof tokenHash !== "string" || tokenHash.length < 20) {
        return {
          passed: false,
          actualResult: `Auth Admin generateLink returned HTTP ${generated.status}; no token was logged`,
          httpStatus: generated.status,
          evidence: { generateLinkResponseBytes: generatedText.length, tokenPrinted: false },
        };
      }

      const verified = await fetch(`${base}/auth/v1/verify`, {
        method: "POST",
        headers: { apikey: key, "content-type": "application/json" },
        body: JSON.stringify({ type: verificationType, token_hash: tokenHash }),
        redirect: "manual",
      });
      const verifiedText = await verified.text();
      let payload = null;
      try { payload = JSON.parse(verifiedText); } catch { payload = null; }
      const token = payload?.access_token ?? payload?.session?.access_token;
      const userId = payload?.user?.id ?? payload?.session?.user?.id;
      const returnedEmail = String(payload?.user?.email ?? payload?.session?.user?.email ?? "").toLowerCase();
      const validTokenShape = typeof token === "string" && token.split(".").length === 3 && !token.startsWith("Bearer ");
      const identityMatches = returnedEmail === email.toLowerCase();
      const passed = verified.ok && validTokenShape && identityMatches && typeof userId === "string";
      if (passed) {
        tokenByTenant[tenant] = token;
        identityByTenant[tenant] = userId;
      }
      return {
        passed,
        actualResult: passed
          ? `HTTP ${verified.status}; existing Supabase Auth identity authenticated by one-time magic link`
          : `Auth verify returned HTTP ${verified.status}; session or identity mismatch`,
        httpStatus: verified.status,
        evidence: {
          generateLinkHttpStatus: generated.status,
          validAccessTokenShape: validTokenShape,
          identityEmailMatched: identityMatches,
          userIdMasked: maskId(userId),
          tokenPrinted: false,
          responseBodyBytes: verifiedText.length,
        },
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
    const definition = {
      id: "P03",
      expectedResult: "Two distinct Auth identities have active memberships and branch assignments in separate tenants",
      authIdentity: "Tenant A and Tenant B",
      tenantScope: "derived after authenticated membership lookup",
      branchScope: "derived after authenticated branch lookup",
      operation: "Auth user, erp-list-tenant-memberships, and erp-list-branches",
    };
    if (!tokenByTenant.A || !tokenByTenant.B) {
      recordBlocked(definition, "one_or_both_logins_failed");
      return;
    }
    await runProbe(definition, definition.authIdentity, async () => {
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
      const resolved = resolveTenantFixtures({
        userA,
        userB,
        membershipsA: membershipAResult.payload?.memberships,
        membershipsB: membershipBResult.payload?.memberships,
        branchesA: branchesAResult.payload?.branches,
        branchesB: branchesBResult.payload?.branches,
        branchCodeA,
        branchCodeB,
      });
      tenantA = resolved.tenantA;
      tenantB = resolved.tenantB;
      branchA = resolved.branchA;
      branchB = resolved.branchB;
      const responsesOk = identityAResult.response.status === 200 &&
        identityBResult.response.status === 200 &&
        membershipAResult.response.status === 200 &&
        membershipBResult.response.status === 200 &&
        branchesAResult.response.status === 200 &&
        branchesBResult.response.status === 200;
      tenantFixturesVerified = responsesOk && resolved.passed;
      refreshProbeScopes();
      definition.tenantScope = `${maskId(tenantA)},${maskId(tenantB)}`;
      definition.branchScope = `${maskId(branchA)},${maskId(branchB)}`;

      const passed = tenantFixturesVerified;
      return {
        passed,
        actualResult: passed
          ? "Both Auth identities, active tenant memberships, and QA branch assignments resolve to separate tenants"
          : "Auth identity, tenant membership, role, permissions, or QA branch resolution did not satisfy the two-tenant fixture contract",
        httpStatus: {
          identityA: identityAResult.response.status,
          identityB: identityBResult.response.status,
          tenantAMembership: membershipAResult.response.status,
          tenantBMembership: membershipBResult.response.status,
          tenantABranches: branchesAResult.response.status,
          tenantBBranches: branchesBResult.response.status,
        },
        evidence: {
          identityAUserIdMasked: maskId(userA),
          identityBUserIdMasked: maskId(userB),
          identityMatchesFixtures: resolved.identityMatchesFixtures,
          tenantIdsDistinct: resolved.tenantIdsDistinct,
          branchIdsDistinct: resolved.branchIdsDistinct,
          membershipAActiveInTenantA: resolved.membershipAIsCorrect,
          membershipBActiveInTenantB: resolved.membershipBIsCorrect,
          profileAHasSupportedRole: resolved.profileAHasSupportedRole,
          profileBHasSupportedRole: resolved.profileBHasSupportedRole,
          tenantRoleA: resolved.membershipA?.role ?? null,
          tenantRoleB: resolved.membershipB?.role ?? null,
          sameTenantRole: resolved.sameTenantRole,
          permissionSetsEqual: resolved.permissionSetsEqual,
          permissionCountA: resolved.permissionsA.length,
          permissionCountB: resolved.permissionsB.length,
          branchAAssignmentMatchesFixture: resolved.branchAAssignmentIsCorrect,
          branchBAssignmentMatchesFixture: resolved.branchBAssignmentIsCorrect,
          qaBranchMatchCounts: resolved.branchMatchCounts,
          fixtureIdsDerivedAtRuntime: true,
        },
      };
    });
  }
  async function verifyOwnBranchRead(tenant) {
    const isTenantA = tenant === "A";
    const id = isTenantA ? "P04" : "P06";
    const [, expectedResult, authIdentity, tenantScope, branchScope, operation] = probeById.get(id);
    const token = tokenByTenant[tenant];
    if (!token || !identityByTenant[tenant] || !tenantFixturesVerified) {
      recordBlocked({ id, expectedResult, authIdentity, tenantScope, branchScope, operation }, "identity_or_tenant_fixture_not_verified");
      return;
    }
    await runProbe({ id, expectedResult, tenantScope, branchScope, operation }, `${authIdentity} (${maskId(identityByTenant[tenant])})`, async () => {
      const requestedBranch = isTenantA ? branchA : branchB;
      const { response, payload, evidence } = await authorizedRequest(token, "/functions/v1/dlice-orders", {
        method: "POST",
        body: JSON.stringify({ action: "erp-list-inventory", branch_id: requestedBranch }),
      });
      const balances = payload?.balances;
      // A successful authorized response with an empty array is still a valid read; do not confuse empty QA stock with an authorization failure.
      const validRows = Array.isArray(balances) && balances.every((row) => row.branch_id === requestedBranch);
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
    if (!token || !identityByTenant[tenant] || !tenantFixturesVerified) {
      recordBlocked({ id, expectedResult, authIdentity, tenantScope, branchScope, operation }, "identity_or_tenant_fixture_not_verified");
      return;
    }
    await runProbe({ id, expectedResult, tenantScope, branchScope, operation }, `${authIdentity} (${maskId(identityByTenant[tenant])})`, async () => {
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
    if (!token || !identityByTenant[tenant] || !tenantFixturesVerified) {
      recordBlocked({ id, expectedResult, authIdentity, tenantScope, branchScope, operation }, "identity_or_tenant_fixture_not_verified");
      return;
    }
    await runProbe({ id, expectedResult, tenantScope, branchScope, operation }, `${authIdentity} (${maskId(identityByTenant[tenant])})`, async () => {
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
      tenantScope: maskId(tenantId),
      branchScope: maskId(branchId),
      operation: "Direct REST GET /rest/v1/branches",
      expectedResult: "Direct client table access is denied or returns no matching branch row",
    };
    const token = tokenByTenant[tenant];
    if (!token || !identityByTenant[tenant] || !tenantFixturesVerified) {
      recordBlocked(definition, "identity_or_tenant_fixture_not_verified");
      return;
    }
    await runProbe(definition, `${authIdentity} (${maskId(identityByTenant[tenant])})`, async () => {
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
      tenantScope: maskId(isTenantA ? tenantA : tenantB),
      branchScope: maskId(foreignBranch),
      operation: "Direct REST POST /rest/v1/rpc/erp_create_stock_transfer",
      expectedResult: "Server-only stock-transfer RPC is inaccessible to the authenticated client",
    };
    const token = tokenByTenant[tenant];
    if (!token || !identityByTenant[tenant] || !tenantFixturesVerified) {
      recordBlocked(definition, "identity_or_tenant_fixture_not_verified");
      return;
    }
    await runProbe(definition, `${authIdentity} (${maskId(identityByTenant[tenant])})`, async () => {
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

  // Revoke both temporary sessions after all probes; never print tokens or response bodies.
  for (const tenant of ["A", "B"]) {
    const token = tokenByTenant[tenant];
    if (!token) continue;
    try {
      const response = await fetch(`${base}/auth/v1/logout`, {
        method: "POST",
        headers: {
          apikey: key,
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
      });
      console.log(JSON.stringify({
        probeId: `CLEANUP-${tenant}`,
        status: response.ok ? "PASS" : "FAIL",
        actualResult: `temporary Auth session revocation HTTP ${response.status}`,
        tokenPrinted: false,
      }));
      if (!response.ok) results.push({
        probeId: `CLEANUP-${tenant}`,
        status: "FAIL",
      });
    } catch {
      results.push({ probeId: `CLEANUP-${tenant}`, status: "FAIL" });
    }
  }

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
    timestamp: new Date().toISOString(),
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
