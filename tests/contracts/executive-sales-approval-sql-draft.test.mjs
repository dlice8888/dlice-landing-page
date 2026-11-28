import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const sql=await readFile(new URL("../../docs/implementation/sql/EXECUTIVE_SALES_APPROVAL_DRAFT.sql",import.meta.url),"utf8");
test("Executive sales draft derives business date from branch timezone and cutoff",()=>{
 assert.match(sql,/business_day_cutoff time without time zone/);
 assert.match(sql,/s\.created_at at time zone b\.timezone/);
 assert.match(sql,/executive_pos_sales_fact/);
});
test("sales draft links POS sales, processed refunds, settlement and Finance journals",()=>{
 for(const name of ["pos_sales","refund_records","payment_settlement_items","payment_settlements","finance_journal_entries"])
  assert.match(sql,new RegExp("public\\."+name));
 assert.match(sql,/rr\.status='processed'/);
 assert.match(sql,/ps\.status='matched'/);
});
test("sales snapshot RPC is server-only and checks tenant and branch membership",()=>{
 assert.match(sql,/auth\.jwt\(\)->>'role',''\)\s*<>\s*'service_role'/);
 assert.match(sql,/tenant_memberships/);
 assert.match(sql,/branch_assignments/);
 assert.match(sql,/EXECUTIVE_BRANCH_SCOPE_DENIED/);
 assert.match(sql,/revoke all on function public\.executive_sales_monitor_snapshot/);
 assert.doesNotMatch(sql,/grant execute on function public\.executive_sales_monitor_snapshot[^;]*to authenticated/i);
});
test("draft cannot be applied as a migration accidentally",()=>{
 assert.match(sql,/DESIGN DRAFT ONLY/);
 assert.match(sql,/rollback;\s*$/i);
});
test("approval schema is separated from authoritative source entities",()=>{
 for(const name of ["executive_approval_policies","executive_approval_delegations","executive_approval_inbox","executive_approval_decisions"])
  assert.match(sql,new RegExp(name));
 assert.match(sql,/source_entity_id/);
 assert.match(sql,/source_version/);
});
