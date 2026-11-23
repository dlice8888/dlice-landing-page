import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../../", import.meta.url);
const [kdsWorkflow, procurementWorkflow, kdsScript, procurementScript, authHelper, tenantWorkflow] = await Promise.all([
  readFile(new URL(".github/workflows/staging-kds-pos-stock-positive-e2e.yml", root), "utf8"),
  readFile(new URL(".github/workflows/staging-procurement-positive-e2e.yml", root), "utf8"),
  readFile(new URL("tests/staging/kds-pos-stock-positive.mjs", root), "utf8"),
  readFile(new URL("tests/staging/procurement-receiving-positive.mjs", root), "utf8"),
  readFile(new URL("tests/runtime/staging-passwordless-auth.mjs", root), "utf8"),
  readFile(new URL(".github/workflows/staging-tenant-isolation-acceptance.yml", root), "utf8"),
]);

test("positive-path staging workflows require explicit staging-only manual mutation confirmation", () => {
  for (const workflow of [kdsWorkflow, procurementWorkflow]) {
    assert.match(workflow, /workflow_dispatch:/);
    assert.match(workflow, /confirm_staging_mutations:/);
    assert.match(workflow, /environment: staging/);
    assert.match(workflow, /refs\/heads\/staging/);
    assert.match(workflow, /STAGING_SUPABASE_SERVICE_ROLE_KEY:/);
    assert.doesNotMatch(workflow, /STAGING_TEST_OWNER_(?:USERNAME|PASSWORD)/);
    assert.doesNotMatch(workflow, /STAGING_TEST_BRANCH_A_(?:USERNAME|PASSWORD)/);
  }
  assert.doesNotMatch(procurementWorkflow, /feat\/staging-kds-offline-tenant/);
});

test("E2E scripts authenticate only pre-existing Auth identities via one-time magic links", () => {
  for (const script of [kdsScript, procurementScript]) {
    assert.match(script, /tokenForExistingUser/);
    assert.match(script, /STAGING_SUPABASE_SERVICE_ROLE_KEY/);
    assert.doesNotMatch(script, /grant_type=password/);
    assert.doesNotMatch(script, /STAGING_TEST_OWNER_(?:USERNAME|PASSWORD)/);
    assert.doesNotMatch(script, /STAGING_TEST_BRANCH_A_(?:USERNAME|PASSWORD)/);
  }
  assert.match(procurementScript, /STAGING_TENANT_A_USER_ID/);
});

test("passwordless helper uses Admin lookup + generate_link + verify without creating or mutating accounts", () => {
  assert.match(authHelper, /auth\/v1\/admin\/users/);
  assert.match(authHelper, /auth\/v1\/admin\/generate_link/);
  assert.match(authHelper, /type:\s*["']magiclink["']/);
  assert.match(authHelper, /auth\/v1\/verify/);
  assert.match(authHelper, /serviceRoleHeaders/);
  assert.match(authHelper, /email_confirmed_at/);
  assert.doesNotMatch(authHelper, /admin\/users["']?\s*,\s*\{/);
  assert.doesNotMatch(authHelper, /updateUserById|createUser|password:/);
  assert.doesNotMatch(authHelper, /console\.(?:log|info|warn|error).*?(?:token|email|secret|key)/i);
});


test("P01-P09 acceptance reruns when Edge Function, migrations or positive E2E auth harness changes", () => {
  assert.match(tenantWorkflow, /push:/);
  assert.match(tenantWorkflow, /branches:\s*\n\s+- staging/);
  assert.match(tenantWorkflow, /workflow_dispatch:/);
  for (const path of [
    "supabase/functions/dlice-orders/**",
    "supabase/migrations/**",
    "tests/runtime/staging-passwordless-auth.mjs",
    "tests/staging/kds-pos-stock-positive.mjs",
    "tests/staging/procurement-receiving-positive.mjs",
    ".github/workflows/staging-kds-pos-stock-positive-e2e.yml",
    ".github/workflows/staging-procurement-positive-e2e.yml",
  ]) assert.ok(tenantWorkflow.includes(path), `tenant acceptance trigger must cover ${path}`);
  assert.match(tenantWorkflow, /github\.ref\s*==\s*'refs\/heads\/staging'/);
});
