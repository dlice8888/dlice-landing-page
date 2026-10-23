#!/usr/bin/env node
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const api = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");
const ui = readFileSync("erp.html", "utf8");

// Receiving RPC requires purchase_order_item_id. The list endpoint must expose
// both the line ID and inventory item ID so the existing ERP form can submit it.
assert.match(
  api,
  /purchase_order_items\(id,inventory_item_id,item_name_snapshot,quantity,unit_cost_idr,line_total_idr\)/,
  "PO list response must expose purchase-order line IDs and item quantities for GRN posting",
);
assert.match(
  ui,
  /purchase_order_item_id:i\.id,quantity_received:Number\(i\.quantity\)/,
  "ERP receiving form must map each PO line ID to purchase_order_item_id",
);
assert.match(api, /action === "erp-receive-purchase-order"/, "Receiving action must remain available");
console.log("PASS procurement receiving contract: PO line IDs flow from API to GRN payload.");
