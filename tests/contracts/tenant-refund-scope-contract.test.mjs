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
  assert.match(edge, /const PLATFORM_OWNER_USER_IDS = new Set\(/);
  assert.match(edge, /DLICE_PLATFORM_OWNER_USER_IDS/);
  assert.match(edge, /\[0-9a-f\]\{8\}-\[0-9a-f\]\{4\}-\[0-9a-f\]\{4\}-\[0-9a-f\]\{4\}-\[0-9a-f\]\{12\}/i, "platform-owner allowlist accepts only canonical UUID-shaped IDs");
  assert.match(edge, /if \(!TENANT_ISOLATION_RELEASED && !PLATFORM_OWNER_USER_IDS\.has\(actor\.user\.id\) && TENANT_SCOPE_UNCERTIFIED_ACTIONS\.has\(action\)\)/);
  assert.doesNotMatch(edge, /TENANT_ISOLATION_RELEASED && actor\.profile\.role !== "owner"/);
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


test("generic owner role cannot grant platform-wide bypass without allowlisted identity", () => {
  assert.match(edge, /profile\.role === "owner" && PLATFORM_OWNER_USER_IDS\.has\(userData\.user\.id\)/);
  assert.match(edge, /\.filter\(\(permission: string\) => permission !== "\*"\)/);
  assert.doesNotMatch(edge, /actor\.profile\.role\s*===\s*"owner"/);
  assert.doesNotMatch(edge, /actor\.profile\.role\s*!==\s*"owner"/);
  assert.match(edge, /const actorCanAccessBranch = async \(branchId: string \| null \| undefined\): Promise<boolean> => \{\n    if \(isPlatformOwner\) return true;/);
  assert.match(edge, /const TENANT_ISOLATION_RELEASED = false/);
});
