import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(
  new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url),
  "utf8",
);
const migration = await readFile(
  new URL("../../supabase/migrations/20261121100000_atomic_admin_permission_audit.sql", import.meta.url),
  "utf8",
);

const permissionBlock = source.slice(
  source.indexOf('if (action === "admin-set-permissions")'),
  source.indexOf('if (action === "admin-set-profile-role")'),
);

test("permission mutation uses the atomic audited RPC", () => {
  assert.match(permissionBlock, /admin\.rpc\("dlice_update_admin_permissions_audited"/);
  assert.match(permissionBlock, /p_actor_user_id:\s*actor\.user\.id/);
  assert.match(permissionBlock, /p_target_user_id:\s*userId/);
  assert.doesNotMatch(permissionBlock, /from\("admin_profiles"\)\.update/);
  assert.doesNotMatch(permissionBlock, /from\("admin_audit_logs"\)\.insert/);
});

test("permission changes fail closed when audit persistence fails", () => {
  assert.match(permissionBlock, /if\s*\(error\)\s*return fail\(/);
  assert.match(permissionBlock, /audit tidak dapat dipastikan/);
});

test("audited RPC is service-role-only and records before/after values transactionally", () => {
  assert.match(migration, /auth\.role\(\) is distinct from 'service_role'/i);
  assert.match(migration, /revoke all on function[\s\S]*from public, anon, authenticated/i);
  assert.match(migration, /grant execute on function[\s\S]*to service_role/i);
  assert.match(migration, /previous_permissions/);
  assert.match(migration, /new_permissions/);
  assert.match(migration, /update public\.admin_profiles[\s\S]*?insert into public\.admin_audit_logs/i);
});
