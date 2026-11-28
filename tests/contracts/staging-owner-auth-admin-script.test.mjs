import test from "node:test";
import assert from "node:assert/strict";
import { setStagingPlatformOwnerClaim, STAGING_PROJECT_REF } from "../../scripts/set-staging-platform-owner.mjs";

const ownerId = "378f02bc-2719-4b07-9107-4ce94299aa27";
const url = `https://${STAGING_PROJECT_REF}.supabase.co`;

test("updates only the existing staging Owner app_metadata and preserves other claims", async () => {
  const calls = [];
  const existing = { provider: "email", providers: ["email"], legacy_claim: "preserve" };
  const fetchImpl = async (_url, options) => {
    calls.push(options);
    if (options.method === "GET") {
      return { ok: true, status: 200, json: async () => ({ id: ownerId, app_metadata: calls.length === 1 ? existing : { ...existing, platform_owner: true } }) };
    }
    const body = JSON.parse(options.body);
    assert.deepEqual(body.app_metadata, { ...existing, platform_owner: true });
    return { ok: true, status: 200, json: async () => ({ id: ownerId, app_metadata: body.app_metadata }) };
  };
  const result = await setStagingPlatformOwnerClaim({ supabaseUrl: url, serviceRoleKey: "test-secret", ownerUserId: ownerId, fetchImpl });
  assert.equal(result.updated, true);
  assert.equal(result.platformOwnerBoolean, true);
  assert.deepEqual(calls.map(x => x.method), ["GET", "PUT", "GET"]);
  assert.equal(JSON.parse(calls[1].body).app_metadata.platform_owner, true);
});

test("refuses non-staging project before making an Auth request", async () => {
  let called = false;
  await assert.rejects(setStagingPlatformOwnerClaim({
    supabaseUrl: "https://another-project.supabase.co", serviceRoleKey: "secret", ownerUserId: ownerId,
    fetchImpl: async () => { called = true; throw new Error("must not call"); },
  }), { code: "OWNER_AUTH_ADMIN_STAGING_ONLY" });
  assert.equal(called, false);
});

test("rejects malformed UUID and banned account before updating metadata", async () => {
  await assert.rejects(setStagingPlatformOwnerClaim({ supabaseUrl: url, serviceRoleKey: "secret", ownerUserId: "not-a-uuid" }), { code: "OWNER_AUTH_ADMIN_UUID_INVALID" });
  let methods = [];
  await assert.rejects(setStagingPlatformOwnerClaim({
    supabaseUrl: url, serviceRoleKey: "secret", ownerUserId: ownerId,
    fetchImpl: async (_url, options) => {
      methods.push(options.method);
      return { ok: true, status: 200, json: async () => ({ id: ownerId, banned_until: "2999-01-01T00:00:00Z", app_metadata: {} }) };
    },
  }), { code: "OWNER_AUTH_ADMIN_USER_BANNED" });
  assert.deepEqual(methods, ["GET"]);
});

import { readFileSync } from "node:fs";
const workflow = readFileSync(".github/workflows/staging-owner-auth-repair.yml", "utf8");

test("manual Auth repair workflow is staging-environment scoped and explicitly confirmed", () => {
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /environment:\s*staging/);
  assert.match(workflow, /confirm_staging_only/);
  assert.match(workflow, /inputs\.confirm_staging_only\s*==\s*'yes'/);
  assert.match(workflow, /STAGING_SUPABASE_SERVICE_ROLE_KEY:\s*\$\{\{\s*secrets\.STAGING_SUPABASE_SERVICE_ROLE_KEY\s*\}\}/);
  assert.match(workflow, /scripts\/set-staging-platform-owner\.mjs/);
  assert.doesNotMatch(workflow, /STAGING_SUPABASE_SERVICE_ROLE_KEY:\s*(?!\$\{\{)/);
});
