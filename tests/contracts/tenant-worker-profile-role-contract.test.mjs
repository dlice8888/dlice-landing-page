import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const edge = await readFile("supabase/functions/dlice-orders/index.ts", "utf8");
const erp = await readFile("erp.html", "utf8");
const migration = await readFile("supabase/migrations/20261118190000_add_branch_worker_profile_role.sql", "utf8");
const workflow = await readFile(".github/workflows/quality-checks.yml", "utf8");

test("branch_worker is a non-owner identity classification, not a permission grant", () => {
  assert.match(migration, /'sales_admin'::text,\s*'branch_worker'::text,\s*'owner'::text/);
  assert.match(edge, /profile\.role === "owner" && PLATFORM_OWNER_USER_IDS\.has\(userData\.user\.id\) && userData\.user\.app_metadata\?\.platform_owner === true/);
  assert.match(edge, /resolveTenantScopedPermissions\(memberships\)/);
  assert.match(edge, /Never authorize tenant actions from global admin_profiles\.permissions/);
});

test("only a verified platform Owner can change a non-owner profile classification", () => {
  const start = edge.indexOf('if (action === "admin-set-profile-role")');
  const end = edge.indexOf('if (action === "admin-set-active")', start);
  assert.ok(start >= 0 && end > start, "profile-role handler must exist");
  const handler = edge.slice(start, end);
  assert.match(handler, /if \(!isPlatformOwner\)/);
  assert.match(handler, /\["sales_admin", "branch_worker"\]/);
  assert.match(handler, /target\.role === "owner"/);
  assert.match(handler, /tenant_memberships/);
  assert.match(handler, /tenant_owner.*tenant_admin/);
  assert.match(handler, /branch_assignments/);
  assert.match(handler, /employment_status", "active"/);
  assert.match(handler, /tenantIds\.has\(assignment\.branches\?\.tenant_id\)/);
  assert.match(handler, /set_staff_profile_role/);
});

test("branch_worker UI uses the Owner-only role action and does not grant global permissions", () => {
  assert.match(erp, /id="staffRolePanel"/);
  assert.match(erp, /value="branch_worker"/);
  assert.match(erp, /admin-set-profile-role/);
  assert.match(erp, /Branch Worker bukan Owner\/Admin/);
});

test("quality workflow executes this contract test", () => {
  assert.match(workflow, /node --test tests\/contracts\/tenant-worker-profile-role-contract\.test\.mjs/);
});
