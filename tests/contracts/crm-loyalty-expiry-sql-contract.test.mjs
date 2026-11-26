import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const sql = readFileSync(new URL("../../docs/implementation/sql/CRM_LOYALTY_EXPIRY_EXTENSION_DRAFT.sql", import.meta.url), "utf8");

test("loyalty expiry requires an approved, bounded validity policy", () => {
  assert.match(sql, /points_validity_days integer null/);
  assert.match(sql, /APPROVED_EARNING_RULE_WITH_VALIDITY_REQUIRED/);
  assert.match(sql, /v_close\.reconciled_at\+make_interval\(days=>v_rule\.points_validity_days\)/);
  assert.match(sql, /FINANCIAL_CLOSE_RECONCILIATION_TIMESTAMP_REQUIRED/);
});

test("earn awards are source-backed by reconciled POS/order and Finance close", () => {
  assert.match(sql, /crm_financial_close_projections/);
  assert.match(sql, /finance_source_reconciliation_status<>'reconciled'/);
  assert.match(sql, /crm_transaction_links/);
  assert.match(sql, /entry_kind,points,idempotency_key,source_reference,created_by,expires_at/);
});

test("redemption allocates points FIFO to unexpired earn lots atomically", () => {
  assert.match(sql, /crm_loyalty_point_allocations/);
  assert.match(sql, /order by expires_at nulls last,created_at,id for update/);
  assert.match(sql, /LOYALTY_EARN_LOT_ALLOCATION_MISMATCH/);
  assert.match(sql, /allocation_kind,points_allocated/);
});

test("expiry removes only unspent points and is idempotent per earn lot", () => {
  assert.match(sql, /crm_expire_loyalty_points/);
  assert.match(sql, /crm-expire:/);
  assert.match(sql, /greatest\(v_lot\.points-v_allocated,0\)/);
  assert.match(sql, /crm\.loyalty\.points_expired/);
});

test("generic ledger RPC cannot bypass source-backed earn/redeem and reversal restores redemption allocations", () => {
  assert.match(sql, /USE_FINANCIAL_CLOSE_OR_REWARD_REDEMPTION_RPC/);
  assert.match(sql, /redemption_reversal/);
  assert.match(sql, /EARN_ENTRY_ALREADY_CONSUMED_OR_EXPIRED/);
  assert.match(sql, /ADJUSTMENT_REVERSAL_REQUIRES_NEW_ADJUSTMENT/);
  assert.match(sql, /REDEMPTION_REVERSAL_AFTER_EXPIRY_BLOCKED/);
  assert.match(sql, /earn_reversal/);
  assert.match(sql, /v_entry\.id,v_original\.id,\x27earn_reversal\x27,v_original\.points/);
  assert.equal((sql.match(/when allocation_kind in \\\(\\x27redemption\\x27,\\x27earn_reversal\\x27,\\x27expiry\\x27\\) then points_allocated/g)||[]).length,3);
  assert.match(sql, /entry_kind='adjustment' and points>0/);
});

test("allocation and ledger write paths remain append-only and service-role-only", () => {
  assert.match(sql, /crm_loyalty_point_allocations_append_only/);
  assert.match(sql, /revoke all on public\.crm_loyalty_point_allocations from public,anon,authenticated/);
  assert.match(sql, /grant select,insert on public\.crm_loyalty_point_allocations to service_role/);
  assert.match(sql, /revoke all on function public\.crm_expire_loyalty_points\(uuid,uuid,uuid\) from public,anon,authenticated/);
});
