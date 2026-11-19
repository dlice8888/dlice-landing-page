import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const edge = await readFile(
  new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url),
  "utf8",
);
const migration = await readFile(
  new URL("../../supabase/migrations/20261120100000_atomic_owner_and_tenant_bootstrap.sql", import.meta.url),
  "utf8",
);

const ownerBootstrapStart = edge.indexOf('if (action === "admin-bootstrap-owner")');
const ownerBootstrap = edge.slice(
  ownerBootstrapStart,
  edge.indexOf("const actor = await getAdmin(req)", ownerBootstrapStart),
);
const tenantBootstrap = edge.slice(
  edge.indexOf('if (action === "erp-create-tenant")'),
  edge.indexOf('if (action === "erp-invite-tenant-member")'),
);

test("initial owner profile, tenant membership, and audit use one database transaction", () => {
  assert.match(ownerBootstrap, /admin\.rpc\("dlice_bootstrap_initial_owner"/);
  assert.doesNotMatch(ownerBootstrap, /from\("admin_profiles"\)\.insert/);
  assert.doesNotMatch(ownerBootstrap, /from\("tenant_memberships"\)\.insert/);
  assert.doesNotMatch(ownerBootstrap, /from\("admin_audit_logs"\)\.insert/);
  assert.match(ownerBootstrap, /app_metadata:\s*\{\s*platform_owner:\s*true\s*\}/);
  assert.match(ownerBootstrap, /admin\.auth\.admin\.deleteUser\(created\.user\.id\)/);
});

test("tenant creation and owner membership use one database transaction", () => {
  assert.match(tenantBootstrap, /admin\.rpc\("dlice_create_tenant_with_owner"/);
  assert.doesNotMatch(tenantBootstrap, /from\("(?:tenants|tenant_memberships|admin_audit_logs)"\)\.(?:insert|delete)/);
  assert.match(tenantBootstrap, /if\s*\(\s*!\s*TENANT_ISOLATION_RELEASED\s*\)/);
});

test("bootstrap RPCs are service-role-only and write audit inside their transaction", () => {
  for (const fn of ["dlice_bootstrap_initial_owner", "dlice_create_tenant_with_owner"]) {
    assert.match(migration, new RegExp(`FUNCTION public\\.${fn}[\\s\\S]*?SECURITY INVOKER[\\s\\S]*?auth\\.role\\(\\) IS DISTINCT FROM 'service_role'[\\s\\S]*?INSERT INTO public\\.admin_audit_logs`));
    assert.match(migration, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}`));
    assert.match(migration, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}[\\s\\S]*?TO service_role`));
  }
});


test("successful bootstrap returns the new Auth UUID for administrator allowlist verification", () => {
  assert.match(ownerBootstrap, /data:\s*bootstrapResult/);
  assert.match(ownerBootstrap, /user_id:\s*created\.user\.id/);
  assert.match(ownerBootstrap, /platform_owner_allowlist_update_required:\s*true/);
  assert.match(ownerBootstrap, /DLICE_OWNER_BOOTSTRAP_SECRET/);
  assert.match(ownerBootstrap, /count\s*\?\?\s*0/);
});
test("initial owner bootstrap requires the one-time server secret before any account or profile lookup", () => {
  assert.ok(ownerBootstrap.indexOf("DLICE_OWNER_BOOTSTRAP_SECRET") < ownerBootstrap.indexOf("admin_profiles"));
  assert.ok(ownerBootstrap.indexOf("bootstrap_secret") < ownerBootstrap.indexOf("admin.auth.admin.createUser"));
  assert.match(ownerBootstrap, /if \(!bootstrapSecret \|\| safeText\(body\.bootstrap_secret, 256\) !== bootstrapSecret\) return fail/);
  assert.match(ownerBootstrap, /if \(\(count \?\? 0\) > 0\) return fail/);
  assert.doesNotMatch(ownerBootstrap, /console\.(?:log|info|warn|error).*bootstrapSecret/);
  assert.doesNotMatch(ownerBootstrap, /return json\([\s\S]{0,300}(?:password|bootstrap_secret)/i);
});

test("uncertain bootstrap RPC outcomes are never auto-cleaned up as if rollback were proven", () => {
  const uncertain = ownerBootstrap.indexOf("Hasil bootstrap belum dapat dipastikan");
  const cleanup = ownerBootstrap.indexOf("admin.auth.admin.deleteUser");
  assert.ok(uncertain >= 0 && cleanup > uncertain);
  assert.ok(ownerBootstrap.indexOf("typeof bootstrapError.code !== \"string\"") < uncertain);
  assert.ok(ownerBootstrap.indexOf("typeof bootstrapError.code !== \"string\"") < cleanup);
  assert.match(migration, /pg_advisory_xact_lock/);
});

