import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const sql=await readFile(new URL("../../docs/implementation/sql/POS_SHIFT_CASH_DRAFT.sql",import.meta.url),"utf8");
test("shift and cash ledger tables are tenant and branch scoped with idempotency",()=>{
 assert.match(sql,/pos_shift_cash_movements/);assert.match(sql,/unique\(tenant_id,branch_id,shift_id,idempotency_key\)/);
 assert.match(sql,/foreign key\(tenant_id,branch_id\) references public\.branches\(tenant_id,id\)/);
 assert.match(sql,/payload_fingerprint/);
});
test("shift open and close are service-only and transactionally audited",()=>{
 assert.match(sql,/pos_open_shift_atomic/);assert.match(sql,/pos_close_shift_atomic/);
 assert.match(sql,/auth\.jwt\(\)->>'role',''\)<>\s*'service_role'/);
 assert.match(sql,/pg_advisory_xact_lock/);assert.match(sql,/for update/);
 assert.match(sql,/pos_shift_already_open/);assert.match(sql,/pos_shift_close_race/);
 assert.match(sql,/pos_shift_closed/);assert.match(sql,/pos_shift_opened/);
});
test("drawer expected cash is derived from source sales, tenders, refunds and cash movements",()=>{
 for(const term of ["pos_sales","pos_sale_tenders","refund_records","pos_shift_cash_movements"])
  assert.match(sql,new RegExp("public\\."+term));
 assert.match(sql,/opening_cash_idr\+v_sales\+v_in-v_out-v_refunds/);
 assert.match(sql,/pos_shift_variance_threshold_idr/);
 assert.match(sql,/pos_shift_variance_approval_required/);
});
test("cash movement and reconciliation require shift ownership or supervisor and write audit",()=>{
 assert.match(sql,/pos_shift_actor_scope_denied/);
 assert.match(sql,/pos_cash_reconciled/);
 assert.match(sql,/pos_cash_\|\|p_movement_type/);
 assert.match(sql,/pos_cash_reconciliation_snapshots/);
 assert.match(sql,/rollback;\s*$/i);
});
