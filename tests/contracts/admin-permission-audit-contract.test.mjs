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
const profileMigration = await readFile(
  new URL("../../supabase/migrations/20261121160000_atomic_admin_profile_mutation_audit.sql", import.meta.url),
  "utf8",
);
const createStaffBlock = source.slice(
  source.indexOf('if (action === "admin-create-staff")'),
  source.indexOf('if (action === "admin-set-permissions")'),
);
const roleBlock = source.slice(
  source.indexOf('if (action === "admin-set-profile-role")'),
  source.indexOf('if (action === "admin-set-active")'),
);
const activeBlock = source.slice(
  source.indexOf('if (action === "admin-set-active")'),
  source.indexOf('if (action === "admin-reset-staff-password")'),
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

test("staff profile creation writes profile and audit through one RPC", () => {
  assert.match(createStaffBlock, /admin\.rpc\("dlice_create_admin_profile_audited"/);
  assert.doesNotMatch(createStaffBlock, /from\("admin_profiles"\)\.insert/);
  assert.doesNotMatch(createStaffBlock, /from\("admin_audit_logs"\)\.insert/);
  assert.match(createStaffBlock, /hasil penyimpanan profil\/audit belum dapat dipastikan/);
});

test("staff role mutation uses the atomic audited RPC", () => {
  assert.match(roleBlock, /admin\.rpc\("dlice_update_admin_profile_role_audited"/);
  assert.doesNotMatch(roleBlock, /from\("admin_profiles"\)\.update/);
  assert.doesNotMatch(roleBlock, /from\("admin_audit_logs"\)\.insert/);
});

test("staff active-state mutation uses the atomic audited RPC", () => {
  assert.match(activeBlock, /admin\.rpc\("dlice_set_admin_profile_active_audited"/);
  assert.doesNotMatch(activeBlock, /from\("admin_profiles"\)\.update/);
  assert.doesNotMatch(activeBlock, /from\("admin_audit_logs"\)\.insert/);
});

test("all staff profile mutation RPCs are service-role-only and audit in their transaction", () => {
  for (const name of [
    "dlice_create_admin_profile_audited",
    "dlice_update_admin_profile_role_audited",
    "dlice_set_admin_profile_active_audited",
  ]) {
    assert.match(profileMigration, new RegExp(`create or replace function public\\.${name}`));
    assert.match(profileMigration, new RegExp(`revoke all on function public\\.${name}`));
    assert.match(profileMigration, new RegExp(`grant execute on function public\\.${name}`));
  }
  assert.match(profileMigration, /insert into public\.admin_profiles[\s\S]*?insert into public\.admin_audit_logs/i);
  assert.match(profileMigration, /update public\.admin_profiles[\s\S]*?insert into public\.admin_audit_logs/i);
  assert.match(profileMigration, /previous_role/);
  assert.match(profileMigration, /new_role/);
  assert.match(profileMigration, /previous_is_active/);
  assert.match(profileMigration, /new_is_active/);
});
