import test from "node:test";
import assert from "node:assert/strict";
import { expandRecipeBom, calculateRecipeUnitEconomics } from "../../src/recipe-bom-unit-economics.mjs";

const flour = { id: "flour", tenantId: "tenant-a", name: "Flour", costUnit: "g", unitCostIdr: 20 };
const baseRecipe = {
  id: "bread-v3", tenantId: "tenant-a", version: 3, status: "approved", effectiveFrom: "2026-11-01",
  yieldQuantity: 10, yieldLossPct: 0,
  ingredients: [{ type: "ingredient", quantity: 500, unit: "g", prepLossPct: 10, ingredient: flour }],
};

test("nested BOM converts units and applies prep loss to gross requirements", () => {
  const bom = expandRecipeBom({ tenantId: "tenant-a", recipe: baseRecipe, requestedQuantity: 20 });
  assert.equal(bom.ingredients.length, 1);
  assert.equal(bom.ingredients[0].unit, "g");
  assert.equal(bom.ingredients[0].quantity, 1111.111111);
  assert.equal(bom.totalIngredientCostIdr, 22222);
});

test("nested sub-recipes expand into canonical ingredient requirements", () => {
  const dough = { id: "dough-v2", tenantId: "tenant-a", version: 2, status: "approved", effectiveFrom: "2026-11-01",
    yieldQuantity: 5, yieldLossPct: 0,
    ingredients: [{ type: "ingredient", quantity: 1, unit: "kg", ingredient: flour }] };
  const bread = { ...baseRecipe, ingredients: [{ type: "sub_recipe", quantity: 2, unit: "portion", recipe: dough }] };
  const bom = expandRecipeBom({ tenantId: "tenant-a", recipe: bread, requestedQuantity: 10 });
  assert.equal(bom.ingredients[0].quantity, 400);
  assert.equal(bom.totalIngredientCostIdr, 8000);
});

test("recipe BOM rejects nested cycles", () => {
  const a = { ...baseRecipe, id: "a", ingredients: [] };
  const b = { ...baseRecipe, id: "b", ingredients: [{ type: "sub_recipe", quantity: 1, unit: "portion", recipe: a }] };
  a.ingredients.push({ type: "sub_recipe", quantity: 1, unit: "portion", recipe: b });
  assert.throws(() => expandRecipeBom({ tenantId: "tenant-a", recipe: a }), { code: "RECIPE_BOM_CYCLE" });
});

test("recipe BOM rejects cross-tenant ingredients and recipes", () => {
  const crossTenant = { ...baseRecipe, ingredients: [{ type: "ingredient", quantity: 10, unit: "g",
    ingredient: { ...flour, tenantId: "tenant-b" } }] };
  assert.throws(() => expandRecipeBom({ tenantId: "tenant-a", recipe: crossTenant }), { code: "RECIPE_INGREDIENT_SCOPE_INVALID" });
  assert.throws(() => expandRecipeBom({ tenantId: "tenant-b", recipe: baseRecipe }), { code: "RECIPE_TENANT_SCOPE_MISMATCH" });
});

test("recipe BOM rejects incompatible unit dimensions and unapproved versions", () => {
  const incompatible = { ...baseRecipe, ingredients: [{ type: "ingredient", quantity: 1, unit: "ml", ingredient: flour }] };
  assert.throws(() => expandRecipeBom({ tenantId: "tenant-a", recipe: incompatible }), { code: "RECIPE_UNIT_CONVERSION_UNSUPPORTED" });
  assert.throws(() => expandRecipeBom({ tenantId: "tenant-a", recipe: { ...baseRecipe, status: "draft" } }),
    { code: "RECIPE_VERSION_NOT_EFFECTIVE" });
});

test("unit economics calculates cost per serving and contribution margin", () => {
  const result = calculateRecipeUnitEconomics({ tenantId: "tenant-a", recipe: baseRecipe,
    requestedQuantity: 10, servingCount: 10, sellingPriceIdr: 5000 });
  assert.equal(result.totalIngredientCostIdr, 11111);
  assert.equal(result.costPerServingIdr, 1112);
  assert.equal(result.contributionIdr, 3888);
  assert.equal(result.contributionMarginPct, 77.76);
});
