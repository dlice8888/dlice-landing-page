import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const edge = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");
const migration = readFileSync("supabase/migrations/20261124121046_enforce_same_tenant_stock_transfers.sql", "utf8");

test("stock-transfer creation rejects cross-tenant branches before calling the RPC", () => {
  const start = edge.indexOf('if (action === "erp-create-stock-transfer")');
  const end = edge.indexOf('if (action === "erp-transition-stock-transfer")', start);
  assert.ok(start >= 0 && end > start, "stock-transfer create handler must exist");
  const handler = edge.slice(start, end);
  const tenantGuard = handler.indexOf("sourceTenantId !== destinationTenantId");
  const rpcCall = handler.indexOf('admin.rpc("erp_create_stock_transfer"');
  assert.ok(tenantGuard >= 0 && rpcCall > tenantGuard, "tenant equality must be checked before the RPC");
  assert.match(handler, /Transfer stok hanya diizinkan antar cabang dalam tenant yang sama/);
});

test("every stock-transfer transition rejects cross-tenant rows, including platform-owner actions", () => {
  const start = edge.indexOf('if (action === "erp-transition-stock-transfer")');
  const end = edge.indexOf('if (action === "erp-list-stock-counts")', start);
  assert.ok(start >= 0 && end > start, "stock-transfer transition handler must exist");
  const handler = edge.slice(start, end);
  const tenantGuard = handler.indexOf("sourceTenantId !== destinationTenantId");
  const rpcCall = handler.indexOf('admin.rpc("erp_transition_stock_transfer"');
  assert.ok(tenantGuard >= 0 && rpcCall > tenantGuard, "tenant equality must be checked before the RPC");
  assert.doesNotMatch(handler, /sourceTenantId !== destinationTenantId\s*&&\s*!isPlatformOwner/,
    "platform owner must not bypass the intra-tenant stock-transfer boundary");
});

test("database trigger covers insert and branch reassignment and is not directly executable by client roles", () => {
  assert.match(migration, /before insert or update of source_branch_id, destination_branch_id/i);
  assert.match(migration, /perform b\.id[\s\S]*?order by b\.id[\s\S]*?for share/i, "tenant reads must be serialized against branch tenant reassignment");
  assert.match(migration, /v_source_tenant is distinct from v_destination_tenant/i);
  assert.match(migration, /revoke all on function public\.enforce_stock_transfer_same_tenant\(\) from public, anon, authenticated/i);
  assert.match(migration, /before update of tenant_id\s+on public\.branches/i);
  assert.match(migration, /branch_tenant_change_with_stock_transfers_forbidden/);
  assert.match(migration, /revoke all on function public\.prevent_branch_tenant_reassignment_with_stock_transfers\(\) from public, anon, authenticated/i);
  assert.match(migration, /set search_path = pg_catalog, public/i);
});
