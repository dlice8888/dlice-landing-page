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
 assert.match(html,/settlement_net_received_idr/);
});
test("Executive sales monitor uses branch-configured timezone instead of client timezone override",()=>{
 assert.match(html,/Timezone lokal masing-masing cabang/);
 assert.doesNotMatch(html,/timezone:\s*\$\('executiveSalesTimezone'\)\.value/);
});
