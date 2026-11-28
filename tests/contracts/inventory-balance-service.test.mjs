import test from "node:test";import assert from "node:assert/strict";import {getInventoryBalance} from "../../src/inventory-balance-service.mjs";
const input={tenantId:"t1",branchId:"b1",actorId:"u1",inventoryItemId:"i1"};
test("inventory balance matches ledger and stock buckets",async()=>{const r=await getInventoryBalance(input,{getInventoryBalanceLedgerReadOnly:async x=>({...x,onHand:100,reserved:20,inTransit:10,blocked:5,available:65,ledgerOnHand:100})});assert.equal(r.available,65);});
test("rejects ledger drift and bucket arithmetic mismatch",async()=>{await assert.rejects(getInventoryBalance(input,{getInventoryBalanceLedgerReadOnly:async x=>({...x,onHand:100,reserved:20,inTransit:10,blocked:5,available:65,ledgerOnHand:99})}),{code:"INVENTORY_BALANCE_LEDGER_MISMATCH"});});
