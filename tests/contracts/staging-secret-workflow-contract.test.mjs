import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const workflow = readFileSync(".github/workflows/staging-auth-tenant-negative.yml", "utf8");
const triggers = workflow.split(/^permissions:\s*$/m, 1)[0];

test("authenticated staging probes do not execute pull request code with staging secrets", () => {
  assert.match(triggers, /^  push:\s*\n\s+branches:\s*\[staging\]/m);
  assert.doesNotMatch(triggers, /\bpull_request\b/);
  assert.match(workflow, /^\s+environment:\s*staging\s*$/m);
  assert.match(workflow, /STAGING_TENANT_A_PASSWORD:\s*\$\{\{\s*secrets\.STAGING_TENANT_A_PASSWORD\s*\}\}/);
  assert.match(workflow, /STAGING_SUPABASE_PUBLIC_KEY:\s*\$\{\{\s*secrets\.STAGING_SUPABASE_PUBLIC_KEY\s*\}\}/);
});


test("legacy authenticated negative probes use canonical Tenant A credentials and real Tenant B branch fixture", () => {
  assert.match(workflow, /STAGING_TENANT_A_USERNAME:\s*\$\{\{\s*secrets\.STAGING_TENANT_A_USERNAME\s*\}\}/);
  assert.match(workflow, /STAGING_TENANT_A_PASSWORD:\s*\$\{\{\s*secrets\.STAGING_TENANT_A_PASSWORD\s*\}\}/);
  assert.match(workflow, /STAGING_TENANT_B_BRANCH_ID:\s*\$\{\{\s*vars\.STAGING_TENANT_B_BRANCH_ID\s*\}\}/);
  assert.doesNotMatch(workflow, /STAGING_TEST_BRANCH_A_/);
  const script = readFileSync("tests/staging/tenant-isolation-existing-identity.mjs", "utf8");
  assert.match(script, /process\.env\.STAGING_TENANT_B_BRANCH_ID/);
  assert.doesNotMatch(script, /90000000-0000-4000-8000-000000000001|d8672046-7029-489b-9223-df07007cdc69/);
});

test("legacy probe reports missing branch fixture as blocked before making network requests", () => {
  const result = spawnSync(process.execPath, ["tests/staging/tenant-isolation-existing-identity.mjs"], {
    encoding: "utf8",
    env: {
      PATH: process.env.PATH ?? "",
      STAGING_SUPABASE_URL: "https://higoadrzxnhzbbwhdbmh.supabase.co",
      STAGING_EDGE_FUNCTION_URL: "https://higoadrzxnhzbbwhdbmh.supabase.co/functions/v1/dlice-orders",
      STAGING_SUPABASE_PUBLIC_KEY: "test-public-key",
      STAGING_TENANT_A_USERNAME: "qa-probe-only",
      STAGING_TENANT_A_PASSWORD: "non-secret-placeholder",
    },
  });

  assert.equal(result.status, 2);
  assert.match(result.stderr, /BLOCKED: staging public key, canonical Tenant A credentials, or Tenant B branch fixture/);
  assert.doesNotMatch(result.stderr, /ReferenceError|Cannot access 'branchB'/);
});
