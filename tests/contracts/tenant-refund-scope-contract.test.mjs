import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const edge = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");

test("refund processing denies unscoped refunds to non-HQ finance actors", () => {
  const start = edge.indexOf('if (action === "erp-process-refund")');
  assert.notEqual(start, -1, "refund processing action exists");
  const next = edge.indexOf('\n  if (action === ', start + 1);
  const handler = edge.slice(start, next === -1 ? undefined : next);
  assert.match(handler, /const financeHQ = await hasFinanceHQ\(\)/);
  assert.match(handler, /if\(!old\.branch_id&&!financeHQ\)return fail\([^\n]*403,origin\)/);
  assert.match(handler, /if\(old\.branch_id&&!financeHQ&&!await actorCanAccessBranch\(old\.branch_id\)\)return fail\([^\n]*403,origin\)/);
  assert.match(handler, /\.eq\("id",id\)\.eq\("status","approved"\)/);
});

test("tenant onboarding stays fail-closed until cross-tenant negative tests are accepted", () => {
  assert.match(edge, /const TENANT_ISOLATION_RELEASED = false/);
  assert.match(edge, /if \(!TENANT_ISOLATION_RELEASED\) return fail\("Tenant onboarding is paused until cross-tenant isolation tests pass\.", 423, origin\)/);
});

test("uncertified legacy tenant actions fail closed for non-platform owners", () => {
  assert.match(edge, /const TENANT_SCOPE_UNCERTIFIED_ACTIONS = new Set\(\[/);
  assert.match(edge, /if \(!TENANT_ISOLATION_RELEASED && actor\.profile\.role !== "owner" && TENANT_SCOPE_UNCERTIFIED_ACTIONS\.has\(action\)\)/);
  for (const action of [
    "admin-list-orders", "admin-list-products", "admin-save-product", "admin-upload-product-photo", "admin-set-permissions",
    "erp-list-recipes", "erp-save-product-modifier", "erp-save-recipe-substitution",
    "erp-list-settlements", "erp-create-fiscal-period", "erp-save-tax-setting",
    "erp-list-branches", "erp-list-branch-settings", "erp-save-branch", "erp-save-assignment", "erp-list-refunds", "erp-process-refund",
    "erp-overview", "erp-list-audit-logs",
  ]) {
    assert.ok(edge.includes(`"${action}"`), `missing fail-closed action: ${action}`);
  }
  assert.match(edge, /Akses sementara ditutup sampai cakupan tenant untuk tindakan ini lolos pengujian isolasi\./);
});
