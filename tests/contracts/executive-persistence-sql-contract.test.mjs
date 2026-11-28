import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const migration=readFileSync(new URL("../../supabase/migrations/20261128110000_executive_command_center_persistence.sql",import.meta.url),"utf8");

test("T01 payment recognition stores immutable payment time and branch-local business date",()=>{
 assert.match(migration,/add column if not exists paid_at timestamptz/i);
 assert.match(migration,/add column if not exists business_date date/i);
 assert.match(migration,/at time zone v_timezone/i);
 assert.match(migration,/legacy_created_at_backfill/i);
 assert.match(migration,/POS_SALE_PAYMENT_RECOGNITION_IMMUTABLE/i);
 assert.match(migration,/POS_SALE_PAID_BRANCH_IMMUTABLE/i);
 assert.match(migration,/POS_SALE_PAID_STATUS_TERMINAL/i);
});

test("T01 sales monitor separates paid sales, processed refunds and reconciled settlement",()=>{
 assert.match(migration,/executive_get_sales_monitor/i);
 assert.match(migration,/s\.payment_status in \('paid','refunded'\)/i);
 assert.match(migration,/r\.status='processed'/i);
 assert.match(migration,/r\.pos_sale_id is not null/i);
 assert.match(migration,/EXECUTIVE_SALES_SOURCE_TOTAL_MISMATCH/i);
 assert.match(migration,/EXECUTIVE_PROCESSED_REFUND_EXCEEDS_SALE/i);
 assert.match(migration,/ps\.status='matched'/i);
 assert.match(migration,/EXECUTIVE_SALES_MONITOR_TENANT_SCOPE_DENIED/i);
 assert.match(migration,/EXECUTIVE_SALES_MONITOR_BRANCH_SCOPE_DENIED/i);
 assert.match(migration,/not exists\(select 1 from public\.payment_settlement_items/i);
});

test("T01 persisted read model is tenant-bound, versioned and idempotent",()=>{
 assert.match(migration,/create table if not exists public\.executive_command_center_snapshots/i);
 assert.match(migration,/formula_version integer not null/i);
 assert.match(migration,/unique\(tenant_id,idempotency_key\)/i);
 assert.match(migration,/executive_persist_command_center_snapshot/i);
 assert.match(migration,/EXECUTIVE_COMMAND_CENTER_PERMISSION_REQUIRED/i);
 assert.match(migration,/where case[\s\S]*?EXECUTIVE_SNAPSHOT_BRANCH_SCOPE_MISMATCH/i);
 assert.match(migration,/insert into public\.executive_command_center_snapshots[\s\S]*?on conflict\(tenant_id,idempotency_key\) do nothing/i);
 assert.match(migration,/get diagnostics v_inserted = row_count/i);
});

test("T02 approval claim is row-locked, versioned, branch-scoped and audited",()=>{
 assert.match(migration,/create table if not exists public\.executive_approval_items/i);
 assert.match(migration,/create table if not exists public\.executive_approval_delegations/i);
 assert.match(migration,/create table if not exists public\.executive_approval_decisions/i);
 assert.match(migration,/for update/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_STALE_VERSION/i);
 assert.match(migration,/p_expected_version is null or p_expected_version<0/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_BRANCH_SCOPE_DENIED/i);
 assert.match(migration,/executive_approval_claim_events/i);
 assert.match(migration,/executive\.approval\.claimed/i);
 assert.match(migration,/decision persistence only/i);
});

test("new executive tables and RPCs are not directly exposed to browser roles",()=>{
 assert.match(migration,/revoke all on public\.%I from anon,authenticated/i);
 assert.match(migration,/revoke all on function public\.executive_claim_approval/i);
 assert.match(migration,/grant execute on function public\.executive_claim_approval[\s\S]*to service_role/i);
 assert.match(migration,/revoke all on function public\.executive_get_sales_monitor/i);
});
