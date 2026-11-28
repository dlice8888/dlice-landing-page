import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const migration=readFileSync(new URL("../../supabase/migrations/20261128110000_executive_command_center_persistence.sql",import.meta.url),"utf8");

test("T01 payment recognition stores immutable payment time and branch-local business date",()=>{
 assert.match(migration,/add column if not exists paid_at timestamptz/i);
 assert.match(migration,/add column if not exists business_date date/i);
 assert.match(migration,/at time zone v_timezone/i);
 assert.match(migration,/legacy_created_at_backfill/i);
 assert.match(migration,/payment_status in \('paid','refunded'\)[\s\S]{0,80}paid_at is null/i);
 assert.match(migration,/POS_SALE_REFUND_REQUIRES_PAID_SOURCE/i);
 assert.match(migration,/new\.payment_status = 'refunded' and old\.payment_status <> 'paid'/i);
 assert.match(migration,/POS_SALE_PAYMENT_RECOGNITION_IMMUTABLE/i);
 assert.match(migration,/revoke all on function public\.set_pos_sale_payment_recognition\(\) from public,anon,authenticated,service_role/i);
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
 assert.match(migration,/check\(expected_branch_count >= active_branch_count\)/i);
 assert.match(migration,/v\.reconciled_branch_count is distinct from p_reconciled_branch_count/i);
 assert.match(migration,/executive_persist_command_center_snapshot/i);
 assert.match(migration,/EXECUTIVE_SNAPSHOT_IDEMPOTENCY_KEY_REUSED/i);
 assert.match(migration,/EXECUTIVE_COMMAND_CENTER_PERMISSION_REQUIRED/i);
 assert.match(migration,/where case[\s\S]*?EXECUTIVE_SNAPSHOT_BRANCH_SCOPE_MISMATCH/i);
 assert.match(migration,/insert into public\.executive_command_center_snapshots[\s\S]*?on conflict\(tenant_id,idempotency_key\) do nothing/i);
 assert.match(migration,/get diagnostics v_inserted = row_count/i);
});

test("T02 approval claim is row-locked, versioned, branch-scoped and audited",()=>{
 assert.match(migration,/create table if not exists public\.executive_approval_items/i);
 assert.match(migration,/executive_approval_one_active_source_idx/i);
 assert.match(migration,/create table if not exists public\.executive_approval_delegations/i);
 assert.match(migration,/create table if not exists public\.executive_approval_decisions/i);
 assert.match(migration,/for update/i);
 assert.match(migration,/Recheck after acquiring the row lock/i);
 assert.match(migration,/Recheck after the item lock/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_STALE_VERSION/i);
 assert.match(migration,/p_expected_version is null or p_expected_version<0/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_IDEMPOTENCY_KEY_REUSED/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_BRANCH_SCOPE_DENIED/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_BRANCH_INACTIVE_OR_OUT_OF_SCOPE/i);
 assert.match(migration,/dm\.status='active'/i);
 assert.match(migration,/executive_approval_claim_events/i);
 assert.match(migration,/executive\.approval\.claimed/i);
 assert.match(migration,/decision persistence only/i);
});

test("T02 enqueue and decision mutate supported HR/procurement sources atomically",()=>{
 assert.match(migration,/executive_enqueue_approval/i);
 assert.equal((migration.match(/create or replace function public\.executive_get_sales_monitor/g)||[]).length,1);
 assert.match(migration,/end \$enqueue\$;[\s\S]*?grant execute on function public\.executive_enqueue_approval/i);
 assert.match(migration,/end \$decision\$;[\s\S]*?grant execute on function public\.executive_decide_approval/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_SOURCE_NOT_SUBMITTED/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_ENQUEUE_IDEMPOTENCY_KEY_REUSED/i);
 assert.match(migration,/executive_decide_approval/i);
 assert.match(migration,/for update of r/i);
 assert.match(migration,/for update of l/i);
 assert.match(migration,/erp_transition_purchase_requisition\(\s*v\.source_entity_id::uuid,\s*p_decision,\s*p_actor_user_id,\s*null\)/i);
 assert.match(migration,/hr_review_leave_request\(\s*v\.source_entity_id::uuid,\s*p_actor_user_id,\s*p_decision='approved'/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_SOURCE_VERSION_MISMATCH/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_DELEGATION_REQUIRED/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_SELF_APPROVAL_DENIED/i);
 assert.match(migration,/source mutation are committed in one PostgreSQL transaction/i);
 assert.match(migration,/EXECUTIVE_APPROVAL_SOURCE_ADAPTER_UNSUPPORTED/i);
});
test("T02 delegation lifecycle is tenant-bound, time-limited, idempotent and audited",()=>{
 assert.match(migration,/source_domains text\[\] not null check\(cardinality\(source_domains\)>0 and source_domains <@/i);
 assert.match(migration,/unique\(tenant_id,idempotency_key\)/i);
 assert.match(migration,/executive_create_approval_delegation/i);
 assert.match(migration,/executive_revoke_approval_delegation/i);
 assert.match(migration,/p_valid_until>now\(\)\+interval '90 days'/i);
 assert.match(migration,/EXECUTIVE_DELEGATION_MEMBERSHIP_REQUIRED/i);
 assert.match(migration,/m\.permissions \?\| p_source_domains/i);
 assert.match(migration,/p_source_domains <@ array\['procurement','hr'\]/i);
 assert.match(migration,/EXECUTIVE_DELEGATION_IDEMPOTENCY_KEY_REUSED/i);
 assert.match(migration,/executive\.approval\.delegation\.created/i);
 assert.match(migration,/executive\.approval\.delegation\.revoked/i);
 assert.match(migration,/v_platform_owner boolean/i);
});
test("new executive tables and RPCs are not directly exposed to browser roles",()=>{
 assert.match(migration,/revoke all on public\.%I from anon,authenticated/i);
 assert.match(migration,/revoke all on function public\.executive_claim_approval/i);
 assert.match(migration,/grant execute on function public\.executive_claim_approval[\s\S]*to service_role/i);
 assert.match(migration,/revoke all on function public\.executive_get_sales_monitor/i);
});
