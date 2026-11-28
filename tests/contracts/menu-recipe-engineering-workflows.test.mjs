import test from "node:test";
import assert from "node:assert/strict";
import { validateProductCatalogChange, resolvePublishedCatalog } from "../../src/product-catalog-admin.mjs";
import { evaluateBranchProductAvailability } from "../../src/branch-product-availability.mjs";
import { resolveEffectivePrice } from "../../src/pricing-policy-engine.mjs";
import { validateRecipeBom } from "../../src/recipe-bom-editor.mjs";
import { validateRecipeVersionActivation } from "../../src/recipe-version-lifecycle.mjs";
import { buildMenuStockReservation } from "../../src/menu-stock-availability.mjs";
import { prepareRecipeChange, assertRecipeRolloutComplete } from "../../src/recipe-change-workflow.mjs";

const now="2026-11-28T10:00:00.000Z";
test("catalog master changes enforce tenant, HQ role and unique SKU",()=>{
 const product={id:"p1",tenant_id:"t1",sku:"CAKE-1",name:"Cake",created_by:"u1"};
 assert.equal(validateProductCatalogChange({product,existingSkus:[],actor:{user_id:"u1",role:"hq_catalog_admin"},scope:{tenant_id:"t1"}}).operation,"upsert");
 assert.throws(()=>validateProductCatalogChange({product,existingSkus:[{id:"p2",tenant_id:"t1",sku:"cake-1"}],actor:{user_id:"u1",role:"hq_catalog_admin"},scope:{tenant_id:"t1"}}),/SKU_DUPLICATE/);
 assert.throws(()=>validateProductCatalogChange({product,actor:{user_id:"u2",role:"branch_manager"},scope:{tenant_id:"t1"}}),/MASTER_WRITE_FORBIDDEN/);
});

test("published catalog resolves active effective version for a branch",()=>{
 const rows=resolvePublishedCatalog({branchId:"b1",now,products:[{id:"p1",sku:"A",name:"Cake",is_active:true,branch_ids:["b1"],version:2,price_idr:1000,effective_from:"2026-11-01T00:00:00Z"}]});
 assert.equal(rows.length,1);assert.equal(rows[0].version,2);
});

test("branch availability override cannot bypass inactive product or stock depletion",()=>{
 assert.equal(evaluateBranchProductAvailability({productId:"p1",branchId:"b1",branchEnabled:false,productActive:true,stockTracked:true,onHand:5,reserved:0,safetyStock:1,override:true,actorCanOverride:true}).available,true);
 assert.equal(evaluateBranchProductAvailability({productId:"p1",branchId:"b1",branchEnabled:false,productActive:true,stockTracked:true,onHand:0,reserved:0,override:true,actorCanOverride:true}).available,false);
 assert.equal(evaluateBranchProductAvailability({productId:"p1",branchId:"b1",branchEnabled:true,productActive:false,stockTracked:false,onHand:0,reserved:0,override:true,actorCanOverride:true}).available,false);
});

test("pricing resolves approved branch override over regional and central price",()=>{
 const policies=[
  {id:"c",product_id:"p1",scope:"central",price_idr:10000,approval_status:"approved",effective_from:"2026-01-01T00:00:00Z"},
  {id:"r",product_id:"p1",scope:"regional",region_id:"r1",price_idr:11000,approval_status:"approved",effective_from:"2026-01-01T00:00:00Z"},
  {id:"b",product_id:"p1",scope:"branch",branch_id:"b1",price_idr:12000,approval_status:"approved",effective_from:"2026-01-01T00:00:00Z"},
 ];
 assert.equal(resolveEffectivePrice({productId:"p1",branchId:"b1",regionId:"r1",at:now,pricePolicies:policies}).price_idr,12000);
 assert.equal(resolveEffectivePrice({productId:"p1",branchId:"b2",regionId:"r1",at:now,pricePolicies:policies}).price_idr,11000);
});

test("recipe BOM rejects missing ingredients, incompatible UOM and cycles",()=>{
 assert.equal(validateRecipeBom({rootRecipeId:"r1",lines:[{parent_recipe_id:"r1",component_id:"i1",component_type:"ingredient",quantity:2,uom:"kg",base_uom:"g"}],knownIngredients:["i1"],knownRecipes:[],uomDimensions:{kg:"mass",g:"mass"}}).validated,true);
 assert.throws(()=>validateRecipeBom({rootRecipeId:"r1",lines:[{parent_recipe_id:"r1",component_id:"r2",component_type:"recipe",quantity:1,uom:"kg",base_uom:"g"},{parent_recipe_id:"r2",component_id:"r1",component_type:"recipe",quantity:1,uom:"kg",base_uom:"g"}],knownIngredients:[],knownRecipes:["r1","r2"],uomDimensions:{kg:"mass",g:"mass"}}),/BOM_CYCLE_DETECTED/);
});

test("recipe activation enforces approved version, non-overlap and independent actor",()=>{
 const candidate={id:"v2",product_id:"p1",status:"approved",effective_from:"2026-12-01T00:00:00Z",created_by:"u1",separation_of_duties:true};
 assert.equal(validateRecipeVersionActivation({candidate,versions:[],actor:{user_id:"u2"},now}).history_immutable,true);
 assert.throws(()=>validateRecipeVersionActivation({candidate,versions:[],actor:{user_id:"u1"},now}),/SELF_APPROVAL/);
 assert.throws(()=>validateRecipeVersionActivation({candidate,versions:[{id:"v1",product_id:"p1",status:"active",effective_from:"2026-01-01T00:00:00Z"}],actor:{user_id:"u2"},now}),/EFFECTIVE_DATE_OVERLAP/);
});

test("menu stock reservation is optimistic-versioned and idempotent",()=>{
 const command=buildMenuStockReservation({tenantId:"t1",branchId:"b1",productId:"p1",requestedQuantity:2,onHand:5,reserved:1,safetyStock:1,expectedStockVersion:4,actualStockVersion:4,idempotencyKey:"menu-reserve-000001",expiresAt:"2026-11-28T11:00:00Z",now});
 assert.equal(command.atomic_reserve_required,true);
 assert.throws(()=>buildMenuStockReservation({tenantId:"t1",branchId:"b1",productId:"p1",requestedQuantity:4,onHand:5,reserved:1,safetyStock:1,expectedStockVersion:4,actualStockVersion:4,idempotencyKey:"menu-reserve-000002",expiresAt:"2026-11-28T11:00:00Z",now}),/STOCK_UNAVAILABLE/);
 assert.throws(()=>buildMenuStockReservation({tenantId:"t1",branchId:"b1",productId:"p1",requestedQuantity:1,onHand:5,reserved:0,expectedStockVersion:3,actualStockVersion:4,idempotencyKey:"menu-reserve-000003",expiresAt:"2026-11-28T11:00:00Z",now}),/STALE_VERSION/);
});

test("recipe change requires independent approval and complete branch rollout",()=>{
 const change=prepareRecipeChange({request:{id:"cr1",product_id:"p1"},author:{user_id:"u1"},costSnapshot:{version:"cost-v1",total_cost_idr:25000,calculated_at:now},approver:{user_id:"u2",decision:"approved"},rolloutBranches:[{branch_id:"b1",acknowledged:true},{branch_id:"b2",acknowledged:true}],now});
 assert.equal(change.activation_allowed,true);
 assert.equal(assertRecipeRolloutComplete({branchAcks:[{branch_id:"b1",status:"applied"}],requiredBranchIds:["b1"]}).complete,true);
 assert.throws(()=>assertRecipeRolloutComplete({branchAcks:[{branch_id:"b1",status:"applied"}],requiredBranchIds:["b1","b2"]}),/ROLLOUT_INCOMPLETE/);
 assert.throws(()=>prepareRecipeChange({request:{id:"cr1",product_id:"p1"},author:{user_id:"u1"},costSnapshot:{version:"v1",total_cost_idr:1,calculated_at:now},approver:{user_id:"u1",decision:"approved"},rolloutBranches:["b1"],now}),/SELF_APPROVAL/);
});
