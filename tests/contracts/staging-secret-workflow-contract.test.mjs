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
  assert.match(script, /!key\.trim\(\)/);
  assert.match(script, /!username\.trim\(\)/);
  assert.match(script, /!password\.trim\(\)/);
});


test("every missing or invalid required input fails closed before any network request", async (t) => {
  const valid = {
    STAGING_SUPABASE_URL: "https://higoadrzxnhzbbwhdbmh.supabase.co",
    STAGING_EDGE_FUNCTION_URL: "https://higoadrzxnhzbbwhdbmh.supabase.co/functions/v1/dlice-orders",
    STAGING_SUPABASE_PUBLIC_KEY: "test-public-key",
    STAGING_TENANT_A_USERNAME: "qa-probe-only",
    STAGING_TENANT_A_PASSWORD: "non-secret-placeholder",
    STAGING_TENANT_B_BRANCH_ID: "11111111-1111-4111-8111-111111111111",
  };
  const missingInputs = [
    ["public key", "STAGING_SUPABASE_PUBLIC_KEY", ""],
    ["Tenant A username", "STAGING_TENANT_A_USERNAME", ""],
    ["Tenant A password", "STAGING_TENANT_A_PASSWORD", ""],
    ["Tenant B branch fixture", "STAGING_TENANT_B_BRANCH_ID", ""],
    ["whitespace-only public key", "STAGING_SUPABASE_PUBLIC_KEY", "   "],
    ["whitespace-only Tenant A username", "STAGING_TENANT_A_USERNAME", "   "],
    ["whitespace-only Tenant A password", "STAGING_TENANT_A_PASSWORD", "   "],
    ["malformed Tenant B branch fixture", "STAGING_TENANT_B_BRANCH_ID", "not-a-uuid"],
  ];

  for (const [label, variable, value] of missingInputs) {
    await t.test(label, () => {
      const result = spawnSync(process.execPath, ["tests/staging/tenant-isolation-existing-identity.mjs"], {
        encoding: "utf8",
        env: { PATH: process.env.PATH ?? "", ...valid, [variable]: value },
        timeout: 5000,
      });

      assert.equal(result.status, 2, "preflight must exit BLOCKED");
      assert.match(result.stderr, /BLOCKED: one or more required staging/);
      assert.doesNotMatch(result.stderr, /ReferenceError|Cannot access 'branchB'/);
      assert.doesNotMatch(result.stderr, /non-secret-placeholder|test-public-key|qa-probe-only|access_token|Bearer\s/i);
      assert.equal(result.stdout, "", "no request/probe output is allowed before preflight");
      assert.equal(result.error, undefined, "timeout/network attempts are not expected");
    });
  }
});


test("KDS/POS/Stock staging E2E uses only staging Environment Supabase endpoint secrets", () => {
  const kds = readFileSync(".github/workflows/staging-kds-pos-stock-positive-e2e.yml", "utf8");
  const triggers = kds.split(/^permissions:\s*$/m, 1)[0];
  assert.match(triggers, /^  workflow_dispatch:\s*$/m);
  assert.doesNotMatch(triggers, /^\s+(?:push|schedule):/m);
  assert.match(kds, /github\.ref\s*==\s*'refs\/heads\/staging'/);
  assert.match(kds, /github\.event_name\s*==\s*'workflow_dispatch'/);
  assert.match(kds, /inputs\.confirm_staging_mutations\s*==\s*true/);
  assert.match(kds, /^\s+environment:\s*staging\s*$/m);
  assert.match(kds, /STAGING_SUPABASE_URL:\s*\$\{\{\s*secrets\.STAGING_SUPABASE_URL\s*\}\}/);
  assert.match(kds, /STAGING_SUPABASE_PUBLIC_KEY:\s*\$\{\{\s*secrets\.STAGING_SUPABASE_PUBLIC_KEY\s*\}\}/);
  assert.match(kds, /STAGING_SUPABASE_SERVICE_ROLE_KEY:\s*\$\{\{\s*secrets\.STAGING_SUPABASE_SERVICE_ROLE_KEY\s*\}\}/);
  assert.doesNotMatch(kds, /STAGING_EDGE_FUNCTION_URL/);
  assert.doesNotMatch(kds, /STAGING_TEST_OWNER_(?:USERNAME|PASSWORD)/);
  assert.doesNotMatch(kds, /sb_publishable_[A-Za-z0-9_-]+/);
  assert.doesNotMatch(kds, /STAGING_SUPABASE_URL:\s*https:\/\/higoadrzxnhzbbwhdbmh\.supabase\.co/);
  assert.doesNotMatch(kds, /STAGING_EDGE_FUNCTION_URL:\s*https:\/\/higoadrzxnhzbbwhdbmh\.supabase\.co/);
});
