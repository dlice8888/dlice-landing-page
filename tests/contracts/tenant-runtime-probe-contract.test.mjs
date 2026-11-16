import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const workflow = readFileSync(".github/workflows/staging-tenant-isolation-acceptance.yml", "utf8");
const probe = readFileSync("tests/runtime/dlice-tenant-jwt-isolation.mjs", "utf8");

test("staging tenant gate uses only the six canonical credentials and the verified identities", () => {
  const triggers = workflow.split(/^permissions:\s*$/m, 1)[0];
  assert.match(workflow, /^\s+environment:\s*staging\s*$/m);
  assert.match(triggers, /^  push:\s*\n\s+branches:\s*\[staging\]/m);
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
  assert.doesNotMatch(triggers, /workflow_dispatch/);
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
