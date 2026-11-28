import test from "node:test";
import assert from "node:assert/strict";
import { calculateInventoryBalance } from "../../src/inventory-balance-service.mjs";
import { buildStockMovementCommand, validateStockReversal } from "../../src/stock-movement-ledger.mjs";
import { validateWarehouseLocationTree } from "../../src/warehouse-location-tree.mjs";
import { convertInventoryQuantity } from "../../src/inventory-uom-conversion.mjs";
import { reconcileStockBuckets, buildStockReservation } from "../../src/inventory-stock-buckets.mjs";
import { calculateReorderRecommendation } from "../../src/inventory-reorder-planner.mjs";
import { calculateCycleCountVariance } from "../../src/inventory-cycle-count.mjs";
import { validateInventoryAdjustment } from "../../src/inventory-adjustment-approval.mjs";
import { reconcileProcurementReceipt } from "../../src/procurement-stock-reconciliation.mjs";

test("inventory balance is derived from scoped posted movements only",()=>{
 const result=calculateInventoryBalance({openingQuantity:10,tenantId:"t1",branchId:"b1",itemId:"i1",movements:[{id:"m1",tenant_id:"t1",branch_id:"b1",item_id:"i1",status:"posted",direction:"in",quantity_base:5},{id:"m2",tenant_id:"t1",branch_id:"b1",item_id:"i1",status:"posted",direction:"out",quantity_base:3},{id:"m3",tenant_id:"t2",branch_id:"b1",item_id:"i1",status:"posted",direction:"out",quantity_base:9}]});
 assert.equal(result.on_hand,12);assert.equal(result.movement_count,2);
 assert.throws(()=>calculateInventoryBalance({openingQuantity:0,tenantId:"t1",branchId:"b1",itemId:"i1",movements:[{id:"m1",tenant_id:"t1",branch_id:"b1",item_id:"i1",status:"posted",direction:"out",quantity_base:1}]}),/NEGATIVE_BALANCE/);
});

test("stock movement command is source-bound and append-only; reversal must mirror original",()=>{
 const cmd=buildStockMovementCommand({tenantId:"t1",branchId:"b1",itemId:"i1",sourceType:"procurement",sourceId:"po1",quantityBase:5,direction:"in",idempotencyKey:"stock-move-0000001",actorDomain:"procurement"});
 assert.equal(cmd.append_only,true);
 assert.throws(()=>buildStockMovementCommand({tenantId:"t1",branchId:"b1",itemId:"i1",sourceType:"manual",sourceId:"po1",quantityBase:5,direction:"in",idempotencyKey:"stock-move-0000002",actorDomain:"client"}),/ACTOR_FORBIDDEN/);
 assert.equal(validateStockReversal({originalMovement:{id:"m1",status:"posted",quantity_base:5,direction:"in"},reversal:{source_id:"m1",quantity_base:5,direction:"out"},actorDomain:"finance"}).append_reversal,true);
});

test("warehouse location tree enforces branch scope, parent existence and acyclic hierarchy",()=>{
 const base=[{id:"w",tenant_id:"t1",branch_id:"b1",location_type:"warehouse",code:"W1"},{id:"z",tenant_id:"t1",branch_id:"b1",location_type:"zone",code:"Z1",parent_id:"w"},{id:"b",tenant_id:"t1",branch_id:"b1",location_type:"bin",code:"B1",parent_id:"z"}];
 assert.equal(validateWarehouseLocationTree({locations:base,tenantId:"t1",branchId:"b1"}).valid,true);
 assert.throws(()=>validateWarehouseLocationTree({locations:[...base,{id:"w",tenant_id:"t1",branch_id:"b1",location_type:"warehouse"}],tenantId:"t1",branchId:"b1"}),/DUPLICATE_ID/);
 assert.throws(()=>validateWarehouseLocationTree({locations:[{...base[0],parent_id:"z"},base[1]],tenantId:"t1",branchId:"b1"}),/CYCLE/);
});

test("UOM conversion uses active effective dimension-compatible snapshot",()=>{
 const result=convertInventoryQuantity({quantity:1.25,fromUom:"kg",toUom:"g",at:"2026-11-28T00:00:00Z",conversions:[{from_uom:"kg",to_uom:"g",factor:1000,from_dimension:"mass",to_dimension:"mass",status:"active",effective_from:"2026-01-01T00:00:00Z",version:"uom-v2"}]});
 assert.equal(result.quantity,1250);assert.equal(result.conversion_version,"uom-v2");
 assert.throws(()=>convertInventoryQuantity({quantity:1,fromUom:"kg",toUom:"l",at:"2026-11-28T00:00:00Z",conversions:[{from_uom:"kg",to_uom:"l",factor:1,from_dimension:"mass",to_dimension:"volume",status:"active",effective_from:"2026-01-01T00:00:00Z"}]}),/CONVERSION_NOT_FOUND/);
 const chain=convertInventoryQuantity({quantity:2,fromUom:"case",toUom:"unit",at:"2026-11-28T00:00:00Z",conversions:[{from_uom:"case",to_uom:"pack",factor:6,from_dimension:"count",to_dimension:"count",status:"active",effective_from:"2026-01-01T00:00:00Z",version:"v1"},{from_uom:"pack",to_uom:"unit",factor:10,from_dimension:"count",to_dimension:"count",status:"active",effective_from:"2026-01-01T00:00:00Z",version:"v2"}]});
 assert.equal(chain.quantity,120);
 assert.throws(()=>convertInventoryQuantity({quantity:1,fromUom:"a",toUom:"c",at:"2026-11-28T00:00:00Z",conversions:[{from_uom:"a",to_uom:"b",factor:2,from_dimension:"count",to_dimension:"count",status:"active",effective_from:"2026-01-01T00:00:00Z"},{from_uom:"b",to_uom:"a",factor:0.5,from_dimension:"count",to_dimension:"count",status:"active",effective_from:"2026-01-01T00:00:00Z"}]}),/CONVERSION_CYCLE/);
});

test("stock buckets reconcile and reservations use optimistic version",()=>{
 assert.equal(reconcileStockBuckets({onHand:10,available:4,reserved:2,inTransit:3,blocked:1}).reconciled,true);
 assert.throws(()=>reconcileStockBuckets({onHand:10,available:4,reserved:2,inTransit:0,blocked:1}),/TOTAL_MISMATCH/);
 assert.equal(buildStockReservation({quantity:2,available:3,stockVersion:4,expectedVersion:4,idempotencyKey:"stock-reserve-0001"}).atomic,true);
 assert.throws(()=>buildStockReservation({quantity:2,available:1,stockVersion:4,expectedVersion:4,idempotencyKey:"stock-reserve-0002"}),/UNAVAILABLE/);
});

test("reorder planner accounts for reservations, in-transit and lead-time safety stock",()=>{
 const result=calculateReorderRecommendation({onHand:20,reserved:10,inTransit:2,averageDailyDemand:3,leadTimeDays:5,safetyStock:5,minimumOrderQuantity:1,maximumStock:100});
 assert.equal(result.reorder_point,20);assert.equal(result.available_stock,12);assert.equal(result.recommended_quantity,8);
 assert.throws(()=>calculateReorderRecommendation({onHand:10,reserved:0,inTransit:0,averageDailyDemand:2,leadTimeDays:3,safetyStock:0,maximumStock:5}),/MAXIMUM_STOCK/);
});

test("cycle count variance requires independent approval and current book version",()=>{
 const result=calculateCycleCountVariance({sessionId:"c1",itemId:"i1",bookQuantity:10,countedQuantity:8,expectedVersion:2,currentVersion:2,createdBy:"u1",approvedBy:"u2",threshold:1,reason:"Physical count variance"});
 assert.equal(result.variance,-2);assert.equal(result.post_once,true);
 assert.throws(()=>calculateCycleCountVariance({sessionId:"c1",itemId:"i1",bookQuantity:10,countedQuantity:8,expectedVersion:2,currentVersion:2,createdBy:"u1",approvedBy:"u1",threshold:1,reason:"Variance"}),/DUAL_CONTROL/);
});

test("inventory adjustments require reason, evidence, idempotency and dual control",()=>{
 const input={tenantId:"t1",branchId:"b1",itemId:"i1",quantity:5,direction:"out",reason:"Damaged stock count",requestedBy:"u1",approvedBy:"u2",thresholdQuantity:2,sourceEvidenceId:"asset1",idempotencyKey:"adjustment-key-0001"};
 assert.equal(validateInventoryAdjustment(input).requires_approval,true);
 assert.throws(()=>validateInventoryAdjustment({...input,approvedBy:"u1"}),/DUAL_CONTROL/);
});

test("procurement accepted receipt matches posted stock and resulting balance",()=>{
 const result=reconcileProcurementReceipt({purchaseOrder:{id:"po1",ordered_quantity:10},receipts:[{id:"grn1",purchase_order_id:"po1",status:"accepted",accepted_quantity:8,rejected_quantity:2}],movements:[{id:"m1",source_type:"procurement_receipt",source_order_id:"po1",status:"posted",quantity_base:8}],inventoryBalance:8});
 assert.equal(result.reconciled,true);
 assert.throws(()=>reconcileProcurementReceipt({purchaseOrder:{id:"po1",ordered_quantity:10},receipts:[{id:"grn2",purchase_order_id:"po1",status:"accepted",accepted_quantity:8}],movements:[],inventoryBalance:8}),/MOVEMENT_MISMATCH/);
 assert.throws(()=>reconcileProcurementReceipt({purchaseOrder:{id:"po1",ordered_quantity:10},receipts:[{id:"grn3",purchase_order_id:"po1",status:"accepted",accepted_quantity:4},{id:"grn3",purchase_order_id:"po1",status:"accepted",accepted_quantity:4}],movements:[],inventoryBalance:0}),/RECEIPT_DUPLICATE/);
});
