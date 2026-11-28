import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const edge=await readFile(new URL("../../supabase/functions/dlice-orders/index.ts",import.meta.url),"utf8");

test("executive sales monitor derives branch scope from authenticated memberships",()=>{
 const start=edge.indexOf('if (action === "erp-executive-sales-monitor")');
 const end=edge.indexOf('if (action === "erp-overview")',start);
 assert.ok(start>=0&&end>start);
 const action=edge.slice(start,end);
 assert.match(action,/branchIdsForActor\(\)/);
 assert.match(action,/allowedIds\.includes\(requestedBranch\)/);
 assert.doesNotMatch(action,/body\.tenant_id|body\.tenantId/);
});
test("sales monitor reads POS sales, processed refunds, settlement allocations and Finance journal sources",()=>{
 const start=edge.indexOf('if (action === "erp-executive-sales-monitor")');
 const end=edge.indexOf('if (action === "erp-overview")',start);
 const action=edge.slice(start,end);
 for(const table of ["pos_sales","pos_sale_items","refund_records","payment_settlement_items","payment_settlements","finance_journal_entries"])assert.ok(action.includes('"'+table+'"'),"missing "+table);
 assert.match(action,/processed_at/);
 assert.match(action,/sale_items:saleItems\.filter/);
 assert.match(action,/aggregateSalesMonitor/);
 assert.match(action,/settlement_net_received_idr:completeSettlementNet\?netAllocation:null/);
 assert.match(action,/settlementNetAllocationByItem/);
 assert.match(action,/business_date\.gte/);
 assert.match(action,/paid_at\.gte/);
 assert.match(action,/settlementSourceBranches/);
 assert.match(action,/singleTenantSettlement/);
 assert.match(action,/posted_finance_refund_journal_idr/);
});
test("sales monitor fails closed on unauthorized branch and invalid timezone",()=>{
 const start=edge.indexOf('if (action === "erp-executive-sales-monitor")');
 const end=edge.indexOf('if (action === "erp-overview")',start);
 const action=edge.slice(start,end);
 assert.match(action,/return fail\("Cabang laporan tidak berada dalam scope aktor\.",403/);
 assert.match(action,/SUPPORTED_BRANCH_TIMEZONES/);
 assert.match(action,/Rekonsiliasi penjualan gagal/);
});
