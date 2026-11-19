import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migration = await readFile("supabase/migrations/20261119160000_revoke_default_public_function_execute.sql", "utf8");
const sqlTest = await readFile("supabase/tests/default_function_execute_acl.test.sql", "utf8");
const workflow = await readFile(".github/workflows/disposable-migration-replay.yml", "utf8");

test("default function privileges deny public client EXECUTE for both migration owners", () => {
  assert.match(migration, /ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public[\s\S]*?REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated/);
  assert.match(migration, /ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public[\s\S]*?REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated/);
  for (const fn of ["erp_guard_journal_period", "erp_guard_refund_amount", "set_updated_at"]) {
    assert.ok(migration.includes(`REVOKE EXECUTE ON FUNCTION public.${fn}() FROM PUBLIC, anon, authenticated;`), fn);
  }
});

test("database ACL assertions are included in the disposable migration replay", () => {
  assert.ok(sqlTest.includes("has_function_privilege('anon'"));
  assert.ok(sqlTest.includes("has_function_privilege('authenticated'"));
  assert.ok(sqlTest.includes("has_function_privilege('service_role'"));
  assert.ok(workflow.includes("supabase test db"));
  assert.ok(workflow.includes("supabase/tests"));
});
