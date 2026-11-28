import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const html=readFileSync(new URL("../../erp.html",import.meta.url),"utf8");
test("POS split tender UI supports two to five distinct supported methods and server checkout",()=>{
 assert.match(html,/id="splitTenderRows"/);
 assert.match(html,/id="addSplitTender"/);
 assert.match(html,/id="submitSplitSale"/);
 assert.match(html,/splitTenderCount=2/);
 assert.match(html,/splitTenderCount>=5/);
 assert.match(html,/erp-create-pos-sale-split-tender/);
 assert.match(html,/new Set\(tenders\.map\(t=>t\.payment_method\)\)\.size<2/);
 assert.match(html,/Number\.isSafeInteger\(t\.amount_idr\)/);
});
