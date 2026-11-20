import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const workflow = readFileSync(".github/workflows/staging-tenant-isolation-acceptance.yml", "utf8");
const runtime = readFileSync("tests/runtime/dlice-tenant-jwt-isolation.mjs", "utf8");
const broker = readFileSync("supabase/functions/staging-tenant-session/index.ts", "utf8");
const migration = readFileSync("supabase/migrations/20261120140000_staging_machine_session_issuance_audit.sql", "utf8");
const config = readFileSync("supabase/config.toml", "utf8");

test("tenant isolation workflow uses GitHub OIDC and no username/password secrets", () => {
  assert.match(workflow, /id-token: write/);
  assert.match(workflow, /ACTIONS_ID_TOKEN_REQUEST_URL/);
  assert.match(workflow, /staging-tenant-session/);
  assert.match(workflow, /STAGING_TENANT_\$\{slot\}_ACCESS_TOKEN/);
  assert.doesNotMatch(workflow, /secrets\.STAGING_TENANT_[AB]_(USERNAME|PASSWORD)/);
  assert.doesNotMatch(workflow, /STAGING_SUPABASE_(SERVICE_ROLE|SECRET)_KEY/);
  assert.match(workflow, /environment:\s*staging/);
  assert.match(workflow, /if: github\.ref == 'refs\/heads\/staging'/);
});

test("broker validates immutable GitHub workflow identity and exact staging trust boundary", () => {
  assert.match(broker, /createRemoteJWKSet/);
  assert.match(broker, /jwtVerify/);
  assert.match(broker, /refs\/heads\/staging/);
  assert.ok(broker.includes('repo:dlice8888/dlice-landing-page:environment:staging'));
  assert.match(broker, /workflow_dispatch/);
  assert.match(broker, /!exact\("event_name", "workflow_dispatch"\)/);
  assert.doesNotMatch(broker, /\\["workflow_dispatch", "push"\\]/);
  assert.match(broker, /claims\.run_id/);
  assert.match(broker, /claims\.run_attempt/);
  assert.match(broker, /claims\.jti/);
  assert.match(broker, /staging_machine_session_issuances/);
  assert.match(broker, /from\("tenant_memberships"\)/);
  assert.match(broker, /activeTenantIds\.size !== 1/);
  assert.match(broker, /membership\.role !== "branch_manager"/);
  assert.match(broker, /generateLink/);
  assert.match(broker, /verifyOtp/);
  assert.match(broker, /expiresAt - nowSeconds > 3600/);
  assert.match(broker, /session_lifetime_out_of_policy/);
  assert.doesNotMatch(broker, /auth\.admin\.createUser|\.from\(["'](?:tenants|tenant_memberships|branch_assignments)["']\)\.(?:insert|upsert)/);
});

test("session issuance audit is private to service role and replay constrained", () => {
  assert.match(migration, /unique \(github_run_id, github_run_attempt, tenant_slot\)/i);
  assert.match(migration, /unique \(github_jti, tenant_slot\)/i);
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /revoke all .* from public, anon, authenticated/i);
  assert.match(migration, /grant all .* to service_role/i);
});

test("tenant probes consume two different broker-issued user sessions, not passwords", () => {
  assert.match(runtime, /STAGING_TENANT_A_ACCESS_TOKEN/);
  assert.match(runtime, /STAGING_TENANT_B_ACCESS_TOKEN/);
  assert.match(runtime, /tokenA !== tokenB/);
  assert.match(runtime, /\/auth\/v1\/user/);
  assert.doesNotMatch(runtime, /STAGING_TENANT_[AB]_(USERNAME|PASSWORD)/);
  assert.match(config, /\[functions\.staging-tenant-session\][\s\S]*verify_jwt = false/);
});
