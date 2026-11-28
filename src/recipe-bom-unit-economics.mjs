/**
 * Deterministic recipe BOM expansion and unit economics.
 * Inputs must be server-loaded, tenant-scoped, approved recipe versions and
 * authoritative ingredient costs; caller-supplied prices are not evidence.
 */
const fail = (code, message) => { const error = new Error(message); error.code = code; throw error; };
const positive = (value, field) => {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) fail("RECIPE_VALUE_INVALID", field);
  return n;
};
const pct = (value, field) => {
  const n = value == null ? 0 : Number(value);
  if (!Number.isFinite(n) || n < 0 || n >= 100) fail("RECIPE_PERCENT_INVALID", field);
  return n;
};
const units = Object.freeze({
  g: { dimension: "mass", factor: 1 }, kg: { dimension: "mass", factor: 1000 },
  mg: { dimension: "mass", factor: 0.001 },
  ml: { dimension: "volume", factor: 1 }, l: { dimension: "volume", factor: 1000 },
  each: { dimension: "count", factor: 1 }, portion: { dimension: "count", factor: 1 },
});
function convert(quantity, from, to) {
  const a = units[from], b = units[to];
  if (!a || !b || a.dimension !== b.dimension) fail("RECIPE_UNIT_CONVERSION_UNSUPPORTED", `${from} -> ${to}`);
  return quantity * a.factor / b.factor;
}
function validateNode(node, tenantId, stack) {
  if (!node || node.tenantId !== tenantId || !node.id) fail("RECIPE_TENANT_SCOPE_MISMATCH", "Recipe and ingredient records must belong to the same tenant");
  if (stack.includes(node.id)) fail("RECIPE_BOM_CYCLE", `Nested recipe cycle: ${[...stack, node.id].join(" -> ")}`);
  if (node.status !== "approved" || !node.effectiveFrom) fail("RECIPE_VERSION_NOT_EFFECTIVE", "Only approved effective recipe versions may be costed");
}
function expandNode(recipe, tenantId, stack, multiplier, output) {
  validateNode(recipe, tenantId, stack);
  const nextStack = [...stack, recipe.id];
  const effectiveYield = positive(recipe.yieldQuantity, "yieldQuantity") * (1 - pct(recipe.yieldLossPct, "yieldLossPct") / 100);
  if (effectiveYield <= 0) fail("RECIPE_EFFECTIVE_YIELD_ZERO", "Recipe effective yield must be positive");
  for (const line of recipe.ingredients || []) {
    const quantity = positive(line.quantity, "ingredient.quantity");
    const grossQuantity = quantity / (1 - pct(line.prepLossPct, "prepLossPct") / 100);
    const scaledQuantity = grossQuantity * multiplier / effectiveYield;
    if (line.type === "sub_recipe") {
      if (!line.recipe) fail("RECIPE_SUB_RECIPE_REQUIRED", "Nested recipe reference is missing");
      expandNode(line.recipe, tenantId, nextStack, scaledQuantity, output);
      continue;
    }
    if (line.type !== "ingredient" || !line.ingredient || line.ingredient.tenantId !== tenantId) {
      fail("RECIPE_INGREDIENT_SCOPE_INVALID", "Ingredient must be an authoritative same-tenant record");
    }
    const costUnit = line.ingredient.costUnit;
    const baseQuantity = convert(scaledQuantity, line.unit, costUnit);
    const unitCost = Number(line.ingredient.unitCostIdr);
    if (!Number.isSafeInteger(unitCost) || unitCost < 0) fail("RECIPE_INGREDIENT_COST_INVALID", "Ingredient unit cost must be a non-negative integer IDR");
    output.push({
      ingredientId: line.ingredient.id, ingredientName: line.ingredient.name,
      quantity: Number(baseQuantity.toFixed(6)), unit: costUnit,
      unitCostIdr: unitCost, extendedCostIdr: Math.round(baseQuantity * unitCost),
    });
  }
  return effectiveYield;
}

/** Expand a recipe into gross ingredient requirements for one requested output quantity. */
export function expandRecipeBom(input) {
  const tenantId = typeof input?.tenantId === "string" && input.tenantId.trim();
  if (!tenantId) fail("RECIPE_TENANT_REQUIRED", "tenantId");
  const recipe = input.recipe;
  const requestedQuantity = positive(input.requestedQuantity ?? 1, "requestedQuantity");
  const output = [];
  const effectiveYield = expandNode(recipe, tenantId, [], requestedQuantity, output);
  const grouped = new Map();
  for (const row of output) {
    const prior = grouped.get(row.ingredientId);
    if (!prior) grouped.set(row.ingredientId, { ...row });
    else {
      prior.quantity = Number((prior.quantity + row.quantity).toFixed(6));
      prior.extendedCostIdr += row.extendedCostIdr;
    }
  }
  return Object.freeze({
    recipeId: recipe.id, recipeVersion: recipe.version,
    requestedQuantity, effectiveYield,
    ingredients: Object.freeze([...grouped.values()].map(Object.freeze)),
    totalIngredientCostIdr: [...grouped.values()].reduce((sum, row) => sum + row.extendedCostIdr, 0),
  });
}

/** Calculate cost/serving and contribution margin from a reconciled approved BOM. */
export function calculateRecipeUnitEconomics(input) {
  const bom = expandRecipeBom(input);
  const servingCount = positive(input.servingCount, "servingCount");
  const sellingPriceIdr = Number(input.sellingPriceIdr);
  if (!Number.isSafeInteger(sellingPriceIdr) || sellingPriceIdr < 0) fail("RECIPE_SELLING_PRICE_INVALID", "sellingPriceIdr");
  const costPerServingIdr = Math.ceil(bom.totalIngredientCostIdr / servingCount);
  const contributionIdr = sellingPriceIdr - costPerServingIdr;
  const marginPct = sellingPriceIdr === 0 ? null : Number((contributionIdr / sellingPriceIdr * 100).toFixed(2));
  return Object.freeze({
    ...bom, servingCount, sellingPriceIdr, costPerServingIdr,
    contributionIdr, contributionMarginPct: marginPct,
  });
}
