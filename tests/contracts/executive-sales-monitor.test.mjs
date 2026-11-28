import test from "node:test";
import assert from "node:assert/strict";
import {getExecutiveSalesMonitor} from "../../src/executive-sales-monitor.mjs";
const snapshot=(overrides={})=>({snapshot_id:"snap1",tenant_id:"t1",period_type:"day",formula_version:"sales-net-v1",
 totals:{gross_idr:100000,discount_idr:10000,refund_idr:5000,net_sales_idr:85000,matched_settlement_idr:85000,transaction_count:1},
 daily:[{business_date:"2026-11-28",gross_idr:100000,discount_idr:10000,refund_idr:5000,net_sales_idr:85000,matched_settlement_idr:85000,transaction_count:1}],
 transactions:[{sale_id:"s1",branch_id:"b1",business_date:"2026-11-28",paid_at:"2026-11-28T04:00:00Z",paid_at_source:"provider_confirmed",timezone:"Asia/Jakarta",cutoff_time:"00:00:00",business_day_policy_version:1,gross_idr:100000,discount_idr:10000,processed_refund_idr:5000,net_sales_idr:85000,matched_settlement_idr:85000}],
 payment_reconciliation:{sale_count:1,tender_mismatch_count:0,tender_allocations_balanced:true,legacy_paid_at_count:0},
 finance_reconciliation:{sale_count:1,sale_without_journal_count:0,linked_journal_entry_count:1,sale_journal_amount_idr:100000,refund_journal_amount_idr:5000,refunds_without_journal_count:0,sale_journal_mismatch_count:0,refund_journal_mismatch_count:0,status:"reconciled"},...overrides});
const input={tenantId:"t1",actorId:"u1",period:"day",startDate:"2026-11-28",endDate:"2026-11-28"};
const deps=(value=snapshot())=>({loadSalesMonitorSnapshot:async()=>value});
test("returns the authoritative snapshot with gross, discount, processed refund and net totals",async()=>{
 const r=await getExecutiveSalesMonitor(input,deps());assert.equal(r.totals.gross_idr,100000);assert.equal(r.totals.discount_idr,10000);
 assert.equal(r.totals.refund_idr,5000);assert.equal(r.totals.net_sales_idr,85000);assert.equal(r.totals.matched_settlement_idr,85000);
});
test("marks T01 source reconciliation complete only when POS, payment and Finance counts and journals reconcile",async()=>{
 const r=await getExecutiveSalesMonitor(input,deps());assert.equal(r.reconciliation_status,"source_reconciled");
 const incomplete=snapshot({finance_reconciliation:{...snapshot().finance_reconciliation,sale_without_journal_count:1,status:"incomplete"}});
 assert.equal((await getExecutiveSalesMonitor(input,deps(incomplete))).reconciliation_status,"reconciliation_incomplete");
});
test("does not forward client-controlled timezone; branch business dates come from the SQL view",async()=>{
 let received;const d={loadSalesMonitorSnapshot:async q=>(received=q,snapshot())};
 await getExecutiveSalesMonitor({...input,timezone:"Pacific/Honolulu"},d);
 assert.equal("timezone" in received,false);assert.equal(received.tenantId,"t1");
});
test("passes branch filter to the single atomic snapshot RPC adapter",async()=>{
 let received;const d={loadSalesMonitorSnapshot:async q=>(received=q,snapshot({branch_ids:["b1"]}))};
 await getExecutiveSalesMonitor({...input,branchIds:["b1"]},d);assert.deepEqual(received.branchIds,["b1"]);
});
test("rejects duplicate branch IDs, invalid date, reversed range and unsupported period",async()=>{
 await assert.rejects(getExecutiveSalesMonitor({...input,branchIds:["b1","b1"]},deps()),{code:"EXEC_SALES_BRANCH_FILTER_INVALID"});
 await assert.rejects(getExecutiveSalesMonitor({...input,startDate:"2026-02-31"},deps()),{code:"EXEC_SALES_DATE_INVALID"});
 await assert.rejects(getExecutiveSalesMonitor({...input,startDate:"2026-11-29",endDate:"2026-11-28"},deps()),{code:"EXEC_SALES_RANGE_INVALID"});
 await assert.rejects(getExecutiveSalesMonitor({...input,period:"quarter"},deps()),{code:"EXEC_SALES_PERIOD_INVALID"});
});
test("accepts valid ISO calendar dates and rejects malformed date strings",async()=>{
 await getExecutiveSalesMonitor(input,deps());
 await assert.rejects(getExecutiveSalesMonitor({...input,startDate:"28-11-2026"},deps()),{code:"EXEC_SALES_DATE_INVALID"});
});
test("rejects incomplete snapshot and mismatched tenant",async()=>{
 await assert.rejects(getExecutiveSalesMonitor(input,deps({snapshot_id:"x"})),{code:"EXEC_SALES_SNAPSHOT_INVALID"});
 await assert.rejects(getExecutiveSalesMonitor(input,deps(snapshot({tenant_id:"t2"}))),{code:"EXEC_SALES_SNAPSHOT_INVALID"});
});
test("rejects negative or unsafe aggregate totals",async()=>{
 await assert.rejects(getExecutiveSalesMonitor(input,deps(snapshot({totals:{...snapshot().totals,net_sales_idr:-1}}))),{code:"EXEC_SALES_TOTAL_INVALID"});
});

test("rejects aggregate totals that do not reconcile to daily and source transaction rows",async()=>{
 const bad=snapshot({totals:{...snapshot().totals,net_sales_idr:86000}});
 await assert.rejects(getExecutiveSalesMonitor(input,deps(bad)),{code:"EXEC_SALES_RECONCILIATION_MISMATCH"});
});
test("rejects a source transaction outside the requested branch/date scope",async()=>{
 const bad=snapshot({transactions:[{...snapshot().transactions[0],branch_id:"b2"}]});
 await assert.rejects(getExecutiveSalesMonitor({...input,branchIds:["b1"]},deps(bad)),{code:"EXEC_SALES_SOURCE_SCOPE_INVALID"});
});
test("rejects a snapshot period that differs from the requested period",async()=>{
 await assert.rejects(getExecutiveSalesMonitor({...input,period:"week"},deps(snapshot())),{code:"EXEC_SALES_SNAPSHOT_INVALID"});
});

test("recomputes immutable business date using WIB, WITA and WIT branch-local cutoff",async()=>{
 const rows=[
  {sale_id:"wib",branch_id:"b1",business_date:"2026-11-28",paid_at:"2026-11-28T16:59:00Z",paid_at_source:"provider_confirmed",timezone:"Asia/Jakarta",cutoff_time:"00:00:00",business_day_policy_version:2},
  {sale_id:"wita",branch_id:"b2",business_date:"2026-11-29",paid_at:"2026-11-28T16:00:00Z",paid_at_source:"provider_confirmed",timezone:"Asia/Makassar",cutoff_time:"00:00:00",business_day_policy_version:2},
  {sale_id:"wit",branch_id:"b3",business_date:"2026-11-29",paid_at:"2026-11-28T15:30:00Z",paid_at_source:"provider_confirmed",timezone:"Asia/Jayapura",cutoff_time:"00:00:00",business_day_policy_version:2}
 ].map(row=>({...snapshot().transactions[0],...row}));
 const daily=[
  {business_date:"2026-11-28",gross_idr:100000,discount_idr:10000,refund_idr:5000,net_sales_idr:85000,matched_settlement_idr:85000,transaction_count:1},
  {business_date:"2026-11-29",gross_idr:200000,discount_idr:20000,refund_idr:10000,net_sales_idr:170000,matched_settlement_idr:170000,transaction_count:2}
 ];
 const value=snapshot({transactions:rows,daily,totals:{gross_idr:300000,discount_idr:30000,refund_idr:15000,net_sales_idr:255000,matched_settlement_idr:255000,transaction_count:3},payment_reconciliation:{sale_count:3,tender_mismatch_count:0,tender_allocations_balanced:true,legacy_paid_at_count:0},finance_reconciliation:{...snapshot().finance_reconciliation,sale_count:3}});
 await getExecutiveSalesMonitor({...input,endDate:"2026-11-29"},deps(value));
});
test("rejects a source row whose stored business date disagrees with branch timezone and cutoff",async()=>{
 const bad=snapshot({transactions:[{...snapshot().transactions[0],business_date:"2026-11-29",cutoff_time:"00:00:00",business_day_policy_version:1}]});
 await assert.rejects(getExecutiveSalesMonitor(input,deps(bad)),{code:"EXEC_SALES_BUSINESS_DATE_MISMATCH"});
});
test("rejects source rows without captured cutoff provenance",async()=>{
 const bad=snapshot({transactions:[{...snapshot().transactions[0],cutoff_time:null}]});
 await assert.rejects(getExecutiveSalesMonitor(input,deps(bad)),{code:"EXEC_SALES_SOURCE_CUTOFF_INVALID"});
});


test("keeps explicitly backfilled legacy paid rows visible but never reconciled",async()=>{
 const legacy=snapshot({
  transactions:[{...snapshot().transactions[0],paid_at_source:"legacy_created_at_backfill",business_day_policy_version:0}],
  payment_reconciliation:{...snapshot().payment_reconciliation,legacy_paid_at_count:1}
 });
 const result=await getExecutiveSalesMonitor(input,deps(legacy));
 assert.equal(result.transactions.length,1);
 assert.equal(result.reconciliation_status,"reconciliation_incomplete");
});

test("rejects unversioned non-legacy payment recognition",async()=>{
 const unversioned=snapshot({transactions:[{...snapshot().transactions[0],paid_at_source:"payment_transition",business_day_policy_version:0}]});
 await assert.rejects(getExecutiveSalesMonitor(input,deps(unversioned)),{code:"EXEC_SALES_SOURCE_CUTOFF_INVALID"});
});

test("applies non-midnight branch cutoff immediately before and at the local boundary",async()=>{
 const before=snapshot({transactions:[{...snapshot().transactions[0],paid_at:"2026-11-28T19:59:00Z",
  business_date:"2026-11-28",timezone:"Asia/Jakarta",cutoff_time:"03:00:00"}]});
 await getExecutiveSalesMonitor(input,deps(before));
 const atBoundary=snapshot({transactions:[{...snapshot().transactions[0],paid_at:"2026-11-28T20:00:00Z",
  business_date:"2026-11-29",timezone:"Asia/Jakarta",cutoff_time:"03:00:00"}]});
 await getExecutiveSalesMonitor({...input,endDate:"2026-11-29"},deps(atBoundary));
});
