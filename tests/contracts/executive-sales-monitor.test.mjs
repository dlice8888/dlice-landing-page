import test from "node:test";
import assert from "node:assert/strict";
import {getExecutiveSalesMonitor} from "../../src/executive-sales-monitor.mjs";
const snapshot=(overrides={})=>({snapshot_id:"snap1",tenant_id:"t1",period_type:"day",formula_version:"sales-net-v1",
 totals:{gross_idr:100000,discount_idr:10000,refund_idr:5000,net_sales_idr:85000,matched_settlement_idr:85000,transaction_count:1},
 daily:[{business_date:"2026-11-28",gross_idr:100000,discount_idr:10000,refund_idr:5000,net_sales_idr:85000,transaction_count:1}],
 transactions:[{sale_id:"s1",branch_id:"b1",business_date:"2026-11-28",timezone:"Asia/Jakarta",gross_idr:100000,discount_idr:10000,processed_refund_idr:5000,net_sales_idr:85000}],
 payment_reconciliation:{sale_count:1,tender_mismatch_count:0,tender_allocations_balanced:true},\n finance_reconciliation:{sale_count:1,sale_without_journal_count:0,linked_journal_entry_count:1,status:"journal_links_present"},...overrides});
const input={tenantId:"t1",actorId:"u1",period:"day",startDate:"2026-11-28",endDate:"2026-11-28"};
const deps=(value=snapshot())=>({loadSalesMonitorSnapshot:async()=>value});
test("returns the authoritative snapshot with gross, discount, processed refund and net totals",async()=>{
 const r=await getExecutiveSalesMonitor(input,deps());assert.equal(r.totals.gross_idr,100000);assert.equal(r.totals.discount_idr,10000);
 assert.equal(r.totals.refund_idr,5000);assert.equal(r.totals.net_sales_idr,85000);assert.equal(r.totals.matched_settlement_idr,85000);
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
test("rejects incomplete snapshot and mismatched tenant",async()=>{
 await assert.rejects(getExecutiveSalesMonitor(input,deps({snapshot_id:"x"})),{code:"EXEC_SALES_SNAPSHOT_INVALID"});
 await assert.rejects(getExecutiveSalesMonitor(input,deps(snapshot({tenant_id:"t2"}))),{code:"EXEC_SALES_SNAPSHOT_INVALID"});
});
test("rejects negative or unsafe aggregate totals",async()=>{
 await assert.rejects(getExecutiveSalesMonitor(input,deps(snapshot({totals:{...snapshot().totals,net_sales_idr:-1}}))),{code:"EXEC_SALES_TOTAL_INVALID"});
});
