import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("recovered staging migration preserves all nine recorded FK indexes", async () => {
  const sql = await readFile("supabase/migrations/20261022140302_add_missing_fk_supporting_indexes.sql", "utf8");
  const expected = [
    "branch_operation_checklist_runs_completed_by_idx",
    "branch_operation_checklist_runs_started_by_idx",
    "stock_count_items_inventory_item_id_idx",
    "stock_counts_counted_by_idx",
    "stock_counts_posted_by_idx",
    "stock_transfer_items_inventory_item_id_idx",
    "stock_transfers_received_by_idx",
    "stock_transfers_requested_by_idx",
    "stock_transfers_shipped_by_idx",
  ];
  for (const name of expected) {
    assert.ok(sql.includes("CREATE INDEX IF NOT EXISTS " + name), "missing exact recovered index " + name);
  }
  assert.equal((sql.match(/CREATE INDEX IF NOT EXISTS/g) || []).length, 9);
  assert.doesNotMatch(sql, /DROP\s+TABLE|DELETE\s+FROM|UPDATE\s+public\./i);
});
