import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration = readFileSync("supabase/migrations/20261023232000_kitchen_kds_idempotency_modifiers.sql", "utf8");
const edge = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");
const platform = readFileSync("supabase/migrations/20261023233000_tenant_branch_platform_foundation.sql", "utf8");

test("KDS tickets are branch-scoped, source-linked, versioned and idempotent", () => {
  assert.match(migration, /create table if not exists public\.kitchen_tickets/i);
  assert.match(migration, /branch_id uuid not null references public\.branches/i);
  assert.match(migration, /idempotency_key text/i);
  assert.match(migration, /unique index[^;]*kitchen_tickets_order_unique/i);
  assert.match(migration, /unique index[^;]*kitchen_tickets_pos_sale_unique/i);
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /revoke all on table public\.kitchen_tickets from anon, authenticated/i);
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
  assert.match(platform, /revoke all on table public\.%I from anon,authenticated/i);
  assert.match(edge, /tenant_memberships/);
  assert.match(edge, /erp-record-waste/);
  assert.match(edge, /erp-create-shift-handover/);
  assert.match(edge, /erp-save-branch-setting/);
  assert.match(edge, /erp-create-tenant/);
});
