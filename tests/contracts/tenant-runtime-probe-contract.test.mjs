import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const workflow = readFileSync(".github/workflows/staging-runtime-tenant-isolation.yml", "utf8");
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
  assert.match(workflow, /STAGING_TENANT_A_USER_ID:\s*b930897c-f8fb-443b-9056-e70c08b31446/);
  assert.match(workflow, /STAGING_TENANT_B_USER_ID:\s*e1de1ffc-9fae-412f-9dd7-0993b54cb631/);
  assert.match(workflow, /STAGING_TENANT_A_BRANCH_CODE:\s*QA-DLICE-A/);
  assert.match(workflow, /STAGING_TENANT_B_BRANCH_CODE:\s*QA-TENANT-B/);
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
  assert.match(probe, /status\s*===?\s*["']active["']/);
  assert.match(probe, /BLOCKED/);
  assert.match(probe, /secretValuesPrinted:\s*false/);
  assert.doesNotMatch(probe, /console\.(?:log|error)\([^)]*(?:tokenA|tokenB|passwordA|passwordB)/);
});
