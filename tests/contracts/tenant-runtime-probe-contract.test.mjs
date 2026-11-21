import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const workflow = readFileSync(".github/workflows/staging-tenant-isolation-acceptance.yml", "utf8");
const probe = readFileSync("tests/runtime/dlice-tenant-jwt-isolation.mjs", "utf8");
const edgeSource = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");

test("staging tenant gate is manually dispatched from trusted staging and discovers fixture UUIDs from authenticated membership and branch responses", () => {
  const triggers = workflow.split(/^permissions:\s*$/m, 1)[0];
  assert.match(workflow, /^\s+environment:\s*staging\s*$/m);
  assert.match(triggers, /^  workflow_dispatch:\s*$/m);
  assert.doesNotMatch(triggers, /^  push:/m, "runtime acceptance must not run automatically before Environment preflight is confirmed");
  assert.match(workflow, /if:\s*github\.ref\s*==\s*'refs\/heads\/staging'/);
  assert.doesNotMatch(triggers, /\bpull_request\b/);
  for (const secret of [
    "STAGING_SUPABASE_URL",
    "STAGING_SUPABASE_SERVICE_ROLE_KEY",
  ]) {
    assert.match(workflow, new RegExp(`${secret}:\\s*\\$\\{\\{\\s*secrets\\.${secret}\\s*\\}\\}`));
  }
  assert.match(workflow, /STAGING_TENANT_A_EMAIL:\\s*dlice8888@accounts\\.dlice\\.internal/);
  assert.match(workflow, /STAGING_TENANT_B_EMAIL:\\s*qa_dlice_staging_branch_a@accounts\\.dlice\\.internal/);
  assert.doesNotMatch(workflow, /STAGING_TENANT_[AB]_(?:USERNAME|PASSWORD)/);
  assert.match(workflow, /STAGING_SUPABASE_ANON_KEY:\s*\$\{\{\s*secrets\.STAGING_SUPABASE_PUBLIC_KEY\s*\}\}/);
  assert.doesNotMatch(workflow, /secrets\.STAGING_TEST_/);
  assert.doesNotMatch(workflow, /vars\.STAGING_TENANT_(?:A|B)_(?:ID|USER_ID|BRANCH_ID)/);
  assert.match(workflow, /STAGING_TENANT_A_BRANCH_CODE:\s*QA-DLICE-A/);
  assert.match(workflow, /STAGING_TENANT_B_BRANCH_CODE:\s*QA-TENANT-B/);
  assert.match(workflow, /^name:\s*Staging Tenant Isolation Acceptance$/m);
  assert.doesNotMatch(triggers, /pull_request/);
  assert.match(workflow, /Summarize P01-P09 and configuration preflight/);
  assert.match(workflow, /staging-tenant-isolation-evidence\.jsonl/);
});

test("runtime tenant gate records every required probe and validates active tenant memberships", () => {
  for (const id of ["P01", "P02", "P03", "P04", "P05", "P06", "P07", "P08", "P09"]) {
    assert.ok(probe.includes(`"${id}"`), `missing required probe ${id}`);
  }
  for (const field of [
    "authIdentity",
    "tenantScope",
    "branchScope",
    "operation",
    "expectedResult",
    "actualResult",
    "httpStatus",
    "evidence",
    "durationMs",
    "status",
  ]) {
    assert.ok(probe.includes(field), `probe evidence is missing ${field}`);
  }
  assert.match(probe, /erp-list-tenant-memberships/);
  assert.match(probe, /Array\.isArray\(balances\)\s*&&\s*balances\.every\(\(row\)\s*=>\s*row\.branch_id\s*===\s*requestedBranch\)/, "own-branch read must accept an empty authorized result but reject any foreign-branch row");
  assert.doesNotMatch(probe, /balances\.length\s*>\s*0/, "empty stock must not be misreported as an authorization failure");
  assert.match(probe, /resolveTenantFixtures/);
  const fixtureResolver = readFileSync("tests/runtime/tenant-fixture-discovery.mjs", "utf8");
  assert.match(fixtureResolver, /membership\?\.status\s*===\s*["']active["']/);
  assert.match(probe, /executed:\s*true/);
  assert.match(probe, /executed:\s*false/);
  assert.match(probe, /BLOCKED/);
  assert.match(probe, /secretValuesPrinted:\s*false/);
  assert.match(probe, /valuePrinted:\s*false/);
  assert.match(probe, /timestamp:\s*new Date\(\)\.toISOString\(\)/);
  assert.doesNotMatch(probe, /console\.(?:log|error)\([^)]*(?:tokenA|tokenB|passwordA|passwordB)/);
  assert.match(probe, /auth\/v1\/admin\/generate_link/);
  assert.match(probe, /auth\/v1\/verify/);
  assert.match(probe, /type:\s*["']magiclink["']/);
  assert.match(probe, /auth\/v1\/logout/);
  assert.match(probe, /STAGING_SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(probe, /STAGING_TENANT_[AB]_(?:USERNAME|PASSWORD)/);
});


test("tenant membership lookup is actor-self-scoped and independent of global branch permission", () => {
  const start = edgeSource.indexOf('if (action === "erp-list-tenant-memberships")');
  const end = edgeSource.indexOf('if (action === "erp-create-tenant")', start);
  assert.ok(start >= 0 && end > start, "membership handler must exist");
  const handler = edgeSource.slice(start, end);
  assert.doesNotMatch(handler, /hasPerm\(["']branches["']\)|isOwner/, "self membership lookup must not require global branch permission");
  assert.match(handler, /\.eq\(["']user_id["'],\s*actor\.user\.id\)/);
  assert.match(handler, /\.eq\(["']status["'],\s*["']active["']\)/);
  assert.doesNotMatch(handler, /body\.user_id|body\.tenant_id/, "caller must not select another identity or tenant");
});

test("missing staging configuration is reported as blocked, never as a passing probe", () => {
  const result = spawnSync(process.execPath, ["tests/runtime/dlice-tenant-jwt-isolation.mjs"], {
    encoding: "utf8",
    env: { PATH: process.env.PATH ?? "" },
  });
  assert.equal(result.status, 2);
  const records = `${result.stdout}\n${result.stderr}`.split(/\r?\n/).flatMap((line) => {
    try { return [JSON.parse(line)]; } catch { return []; }
  });
  const probes = records.filter((record) => /^P\d\d$/.test(record.probeId));
  assert.equal(probes.length, 9);
  assert.ok(probes.every((record) => record.status === "BLOCKED"));
  const preflight = records.filter((record) => record.probeId === "PREFLIGHT");
  assert.equal(preflight.length, 7);
  assert.ok(preflight.every((record) => record.valuePrinted === false));
  assert.ok(preflight.every((record) => record.status === "FAIL"));
  const summary = records.find((record) => record.probeId === "SUMMARY");
  assert.equal(summary.pass, 0);
  assert.equal(summary.blocked, 9);
  assert.equal(summary.skipped, 0);
  assert.equal(summary.secretValuesPrinted, false);
});

test("inventory reads authorize the requested branch before any data query and scope balances to that branch", () => {
  const start = edgeSource.indexOf('if (action === "erp-list-inventory")');
  const end = edgeSource.indexOf('if (action === "erp-save-inventory")', start);
  assert.ok(start >= 0 && end > start, "inventory list handler must exist");
  const handler = edgeSource.slice(start, end);
  const authorization = handler.indexOf("await branchAccess(branchId)");
  const firstDataQuery = handler.indexOf('admin.from("inventory_items")');
  const balancesQuery = handler.indexOf('admin.from("branch_inventory")');
  assert.ok(authorization >= 0, "requested branch must be authorized");
  assert.ok(firstDataQuery > authorization, "no inventory data may be queried before branch authorization");
  assert.ok(balancesQuery > authorization, "branch balances may only be queried after branch authorization");
  assert.match(handler, /\.eq\(["']branch_id["'],\s*branchId\s*\)/,
    "balance query must be restricted to the explicitly authorized branch");
  assert.match(handler, /inventoryItemIds[\s\S]*?\.in\(["']id["'],\s*inventoryItemIds\s*\)/,
    "shared inventory metadata must be restricted to items stocked in the authorized branch");
  assert.match(handler, /select\(["']id,sku,name,unit,category,min_stock,is_active["']\)/,
    "the shared inventory master query must return only its approved catalog fields");
  assert.match(handler, /if\(!branchId\|\|!await branchAccess\(branchId\)\)return fail\([^;]+403/,
    "missing or foreign-tenant branch reads must be rejected before catalog or balance queries");
});


test("P03 requires supported global sales_admin profiles, branch_manager tenant memberships, equal permissions, and allows multiple same-tenant branches", () => {
  assert.ok(edgeSource.includes("admin_profiles(display_name,username,role)"));
  // Global console role and tenant-scoped membership role are separate parts of the actual app model.
  const fixtureResolver = readFileSync("tests/runtime/tenant-fixture-discovery.mjs", "utf8");
  assert.ok(fixtureResolver.includes('membershipA?.admin_profiles?.role === "sales_admin"'));
  assert.ok(fixtureResolver.includes('membershipB?.admin_profiles?.role === "sales_admin"'));
  assert.ok(fixtureResolver.includes('membershipA?.role === "branch_manager"'));
  assert.ok(fixtureResolver.includes('membershipB?.role === membershipA.role'));
  assert.ok(fixtureResolver.includes("sameTenantRole"));
  assert.ok(fixtureResolver.includes("permissionSetsEqual"));
  assert.ok(fixtureResolver.includes("list(branchesA).every((branch) => branch?.tenant_id === tenantA)"));
  assert.ok(fixtureResolver.includes("list(branchesB).every((branch) => branch?.tenant_id === tenantB)"));
  assert.ok(!fixtureResolver.includes("branchesA.length === 1") && !fixtureResolver.includes("branchesB.length === 1"),
    "additional same-tenant assignments must not fail the worker acceptance test");
});

test("runtime probe evidence masks user, tenant, and branch identifiers in every probe", () => {
  assert.ok(probe.includes("const maskId ="));
  assert.ok(probe.includes("resolveTenantFixtures"));
  assert.doesNotMatch(probe, /STAGING_TENANT_[AB]_(?:ID|USER_ID|BRANCH_ID)/);
  assert.ok(probe.includes("maskId(tenantA)"));
  assert.ok(probe.includes("maskId(branchA)"));
  assert.ok(probe.includes("maskId(tenantB)"));
  assert.ok(probe.includes("maskId(branchB)"));
  assert.ok(probe.includes("identityAUserIdMasked: maskId(userA)"));
  assert.ok(probe.includes("identityBUserIdMasked: maskId(userB)"));
  assert.ok(!probe.includes("identityAUserId: userA") && !probe.includes("identityBUserId: userB"));
  const definitions = probe.slice(probe.indexOf("const requiredProbes = ["), probe.indexOf("];", probe.indexOf("const requiredProbes = [")));
  assert.doesNotMatch(definitions, /tenantA \?\?|tenantB \?\?|branchA \?\?|branchB \?\?/);
});
