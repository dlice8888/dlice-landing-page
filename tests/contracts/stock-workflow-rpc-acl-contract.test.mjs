import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migration = await readFile("supabase/migrations/20261118193000_revoke_public_stock_workflow_rpc_execute.sql", "utf8");
const edge = await readFile("supabase/functions/dlice-orders/index.ts", "utf8");
const workflow = await readFile(".github/workflows/quality-checks.yml", "utf8");

const functions = [
  ["erp_create_stock_count", "text, uuid, jsonb, uuid, text, text"],
  ["erp_create_stock_transfer", "text, uuid, uuid, jsonb, uuid, text, text"],
  ["erp_post_stock_count", "uuid, uuid"],
  ["erp_transition_stock_transfer", "uuid, uuid, text"],
  ["erp_update_stock_count_item", "uuid, uuid, numeric"],
];

test("all stock workflow SECURITY DEFINER RPCs revoke client EXECUTE and retain service_role", () => {
  for (const [name, signature] of functions) {
    assert.ok(migration.includes(`REVOKE ALL ON FUNCTION public.${name}(${signature}) FROM PUBLIC, anon, authenticated;`), name);
    assert.ok(migration.includes(`GRANT EXECUTE ON FUNCTION public.${name}(${signature}) TO service_role;`), name);
    assert.ok(edge.includes(`admin.rpc("${name}"`), `${name} must use the trusted admin client`);
  }
});

test("CI executes this RPC ACL contract", () => {
  assert.ok(workflow.includes("tests/contracts/stock-workflow-rpc-acl-contract.test.mjs"));
});
