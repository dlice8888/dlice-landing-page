import test from "node:test";
import assert from "node:assert/strict";
import { dispatchKitchenTicket, claimKitchenTicket } from "../../src/kds-station-board.mjs";
import { evaluatePrepSla } from "../../src/kds-prep-sla.mjs";
import { transitionKitchenItem } from "../../src/kds-lifecycle.mjs";
import { calculateRecipeYield } from "../../src/recipe-yield-costing.mjs";
import { planProductionBatch } from "../../src/production-prep-planner.mjs";
import { reconcileProductionConsumption } from "../../src/production-consumption-reconciliation.mjs";
import { resolveProductionMode } from "../../src/production-mode-router.mjs";

const now="2026-11-28T10:00:00.000Z";
test("KDS dispatch maps committed order items to active branch stations",()=>{
 const result=dispatchKitchenTicket({order:{id:"o1",branch_id:"b1",version:2},branchId:"b1",items:[{id:"i1",product_id:"p1",quantity:2}],stations:[{id:"st1",branch_id:"b1",is_active:true,product_ids:["p1"]}],idempotencyKey:"kds-dispatch-000001"});
 assert.equal(result.tickets[0].station_id,"st1");
 assert.throws(()=>dispatchKitchenTicket({order:{id:"o1",branch_id:"b1"},branchId:"b1",items:[{id:"i1",product_id:"p1",quantity:1}],stations:[],idempotencyKey:"kds-dispatch-000002"}),/STATION_NOT_CONFIGURED/);
 assert.throws(()=>dispatchKitchenTicket({order:{id:"o1",branch_id:"b1"},branchId:"b1",items:[{id:"i1",product_id:"p1",quantity:1}],stations:[{id:"st1",branch_id:"b1",is_active:true,product_ids:["p1"]},{id:"st2",branch_id:"b1",is_active:true,product_ids:["p1"]}],idempotencyKey:"kds-dispatch-000003"}),/STATION_ROUTE_AMBIGUOUS/);
 assert.throws(()=>claimKitchenTicket({ticket:{id:"t1",status:"waiting",station_id:"st1",branch_id:"b1",version:2},actor:{user_id:"u1",branch_id:"b1"},assignedStationIds:["st1"],expectedVersion:1}),/STALE_VERSION/);
});

test("KDS SLA escalates once after target after subtracting paused time",()=>{
 const result=evaluatePrepSla({ticketId:"t1",stationId:"st1",startedAt:"2026-11-28T09:00:00Z",targetMinutes:30,now,pausedSeconds:600});
 assert.equal(result.overdue,true);assert.equal(result.escalate,true);
 assert.equal(evaluatePrepSla({ticketId:"t1",stationId:"st1",startedAt:"2026-11-28T09:00:00Z",targetMinutes:30,now,pausedSeconds:600,escalationAlreadyCreated:true}).escalate,false);
});

test("KDS lifecycle requires station assignment and independent handover acknowledgement",()=>{
 const item={id:"i1",branch_id:"b1",station_id:"st1",status:"ready",version:3};
 assert.throws(()=>transitionKitchenItem({item,actor:{user_id:"u1",branch_id:"b1"},assignedStationIds:["st1"],toStatus:"handed_over",expectedVersion:3,eventId:"e1",receiverUserId:"u1",acknowledged:true,now}),/HANDOVER_ACK_REQUIRED/);
 const result=transitionKitchenItem({item,actor:{user_id:"u1",branch_id:"b1"},assignedStationIds:["st1"],toStatus:"handed_over",expectedVersion:3,eventId:"e1",receiverUserId:"u2",acknowledged:true,now});
 assert.equal(result.version,4);assert.equal(result.append_only,true);
});

const recipe={id:"rv1",status:"active",yield_quantity:10,ingredients:[{ingredient_id:"flour",quantity:2,uom:"kg",base_uom:"g"}]};
test("recipe yield expands theoretical ingredient use from active version",()=>{
 const result=calculateRecipeYield({recipeVersion:recipe,requestedOutputQuantity:20,unitConversions:{kg:1000}});
 assert.equal(result.ingredients[0].quantity_base,4000);
 assert.throws(()=>calculateRecipeYield({recipeVersion:{...recipe,status:"draft"},requestedOutputQuantity:10}),/NOT_ACTIVE/);
});

test("prep planning reserves only available stock and carries recipe version",()=>{
 const result=planProductionBatch({branchId:"b1",productId:"p1",recipeVersion:recipe,demandQuantity:20,onHandByIngredient:{flour:10},reservedByIngredient:{flour:2},idempotencyKey:"prep-plan-0000001"});
 assert.equal(result.batch_count,2);assert.equal(result.ingredient_reservations[0].reserve_quantity,4);
 assert.throws(()=>planProductionBatch({branchId:"b1",productId:"p1",recipeVersion:recipe,demandQuantity:20,onHandByIngredient:{flour:3},idempotencyKey:"prep-plan-0000002"}),/INSUFFICIENT_STOCK/);
});

test("production consumption must reconcile to posted stock movement ledger",()=>{
 const result=reconcileProductionConsumption({batchId:"batch1",recipeVersionId:"rv1",plannedByIngredient:{flour:4},actualByIngredient:{flour:4.5},movements:[{id:"m-ok",batch_id:"batch1",ingredient_id:"flour",quantity_base:4.5,status:"posted"}],wasteByIngredient:{flour:0.5},varianceTolerance:1});
 assert.equal(result.reconciled,true);
 assert.throws(()=>reconcileProductionConsumption({batchId:"batch1",recipeVersionId:"rv1",plannedByIngredient:{flour:4},actualByIngredient:{flour:5},movements:[{id:"m-bad",batch_id:"batch1",ingredient_id:"flour",quantity_base:4,status:"posted"}]}),/LEDGER_MISMATCH/);
 const duplicate={id:"m1",batch_id:"batch1",ingredient_id:"flour",quantity_base:4.5,status:"posted"};
 assert.throws(()=>reconcileProductionConsumption({batchId:"batch1",recipeVersionId:"rv1",plannedByIngredient:{flour:4},actualByIngredient:{flour:9},movements:[duplicate,duplicate]}),/MOVEMENT_DUPLICATE/);
});

test("production mode keeps batch and made-to-order routes distinct with explicit fallback",()=>{
 assert.equal(resolveProductionMode({productId:"p1",branchId:"b1",configuredMode:"batch",batchAvailable:true}).source,"production_batch");
 assert.equal(resolveProductionMode({productId:"p2",branchId:"b1",configuredMode:"batch",batchAvailable:false,allowOnDemandFallback:true}).production_mode,"made_to_order");
 assert.throws(()=>resolveProductionMode({productId:"p1",branchId:"b1",configuredMode:"made_to_order",batchAvailable:true,overrideMode:"batch"}),/OVERRIDE_FORBIDDEN/);
});
