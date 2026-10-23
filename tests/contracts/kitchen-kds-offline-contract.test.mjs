import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration = readFileSync("supabase/migrations/20261023232000_kitchen_kds_idempotency_modifiers.sql", "utf8");
const edge = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");
const platform = readFileSync("supabase/migrations/20261023233000_tenant_branch_platform_foundation.sql", "utf8");
const tenantIntegrity = readFileSync("supabase/migrations/20261023180000_tenant_branch_integrity_constraints.sql", "utf8");
const posDispatch = readFileSync("supabase/migrations/20261023181000_kds_pos_deferred_dispatch.sql", "utf8");
const ui = readFileSync("erp.html", "utf8");

test("KDS tickets are branch-scoped, source-linked, versioned and idempotent", () => {
  assert.match(migration, /create table if not exists public\.kitchen_tickets/i);
  assert.match(migration, /branch_id uuid not null references public\.branches/i);
  assert.match(migration, /idempotency_key text/i);
  assert.match(migration, /unique index[^;]*kitchen_tickets_order_unique/i);
  assert.match(migration, /unique index[^;]*kitchen_tickets_pos_sale_unique/i);
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /revoke all on table public\.%I from anon, authenticated/i);
});

test("order and POS events create KDS tickets without duplicating a source", () => {
  assert.match(migration, /create or replace function public\.dlice_dispatch_kitchen_ticket/i);
  assert.match(migration, /create trigger[^;]*kitchen_ticket/i);
  assert.match(migration, /on conflict do nothing/i);
  assert.match(migration, /payment_status\s*=\s*'paid'/i);
});

test("POS retry key returns the original result and rejects changed payloads", () => {
  assert.match(migration, /create table if not exists public\.pos_idempotency_requests/i);
  assert.match(migration, /payload_fingerprint/i);
  assert.match(migration, /create or replace function public\.erp_create_pos_sale_idempotent/i);
  assert.match(edge, /erp-create-pos-sale/);
  assert.match(edge, /erp_create_pos_sale_idempotent/);
  assert.match(edge, /idempotency_key/);
});

test("KDS API enforces operational permission and branch scope", () => {
  assert.match(edge, /erp-list-kitchen-tickets/);
  assert.match(edge, /erp-transition-kitchen-ticket/);
  assert.match(edge, /branchAccess\(/);
  assert.match(edge, /kitchen_ticket_transition/i);
});

test("modifier and substitution snapshots preserve the sale-time recipe choice", () => {
  assert.match(migration, /create table if not exists public\.product_modifiers/i);
  assert.match(migration, /create table if not exists public\.recipe_substitutions/i);
  assert.match(migration, /modifier_snapshot jsonb/i);
  assert.match(migration, /substitution_snapshot jsonb/i);
});

test("offline sync receipt records deduplicate device operations", () => {
  assert.match(migration, /create table if not exists public\.offline_sync_receipts/i);
  assert.match(migration, /device_id text not null/i);
  assert.match(migration, /client_operation_id text not null/i);
  assert.match(migration, /unique\s*\(device_id, client_operation_id\)/i);
});

test("paid online orders and POS sales consume recipe stock atomically", () => {
  assert.match(migration, /create table if not exists public\.order_stock_consumptions/i);
  assert.match(migration, /create or replace function public\.dlice_consume_order_recipe_stock/i);
  assert.match(migration, /reference_type,reference_id,notes,created_by/i);
  assert.match(migration, /active_recipe_required/i);
  assert.match(migration, /insufficient_stock/i);
});

test("tenant membership, branch settings, warehouse, waste, handover and integrations have private data boundaries", () => {
  for (const table of ["tenants","tenant_memberships","tenant_invites","warehouses","branch_settings","shift_handover_records","inventory_waste_events","integration_connections","integration_outbox","backup_restore_runs"]) {
    assert.match(platform, new RegExp("create table if not exists public\\."+table, "i"));
    assert.match(platform, new RegExp("'"+table+"'", "i"));
  }
  assert.match(platform, /enable row level security/i);
  assert.match(migration, /revoke all on table public\.%I from anon, authenticated/i);
  assert.match(edge, /tenant_memberships/);
  assert.match(edge, /erp-record-waste/);
  assert.match(edge, /erp-create-shift-handover/);
  assert.match(edge, /erp-save-branch-setting/);
  assert.match(edge, /erp-create-tenant/);
});

test("ERP UI exposes KDS, offline replay, modifiers, substitutions, waste and handover controls", () => {
  for (const id of ["loadKitchenTickets","syncOfflineSales","modifierForm","substitutionForm","stockTrackingForm","wasteForm","handoverForm","tenantForm","tenantInviteForm","branchSettingForm","integrationForm","backupRunForm"]) {
    assert.match(ui, new RegExp('id="' + id + '"'));
  }
  assert.match(ui, /indexedDB\.open\(OFFLINE_DB/);
  assert.match(ui, /TRANSAKSI BELUM DIKONFIRMASI SERVER/);
  assert.match(ui, /erp-sync-offline-operation/);
});

test("tenant migration has balanced SQL dollar quotes and no duplicated table declarations", () => {
  assert.equal((platform.match(/\$\$/g) || []).length % 2, 0, "PL/pgSQL dollar quotes must be balanced");
  assert.doesNotMatch(platform, /as \$\n/, "PL/pgSQL function body must use a valid dollar-quote delimiter");
  assert.doesNotMatch(platform, /payload_fingerprint ~ '\^\[0-9a-f\]\{64\} check/, "waste idempotency fingerprint constraint must be complete");
  const declarations = [...platform.matchAll(/create table if not exists public\.(\w+)/gi)].map(m => m[1]);
  assert.equal(new Set(declarations).size, declarations.length, "each platform table should be declared once per migration");
});

test("tenant and branch identifiers are constrained consistently by composite foreign keys", () => {
  assert.match(tenantIntegrity, /unique\(tenant_id,id\)/i);
  assert.match(tenantIntegrity, /foreign key\(tenant_id,branch_id\) references public\.branches\(tenant_id,id\)/i);
  assert.match(tenantIntegrity, /foreign key\(branch_id,warehouse_id\) references public\.warehouses\(branch_id,id\)/i);
  assert.match(tenantIntegrity, /integration_outbox_tenant_branch_fkey/i);
});

test("POS KDS dispatch is deferred until sale lines and snapshots are written", () => {
  assert.match(posDispatch, /create constraint trigger dlice_kitchen_ticket_from_pos_sale/i);
  assert.match(posDispatch, /deferrable initially deferred/i);
  assert.match(posDispatch, /execute function public\.dlice_dispatch_kitchen_ticket/i);
});

test("POS reconciliation cross-checks sale lines, KDS, stock ledger, balances and audit", () => {
  assert.match(edge, /action === "erp-reconcile-pos-sale"/);
  assert.match(edge, /reference_type","pos_sale"/);
  assert.match(edge, /stock_movements/);
  assert.match(edge, /kitchen_ticket_items/);
  assert.match(edge, /audit_events/);
  assert.match(edge, /branchAccess\(branchId\)/);
});
