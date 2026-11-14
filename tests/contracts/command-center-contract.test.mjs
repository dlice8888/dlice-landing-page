import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration = readFileSync(
  "supabase/migrations/20261114110000_command_center_summary.sql",
  "utf8",
);
const edge = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");
const ui = readFileSync("erp.html", "utf8");

test("command-center summary is service-role-only and validates bounded date and branch input", () => {
  assert.match(migration, /create or replace function public\.dlice_get_command_center_summary/i);
  assert.match(migration, /security invoker/i, "RPC runs with invoker privileges");
  assert.doesNotMatch(migration, /security definer/i, "RPC must not bypass RLS via SECURITY DEFINER");
  assert.doesNotMatch(migration, /auth\\.role\\(/i, "authorization relies on EXECUTE ACL rather than deprecated auth.role()");
  assert.match(migration, /cardinality\(p_branch_ids\)\s*>\s*500/i);
  assert.match(migration, /p_through_date\s*-\s*p_from_date\s*>\s*92/i);
  assert.match(migration, /revoke all on function public\.dlice_get_command_center_summary/i);
  assert.match(migration, /grant execute on function public\.dlice_get_command_center_summary[^;]*to service_role/i);
});

test("summary uses branch-local dates and actual operational tables", () => {
  assert.match(migration, /p_from_date::timestamp\s+at time zone\s+b\.timezone/i);
  assert.match(migration, /\(p_through_date\s*\+\s*1\)::timestamp\s+at time zone\s+b\.timezone/i);
  assert.match(migration, /pos_sales/i);
  assert.match(migration, /payment_status\s*=\s*'paid'/i);
  assert.match(migration, /branch_inventory/i);
  assert.match(migration, /inventory_items/i);
  assert.match(migration, /i\.is_active\s*=\s*true and b\.status\s*<>\s*'planned'/i);
  assert.match(migration, /pos_shifts/i);
  assert.match(migration, /kitchen_tickets/i);
  assert.match(migration, /purchase_requisitions/i);
  assert.match(migration, /branch_expenses/i);
});

test("command-center API remains release-gated and reports database errors", () => {
  assert.match(edge, /const TENANT_ISOLATION_RELEASED = false/);
  assert.match(edge, /"erp-overview"[\s\S]{0,80}"erp-reports"/);
  assert.match(edge, /if \(action === "erp-overview"\)[\s\S]*?if \(!isOwner\)/);
  assert.match(edge, /dlice_get_command_center_summary/);
  assert.match(edge, /ringkasan operasional gagal dimuat/i);
  assert.match(edge, /const SUPPORTED_BRANCH_TIMEZONES = new Set/);
  assert.match(edge, /Zona waktu cabang tidak didukung/);
  assert.match(migration, /unsupported_branch_timezone/);
});

test("ERP command center exposes date and branch filters and actual transaction KPIs", () => {
  for (const id of ["overviewFrom", "overviewThrough", "overviewBranch", "loadOverview", "overviewBranches"]) {
    assert.match(ui, new RegExp(`id="${id}"`));
  }
  assert.ok(/const filters=\{from_date:\$\('overviewFrom'\)\.value,through_date:\$\('overviewThrough'\)\.value\}/.test(ui), "date inputs reach the API");
  assert.ok(/Transaksi terbayar/.test(ui), "paid transaction KPI is visible");
  assert.ok(/Rata-rata transaksi/.test(ui), "average-order-value KPI is visible");
  assert.ok(/overviewBranches/.test(ui), "branch performance table is rendered");
});
