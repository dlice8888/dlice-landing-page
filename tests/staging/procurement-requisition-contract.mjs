import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile("supabase/migrations/20261023170000_purchase_requisitions.sql", "utf8");
const edge = await readFile("supabase/functions/dlice-orders/index.ts", "utf8");
const ui = await readFile("erp.html", "utf8");

assert.match(migration, /create table if not exists public\.purchase_requisitions/i);
assert.match(migration, /create table if not exists public\.purchase_requisition_items/i);
assert.match(migration, /enable row level security/i);
assert.match(migration, /erp_create_purchase_requisition/i);
assert.match(migration, /erp_transition_purchase_requisition/i);
assert.match(migration, /revoke all on table public\.purchase_requisitions/i);
assert.match(edge, /"erp-list-purchase-requisitions"\s*:\s*"procurement"/);
assert.match(edge, /"erp-create-purchase-requisition"\s*:\s*"procurement"/);
assert.match(edge, /"erp-transition-purchase-requisition"\s*:\s*"procurement"/);
assert.match(edge, /action === "erp-list-purchase-requisitions"/);
assert.match(edge, /action === "erp-create-purchase-requisition"/);
assert.match(edge, /action === "erp-transition-purchase-requisition"/);
assert.match(edge, /erp_create_purchase_requisition/);
assert.match(edge, /erp_transition_purchase_requisition/);
assert.match(edge, /old\.requested_by === actor\.user\.id/);
assert.match(edge, /Pembuat requisition tidak boleh menyetujui atau menolak requisition sendiri/);
assert.match(ui, /r\.requested_by!==session\.user\.id/);
assert.match(ui, /id="prForm"/);
assert.match(ui, /id="prList"/);
assert.match(ui, /erp-list-purchase-requisitions/);
assert.match(ui, /erp-create-purchase-requisition/);
assert.match(ui, /erp-transition-purchase-requisition/);

console.log("PASS: purchase requisition migration, permission map, branch-scoped actions, and ERP UI contract.");
