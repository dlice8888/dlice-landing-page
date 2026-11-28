import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const sql = readFileSync(new URL("../../docs/implementation/sql/EXECUTIVE_T01_T02_APPROVAL_AND_SALES_SOURCE.sql", import.meta.url), "utf8");

test("T01 stores payment instant, branch timezone snapshot and business date without fabricating history", () => {
  assert.match(sql, /add column if not exists paid_at timestamptz/i);
  assert.match(sql, /add column if not exists business_date date/i);
  assert.match(sql, /new\.paid_at := now\(\)/i);
  assert.match(sql, /new\.business_date := \(new\.paid_at at time zone v_timezone\)::date/i);
  assert.match(sql, /Existing paid POS rows are intentionally NOT backfilled/i);
  assert.match(sql, /business_timezone := old\.business_timezone/i);
});

test("T01 KPI definition is versioned and source view is security-invoker", () => {
  assert.match(sql, /create table if not exists public\.executive_kpi_definitions/i);
  assert.match(sql, /sales-monitor\.v2/);
  assert.match(sql, /create or replace view public\.executive_sales_source_v\s+with \(security_invoker=true\)/i);
  assert.match(sql, /payment_settlement/i);
});

test("T02 inbox references source entities and persists claims, delegations and decisions", () => {
  for (const table of ["approval_policies", "approval_inbox_items", "approval_delegations", "approval_claim_events", "approval_decisions"]) {
    assert.match(sql, new RegExp("create table if not exists public\\." + table, "i"));
  }
  assert.match(sql, /source_entity_type text not null/i);
  assert.match(sql, /source_entity_id uuid not null/i);
  assert.match(sql, /source_version timestamptz not null/i);
  assert.match(sql, /unique\(tenant_id,source_entity_type,source_entity_id,source_version\)/i);
});

test("T02 RPCs lock inbox rows and enforce optimistic version, branch scope and separation of duties", () => {
  for (const fn of ["list_pending_approvals", "claim_approval", "decide_approval"]) {
    assert.match(sql, new RegExp("function public\\." + fn, "i"));
  }
  assert.match(sql, /from public\.approval_inbox_items where id=p_approval_id for update/i);
  assert.match(sql, /a\.version<>p_expected_version/i);
  assert.match(sql, /a\.branch_id=any\(coalesce\(p_allowed_branch_ids/i);
  assert.match(sql, /APPROVAL_SELF_APPROVAL_FORBIDDEN/);
  assert.match(sql, /APPROVAL_AMOUNT_LIMIT_EXCEEDED/);
  assert.match(sql, /APPROVAL_SOURCE_STALE_OR_ALREADY_TRANSITIONED/);
  assert.match(sql, /approval_source_is_current/);
  assert.match(sql, /APPROVAL_SOURCE_STALE/);
  assert.match(sql, /allowed_categories/);
  assert.match(sql, /executive\.approval\.'\|\|p_decision/);
});

test("T02 mutates only explicit source tables and keeps client roles denied", () => {
  for (const table of ["purchase_requisitions", "purchase_orders", "branch_expenses", "hr_timesheets"]) {
    assert.match(sql, new RegExp("public\\." + table, "i"));
  }
  assert.match(sql, /revoke all on function public\.decide_approval[\s\S]*?from public,anon,authenticated/i);
  assert.match(sql, /grant execute on function public\.decide_approval[\s\S]*?to service_role/i);
  assert.match(sql, /alter table public\.purchase_orders add constraint purchase_orders_status_check/i);
});

test("T01 preserves paid recognition fields and allocates settlement net deterministically", () => {
  assert.match(sql, /PAID_POS_SALE_STATUS_IMMUTABLE/);
  assert.match(sql, /settlement_allocation_base as/i);
  assert.match(sql, /row_number\(\) over\(partition by i\.settlement_id order by i\.id\)/i);
  assert.match(sql, /st\.tenant_count=1/i);
  assert.match(sql, /st\.allocated_gross_idr=ps\.gross_amount_idr/i);
});

test("T02 uses the verified owner role and blocks creator delegation", () => {
  assert.match(sql, /array\['owner'\]::text\[\]/i);
  assert.match(sql, /d\.delegator_user_id<>a\.created_by/i);
  assert.match(sql, /a\.amount_idr<=p\.max_amount_idr/i);
  assert.match(sql, /updated_at=a\.source_version/i);
});

test("SQL function bodies use valid dollar quoting", () => {
  assert.doesNotMatch(sql, /as \$(?:\s|begin)/i);
  assert.doesNotMatch(sql, /\n\$;\n/);
});

test("T02 delegation create and revoke are audited and branch-scoped", () => {
  assert.match(sql, /function public\.create_approval_delegation/i);
  assert.match(sql, /function public\.revoke_approval_delegation/i);
  assert.match(sql, /APPROVAL_DELEGATE_NOT_ACTIVE_IN_SCOPE/);
  assert.match(sql, /executive\.approval\.delegation\.created/);
  assert.match(sql, /executive\.approval\.delegation\.revoked/);
  assert.match(sql, /d\.delegator_user_id<>a\.created_by/);
});

test("T02 prevents employee self-approval even when another creator submitted the timesheet", () => {
  assert.match(sql, /APPROVAL_EMPLOYEE_SELF_APPROVAL_FORBIDDEN/);
  assert.match(sql, /employee_user_id=p_actor_user_id/);
});

test("T02 delegation cannot exceed policy amount or category", () => {
  assert.match(sql, /p_max_amount_idr>v_policy\.max_amount_idr/i);
  assert.match(sql, /APPROVAL_DELEGATION_POLICY_LIMIT_EXCEEDED/);
  assert.match(sql, /p\.tenant_id=a\.tenant_id and p\.active/i);
});

test("T02 decision history is append-only and idempotent replay is actor-bound", () => {
  assert.match(sql, /revoke update,delete on public\.approval_claim_events,public\.approval_decisions from service_role/i);
  assert.match(sql, /APPROVAL_IDEMPOTENCY_ACTOR_MISMATCH/);
  assert.match(sql, /v_existing_decision\.actor_user_id<>p_actor_user_id/);
});

test("T01 marks settlement net incomplete when any allocation is missing", () => {
  assert.match(sql, /count\(\*\)=count\(sa\.allocated_net_idr\)/i);
  assert.match(sql, /settlement_allocation_complete/i);
});
