import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync("supabase/migrations/20261120125000_harden_owner_metadata_boolean.sql", "utf8");

test("platform_owner metadata is checked as JSON boolean true, not text", () => {
  assert.equal((migration.match(/raw_app_meta_data->'platform_owner' = 'true'::jsonb/g) || []).length, 2);
  assert.doesNotMatch(migration, /raw_app_meta_data->>'platform_owner'\s*=\s*'true'/);
});

test("service-role RPC guards use the current JWT role claim helper", () => {
  assert.equal((migration.match(/auth\.jwt\(\) ->> 'role'/g) || []).length, 3);
  assert.doesNotMatch(migration, /auth\.role\(\)/);
  for (const fn of ["dlice_bootstrap_initial_owner", "dlice_create_tenant_with_owner", "dlice_manage_branch_checklist"]) {
    assert.match(migration, new RegExp("REVOKE ALL ON FUNCTION public\\." + fn));
    assert.match(migration, new RegExp("GRANT EXECUTE ON FUNCTION public\\." + fn + "[\\s\\S]*?TO service_role"));
  }
});
