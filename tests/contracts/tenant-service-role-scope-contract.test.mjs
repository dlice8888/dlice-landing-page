import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(
  new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url),
  "utf8",
);

const gate = source.match(/const TENANT_SCOPE_UNCERTIFIED_ACTIONS = new Set\(\[([\s\S]*?)\]\);/)?.[1] ?? "";
const gatedActions = new Set([...gate.matchAll(/"([^"]+)"/g)].map((match) => match[1]));

test("unscoped service-role inventory and invite handlers remain closed before tenant isolation release", () => {
  for (const action of ["erp-accept-tenant-invite", "erp-list-inventory", "erp-save-inventory"]) {
    assert.ok(gatedActions.has(action), `missing tenant isolation gate for ${action}`);
  }
  assert.match(source, /if \(!TENANT_ISOLATION_RELEASED && !isPlatformOwner && TENANT_SCOPE_UNCERTIFIED_ACTIONS\.has\(action\)\)/);
});

test("global funnel metrics are not exposed to tenant members before tenant-scoped reporting exists", () => {
  const start = source.indexOf('if (action === "admin-funnel-summary")');
  const end = source.indexOf('if (action === "list-products")', start);
  const block = source.slice(start, end);
  assert.match(block, /funnelPlatformOwner/);
  assert.match(block, /!TENANT_ISOLATION_RELEASED/);
  assert.match(block, /423/);
  assert.ok(block.indexOf("funnelPlatformOwner") < block.indexOf('from("funnel_daily_metrics")'));
});

test("service-role branch mutations derive scope from a database-backed branch authorization check", () => {
  const helpers = source.slice(source.indexOf("const actorCanAccessBranch"), source.indexOf("const actorBranchIds"));
  assert.match(helpers, /branches[\s\S]*?select\("tenant_id"\)[\s\S]*?eq\("id"/);
  assert.match(helpers, /tenant_memberships[\s\S]*?eq\("tenant_id"/);
  assert.match(helpers, /branch_assignments[\s\S]*?eq\("branch_id"/);
  for (const [action, marker] of [
    ["erp-open-shift", "branchAccess(branchId)"],
    ["erp-create-pos-sale", "branchAccess(branchId)"],
    ["erp-create-expense", "branchAccess(branchId)"],
    ["erp-create-purchase-requisition", "branchAccess(branchId)"],
    ["erp-create-production-batch", "branchAccess(branchId)"],
    ["erp-create-cash-reconciliation", "branchAccess(branchId)"],
  ]) {
    const start = source.indexOf(`if (action === "${action}")`);
    const next = source.indexOf("\n  if (action ===", start + 1);
    const block = source.slice(start, next === -1 ? undefined : next);
    assert.ok(start >= 0 && block.includes(marker), `missing server-side scope guard for ${action}`);
  }
});


test("every handler using unscoped Head Office helpers remains behind the tenant-isolation release gate", () => {
  const starts = [...source.matchAll(/^  if\\s*\\(action\\s*===\\s*"([^"]+)"\\)/gm)];
  for (let index = 0; index < starts.length; index++) {
    const action = starts[index][1];
    const start = starts[index].index;
    const end = starts[index + 1]?.index ?? source.length;
    const block = source.slice(start, end);
    if (/hasHQPermission\\(|hasFinanceHQ\\(/.test(block)) {
      assert.ok(gatedActions.has(action), `unscoped HQ helper action is not gated: ${action}`);
    }
  }
});
