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
