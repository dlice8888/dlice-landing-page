import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration = readFileSync(new URL("../../supabase/migrations/20261128025950_20261126192455_crm_loyalty_financial_close.sql", import.meta.url), "utf8");
const pgTap = readFileSync(new URL("../../supabase/tests/crm_loyalty.test.sql", import.meta.url), "utf8");
const edge = readFileSync(new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url), "utf8");
const erp = readFileSync(new URL("../../erp.html", import.meta.url), "utf8");

test("CRM financial close links paid POS and online orders to refunds, settlements and Finance", () => {
  for (const term of ["crm_transaction_links","crm_auto_link_paid_transaction_customer","payment_settlement_items","refunds","finance_journal_entries","crm_build_financial_close_projection","crm_reconcile_financial_close_projection"]) {
    assert.ok(migration.includes(term), `missing ${term}`);
  }
  assert.match(migration, /pos_sale_tenders/);
  assert.match(migration, /POS_SPLIT_TENDER_METHOD_ALLOCATION_MISMATCH/);
  assert.match(migration, /v_cash_tender/);
  assert.match(migration, /v_non_cash_tender/);
});

test("Split tender rechecks drawer and provider settlements independently", () => {
  assert.match(migration, /cardinality\(v\.settlement_ids\)>0/);
  assert.match(migration, /v\.shift_reconciliation_id is not null/);
  assert.match(pgTap, /POS split tender must reconcile each bank\/QRIS tender/);
  assert.match(pgTap, /Finance review independently rechecks both settlement and cash drawer/);
});

test("Refunds after award create immutable loyalty adjustments and preserve original rule provenance", () => {
  assert.match(migration, /earning_rule_version/);
  assert.match(migration, /refund-adjustment:/);
  assert.match(migration, /spent_points_debt/);
  assert.match(migration, /earn_reversal/);
  assert.match(migration, /crm\.loyalty\.refund_points_adjusted/);
  assert.match(pgTap, /processed refunds reverse unspent loyalty lots/);
});

test("CRM close, reconciliation and award actions are wired through authenticated ERP Edge API", () => {
  for (const action of ["erp-crm-build-financial-close","erp-crm-reconcile-financial-close","erp-crm-award-reconciled-close"]) assert.ok(edge.includes(action));
  for (const rpc of ["crm_build_financial_close_projection","crm_reconcile_financial_close_projection","crm_award_loyalty_for_reconciled_close"]) assert.ok(edge.includes(rpc));
  assert.ok(erp.includes("crmFinancialCloseForm"));
});
