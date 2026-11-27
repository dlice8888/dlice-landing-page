import test from "node:test";
import assert from "node:assert/strict";
import {
 allocateInventoryLots,calculateInventoryValuation,reserveInventoryFromLots,publishInventoryValuation,
} from "../../src/inventory-lot-valuation-workflows.mjs";

const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"stock-manager",idempotencyKey:"inventory-flow-0001"};
const lots=[
 {id:"lot-old",tenantId:"tenant-a",branchId:"branch-a",itemId:"flour",status:"available",availableQuantity:5,
  remainingQuantity:5,receivedAt:"2026-11-01T00:00:00Z",expiryDate:"2026-12-31",unitCostIdr:1000},
 {id:"lot-expiring",tenantId:"tenant-a",branchId:"branch-a",itemId:"flour",status:"available",availableQuantity:4,
  remainingQuantity:4,receivedAt:"2026-11-05T00:00:00Z",expiryDate:"2026-11-30",unitCostIdr:1200},
 {id:"lot-expired",tenantId:"tenant-a",branchId:"branch-a",itemId:"flour",status:"available",availableQuantity:10,
  remainingQuantity:10,receivedAt:"2026-10-01T00:00:00Z",expiryDate:"2026-11-01",unitCostIdr:900},
];

test("FEFO allocates earliest expiry before older receipt and excludes expired lots",()=>{
 const result=allocateInventoryLots({tenantId:"tenant-a",branchId:"branch-a",itemId:"flour",quantity:6,
  method:"FEFO",asOf:"2026-11-27T00:00:00Z",lots});
 assert.deepEqual(result.allocations.map(x=>[x.lotId,x.quantity]),[["lot-expiring",4],["lot-old",2]]);
});
test("FIFO allocates oldest receipt first and fails closed when unexpired stock is insufficient",()=>{
 const result=allocateInventoryLots({tenantId:"tenant-a",branchId:"branch-a",itemId:"flour",quantity:6,
  method:"FIFO",asOf:"2026-11-27T00:00:00Z",lots});
 assert.deepEqual(result.allocations.map(x=>[x.lotId,x.quantity]),[["lot-old",5],["lot-expiring",1]]);
 assert.throws(()=>allocateInventoryLots({tenantId:"tenant-a",branchId:"branch-a",itemId:"flour",quantity:10,
  method:"FIFO",asOf:"2026-11-27T00:00:00Z",lots}),{code:"INVENTORY_INSUFFICIENT_UNEXPIRED_STOCK"});
});
test("lot allocation rejects cross-tenant branch or item records",()=>{
 assert.throws(()=>allocateInventoryLots({tenantId:"tenant-a",branchId:"branch-a",itemId:"flour",quantity:1,
  method:"FIFO",asOf:"2026-11-27T00:00:00Z",lots:[{...lots[0],tenantId:"tenant-b"}]}),
  {code:"INVENTORY_LOT_SCOPE_MISMATCH"});
});
test("historical valuation uses only layers received by the cutoff and reports IDR value",()=>{
 const result=calculateInventoryValuation({tenantId:"tenant-a",branchId:"branch-a",itemId:"flour",
  method:"WEIGHTED_AVERAGE",asOf:"2026-11-03T00:00:00Z",lots:[...lots,{...lots[1],id:"future-lot",receivedAt:"2026-11-04T00:00:00Z"}]});
 assert.equal(result.quantity,5);assert.equal(result.valueIdr,5000);assert.equal(result.layerCount,1);
});
test("valuation rejects unsupported method and cross-tenant layers",()=>{
 assert.throws(()=>calculateInventoryValuation({tenantId:"tenant-a",branchId:"branch-a",itemId:"flour",
  method:"LIFO",asOf:"2026-11-27T00:00:00Z",lots}),{code:"INVENTORY_VALUATION_METHOD_INVALID"});
 assert.throws(()=>calculateInventoryValuation({tenantId:"tenant-a",branchId:"branch-a",itemId:"flour",
  method:"FIFO",asOf:"2026-11-27T00:00:00Z",lots:[{...lots[0],tenantId:"tenant-b"}]}),
  {code:"INVENTORY_LOT_SCOPE_MISMATCH"});
});
test("inventory allocation persists all lot movements under approved policy",async()=>{
 const deps={
  withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
  findLotAllocationByIdempotencyKey:async()=>null,
  loadApprovedInventoryPolicy:async()=>({status:"approved",allocationMethod:"FEFO"}),
  loadAvailableLotsForUpdate:async()=>lots,
  persistLotAllocationsAndMovements:async(_tx,row)=>{assert.equal(row.allocations.length,2);return{id:"allocation-a",movementCount:2};},
  appendAudit:async()=>{},
 };
 const result=await reserveInventoryFromLots({...base,itemId:"flour",quantity:6,asOf:"2026-11-27T00:00:00Z"},deps);
 assert.equal(result.status,"allocated");assert.equal(result.allocations.length,2);
});
test("inventory valuation snapshot uses approved policy and historical repository layers",async()=>{
 const deps={
  withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
  findInventoryValuationByIdempotencyKey:async()=>null,
  loadApprovedInventoryPolicy:async()=>({status:"approved",valuationMethod:"FIFO",version:2}),
  loadValuationLotsAsOf:async()=>lots.filter(x=>x.id!=="lot-expired"),
  persistInventoryValuationSnapshot:async(_tx,row)=>{assert.equal(row.policyVersion,2);return{id:"valuation-a"};},
  appendAudit:async()=>{},
 };
 const result=await publishInventoryValuation({...base,itemId:"flour",asOf:"2026-11-27T00:00:00Z"},deps);
 assert.equal(result.status,"published");assert.equal(result.valuationId,"valuation-a");
});
