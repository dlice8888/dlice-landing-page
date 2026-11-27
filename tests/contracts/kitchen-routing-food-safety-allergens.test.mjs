import test from "node:test";
import assert from "node:assert/strict";
import {routeKitchenItems,evaluateFoodSafetyObservation,validateProductAllergenDeclaration} from "../../src/kitchen-routing-food-safety-allergens.mjs";

test("kitchen routing uses approved tenant/branch product-category rules",()=>{
 const result=routeKitchenItems({tenantId:"tenant-a",branchId:"branch-a",
  items:[{id:"line-a",tenantId:"tenant-a",branchId:"branch-a",productCategory:"hot_food",quantity:2}],
  stations:[{id:"hot",tenantId:"tenant-a",branchId:"branch-a",status:"active",capacity:10,queuedItems:3}],
  routingRules:[{tenantId:"tenant-a",branchId:"branch-a",productCategory:"hot_food",stationId:"hot",status:"approved"}]});
 assert.equal(result.routes[0].stationId,"hot");
});
test("kitchen routing rejects missing route and capacity overflow",()=>{
 const base={tenantId:"tenant-a",branchId:"branch-a",items:[{id:"line-a",tenantId:"tenant-a",branchId:"branch-a",productCategory:"cold",quantity:5}],
  stations:[{id:"cold",tenantId:"tenant-a",branchId:"branch-a",status:"active",capacity:4,queuedItems:0}],
  routingRules:[{tenantId:"tenant-a",branchId:"branch-a",productCategory:"cold",stationId:"cold",status:"approved"}]};
 assert.throws(()=>routeKitchenItems({...base,routingRules:[]}),{code:"KITCHEN_STATION_ROUTE_MISSING"});
 assert.throws(()=>routeKitchenItems(base),{code:"KITCHEN_STATION_CAPACITY_EXCEEDED"});
});
test("food safety accepts observations within approved temperature, shelf-life and allergen policy",()=>{
 const result=evaluateFoodSafetyObservation({tenantId:"tenant-a",branchId:"branch-a",at:"2026-11-27T10:00:00Z",
  policy:{tenantId:"tenant-a",branchId:"branch-a",status:"approved",minTemperatureC:0,maxTemperatureC:5,
   requiredAllergens:["milk"],criticalAllergens:["peanut"]},
  observation:{temperatureC:3,observedAt:"2026-11-27T09:59:00Z",useBy:"2026-11-30",declaredAllergens:["milk"],crossContactAllergens:[]}});
 assert.equal(result.status,"accepted");
});
test("food safety quarantines out-of-range, expired and critical cross-contact observations",()=>{
 const result=evaluateFoodSafetyObservation({tenantId:"tenant-a",branchId:"branch-a",at:"2026-11-27T10:00:00Z",
  policy:{tenantId:"tenant-a",branchId:"branch-a",status:"approved",minTemperatureC:0,maxTemperatureC:5,
   requiredAllergens:["milk"],criticalAllergens:["peanut"]},
  observation:{temperatureC:9,observedAt:"2026-11-27T09:59:00Z",useBy:"2026-11-20",declaredAllergens:[],crossContactAllergens:["peanut"]}});
 assert.equal(result.status,"quarantined");assert.equal(result.quarantineRequired,true);
 assert.equal(result.temperatureOutOfRange,true);assert.equal(result.expired,true);
 assert.deepEqual(result.missingAllergens,["milk"]);
});
test("food safety rejects unapproved or cross-branch policy",()=>{
 assert.throws(()=>evaluateFoodSafetyObservation({tenantId:"tenant-a",branchId:"branch-a",at:"2026-11-27T10:00:00Z",
  policy:{tenantId:"tenant-b",branchId:"branch-a",status:"approved"},observation:{}}),
  {code:"FOOD_SAFETY_POLICY_NOT_APPROVED"});
});
test("allergen declarations must include every recipe ingredient allergen",()=>{
 const result=validateProductAllergenDeclaration({tenantId:"tenant-a",declaredAllergens:["milk","wheat"],
  ingredients:[{tenantId:"tenant-a",allergens:["milk"]},{tenantId:"tenant-a",allergens:["wheat"]}]});
 assert.equal(result.status,"valid");
 assert.throws(()=>validateProductAllergenDeclaration({tenantId:"tenant-a",declaredAllergens:["milk"],
  ingredients:[{tenantId:"tenant-a",allergens:["milk","peanut"]}]}),{code:"ALLERGEN_DECLARATION_INCOMPLETE"});
});
test("allergen declaration rejects cross-tenant ingredients and unsupported claims",()=>{
 assert.throws(()=>validateProductAllergenDeclaration({tenantId:"tenant-a",declaredAllergens:["milk"],
  ingredients:[{tenantId:"tenant-b",allergens:["milk"]}]}),{code:"ALLERGEN_INGREDIENT_SCOPE_MISMATCH"});
 assert.throws(()=>validateProductAllergenDeclaration({tenantId:"tenant-a",declaredAllergens:["milk","peanut"],
  ingredients:[{tenantId:"tenant-a",allergens:["milk"]}]}),{code:"ALLERGEN_DECLARATION_UNSUPPORTED"});
});
