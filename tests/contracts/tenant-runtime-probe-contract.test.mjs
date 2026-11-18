import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const workflow = readFileSync(".github/workflows/staging-tenant-isolation-acceptance.yml", "utf8");
const probe = readFileSync("tests/runtime/dlice-tenant-jwt-isolation.mjs", "utf8");
const edgeSource = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");

test("staging tenant gate uses only the six canonical credentials and the verified identities", () => {
  const triggers = workflow.split(/^permissions:\s*$/m, 1)[0];
  assert.match(workflow, /^\s+environment:\s*staging\s*$/m);
  assert.match(triggers, /^  workflow_dispatch:\s*$/m);
  assert.match(triggers, /^  push:\s*\n\s+branches:\s*\[staging\]/m);
  assert.match(workflow, /if:\s*github\.ref\s*==\s*'refs\/heads\/staging'/);
  assert.doesNotMatch(triggers, /\bpull_request\b/);
  for (const secret of [
    "STAGING_SUPABASE_URL",
    "STAGING_TENANT_A_USERNAME",
    "STAGING_TENANT_A_PASSWORD",
    "STAGING_TENANT_B_USERNAME",
    "STAGING_TENANT_B_PASSWORD",
  ]) {
    assert.match(workflow, new RegExp(`${secret}:\\s*\\$\\{\\{\\s*secrets\\.${secret}\\s*\\}\\}`));
  }
  assert.match(workflow, /STAGING_SUPABASE_ANON_KEY:\s*\$\{\{\s*secrets\.STAGING_SUPABASE_PUBLIC_KEY\s*\}\}/);
  assert.doesNotMatch(workflow, /secrets\.STAGING_TEST_/);
  assert.match(workflow, /STAGING_TENANT_A_USER_ID:\s*\$\{\{\s*vars\.STAGING_TENANT_A_USER_ID\s*\}\}/);
  assert.match(workflow, /STAGING_TENANT_B_USER_ID:\s*\$\{\{\s*vars\.STAGING_TENANT_B_USER_ID\s*\}\}/);
  assert.match(workflow, /STAGING_TENANT_A_BRANCH_ID:\s*\$\{\{\s*vars\.STAGING_TENANT_A_BRANCH_ID\s*\}\}/);
  assert.match(workflow, /STAGING_TENANT_B_BRANCH_ID:\s*\$\{\{\s*vars\.STAGING_TENANT_B_BRANCH_ID\s*\}\}/);
  assert.match(workflow, /STAGING_TENANT_A_ID:\s*\$\{\{\s*vars\.STAGING_TENANT_A_ID\s*\}\}/);
  assert.match(workflow, /STAGING_TENANT_B_ID:\s*\$\{\{\s*vars\.STAGING_TENANT_B_ID\s*\}\}/);
  assert.match(workflow, /STAGING_TENANT_A_BRANCH_CODE:\s*QA-DLICE-A/);
  assert.match(workflow, /STAGING_TENANT_B_BRANCH_CODE:\s*QA-TENANT-B/);
  assert.match(workflow, /^name:\s*Staging Tenant Isolation Acceptance$/m);
  assert.doesNotMatch(triggers, /pull_request/);
  assert.match(workflow, /STAGING_TENANT_A_BRANCH_ID:\s*\$\{\{\s*vars\.STAGING_TENANT_A_BRANCH_ID\s*\}\}/);
  assert.match(workflow, /STAGING_TENANT_B_BRANCH_ID:\s*\$\{\{\s*vars\.STAGING_TENANT_B_BRANCH_ID\s*\}\}/);
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
  assert.match(probe, /balances\.length\s*>\s*0/, "own-branch read must prove at least one real inventory row");
  assert.match(probe, /status\s*===?\s*["']active["']/);
  assert.match(probe, /BLOCKED/);
  assert.match(probe, /secretValuesPrinted:\s*false/);
  assert.match(probe, /valuePrinted:\s*false/);
  assert.match(probe, /timestamp:\s*new Date\(\)\.toISOString\(\)/);
  assert.doesNotMatch(probe, /console\.(?:log|error)\([^)]*(?:tokenA|tokenB|passwordA|passwordB)/);
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
  assert.equal(preflight.length, 14);
  assert.ok(preflight.every((record) => record.valuePrinted === false));
  assert.ok(preflight.every((record) => record.status === "FAIL"));
  const summary = records.find((record) => record.probeId === "SUMMARY");
  assert.equal(summary.pass, 0);
  assert.equal(summary.blocked, 9);
  assert.equal(summary.skipped, 0);
  assert.equal(summary.secretValuesPrinted, false);
});

test("inventory list is enabled for scoped worker reads while global inventory writes remain gated", () => {
  const denylistStart = edgeSource.indexOf("const TENANT_SCOPE_UNCERTIFIED_ACTIONS = new Set([");
  const denylistEnd = edgeSource.indexOf("]);", denylistStart);
  assert.ok(denylistStart >= 0 && denylistEnd > denylistStart, "tenant denylist must exist");
  const denylist = edgeSource.slice(denylistStart, denylistEnd);
  assert.doesNotMatch(denylist, /"erp-list-inventory"/, "own-branch inventory reads must be eligible for explicit branch authorization");
  assert.match(denylist, /"erp-save-inventory"/, "global inventory master writes remain closed until tenant ownership is modeled");
});

test("inventory reads require and authorize a branch, then return only that branch's inventory rows", () => {
  const start = edgeSource.indexOf('if (action === "erp-list-inventory")');
  const end = edgeSource.indexOf('if (action === "erp-save-inventory")', start);
  assert.ok(start >= 0 && end > start, "inventory list handler must exist");
  const handler = edgeSource.slice(start, end);
  const requiredBranch = handler.indexOf("if(!branchId)");
  const authorization = handler.indexOf("await branchAccess(branchId)");
  const branchQuery = handler.indexOf('admin.from("branch_inventory")');
  assert.ok(requiredBranch >= 0 && requiredBranch < authorization, "branch_id is mandatory before authorization");
  assert.match(handler, /return fail\("Cabang wajib dipilih untuk melihat persediaan\.",422/);
  assert.ok(authorization > requiredBranch && authorization < branchQuery, "branch authorization must precede every data query");
  assert.match(handler, /return fail\("Akses cabang tidak diizinkan\.",403/);
  assert.doesNotMatch(handler, /admin\.from\("inventory_items"\)/, "never enumerate the global inventory master for a tenant-scoped read");
  assert.match(handler, /inventory_items!branch_inventory_inventory_item_id_fkey\(/, "items must be joined only through the selected branch's stock rows");
  assert.match(handler, /\.eq\("branch_id",branchId\)/, "stock rows must be filtered to the authorized branch");
  assert.match(handler, /const items=scopedRows\.map\(/, "returned items must be derived from scoped branch rows");
  assert.match(handler, /const balances=scopedRows\.map\(/, "returned balances must be derived from the same scoped rows");

  const accessStart = edgeSource.indexOf("const branchAccess = async");
  const accessEnd = edgeSource.indexOf("const branchIdsForActor", accessStart);
  const access = edgeSource.slice(accessStart, accessEnd);
  assert.match(access, /\.eq\("tenant_id",branch\.tenant_id\)/, "membership must match the requested branch tenant");
  assert.match(access, /\.eq\("status","active"\)/, "membership must be active");
  assert.match(access, /\.eq\("branch_id",branchId\)/, "worker must have an assignment to the exact branch");
  assert.match(access, /\.eq\("employment_status","active"\)/, "branch assignment must be active");
});
