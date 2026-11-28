import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const html=await readFile(new URL("../../erp.html",import.meta.url),"utf8");
test("Executive live sales monitor exposes day/week/month, date and branch controls",()=>{
 for(const id of ["executiveSalesPeriod","executiveSalesDate","executiveSalesBranch","executiveSalesTimezone","loadExecutiveSales","executiveSalesMetrics","executiveSalesSources"])assert.ok(html.includes('id="'+id+'"'),"missing "+id);
 assert.match(html,/value="day"/);assert.match(html,/value="week"/);assert.match(html,/value="month"/);
});
test("Executive UI invokes authenticated server action and exposes source transaction rows",()=>{
 assert.match(html,/call\('erp-executive-sales-monitor'/);
 assert.match(html,/sources\?\.sales/);
 assert.match(html,/sources\?\.refunds/);
 assert.match(html,/sources\?\.sale_items/);
 assert.match(html,/created_at legacy/);
 assert.match(html,/business_date\/paid_at cabang/);
 assert.match(html,/Settlement net teralokasi/);
 assert.match(html,/Alokasi settlement cocok/);
 assert.match(html,/Waktu pengakuan/);
 assert.match(html,/Finance journal net/);
});
test("Executive sales monitor uses branch-configured timezone instead of client timezone override",()=>{
 assert.match(html,/Timezone lokal masing-masing cabang/);
 assert.doesNotMatch(html,/timezone:\s*\$\('executiveSalesTimezone'\)\.value/);
});

test("Executive approval center renders source-backed entity detail and evidence",()=>{
 assert.match(html,/item\.source_detail/);
 assert.match(html,/Detail entity sumber/);
 assert.match(html,/Referensi bukti/);
});

test("Executive sales transaction drill-down includes refunds, settlement allocations and Finance journals",()=>{
 assert.match(html,/sale_refunds/);
 assert.match(html,/sale_settlements/);
 assert.match(html,/sale_finance_journals/);
 assert.match(html,/Finance journal \(/);
 assert.match(html,/Settlement \(/);
});

test("Executive sales source rows provide an authorized POS reconciliation drill-down", () => {
  assert.match(ui, /data-exec-sale-drilldown/);
  assert.match(ui, /erp-reconcile-pos-sale/);
  assert.match(ui, /Detail rekonsiliasi POS \/ KDS \/ stok \/ audit/);
});
