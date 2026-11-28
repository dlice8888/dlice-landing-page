/** Recipe yield and theoretical ingredient usage. */
export function calculateRecipeYield({recipeVersion,requestedOutputQuantity,unitConversions={}}){
 if(!recipeVersion?.id||recipeVersion.status!=="active"||!Number.isFinite(recipeVersion.yield_quantity)||recipeVersion.yield_quantity<=0)throw new Error("RECIPE_VERSION_NOT_ACTIVE_OR_YIELD_INVALID");
 if(!Number.isFinite(requestedOutputQuantity)||requestedOutputQuantity<=0)throw new Error("RECIPE_OUTPUT_QUANTITY_INVALID");
 const factor=requestedOutputQuantity/recipeVersion.yield_quantity;
 const ingredients=(recipeVersion.ingredients||[]).map(line=>{
  if(!line.ingredient_id||!Number.isFinite(line.quantity)||line.quantity<=0)throw new Error("RECIPE_INGREDIENT_INVALID");
  const conversion=unitConversions[line.uom]??1;if(!Number.isFinite(conversion)||conversion<=0)throw new Error("RECIPE_UOM_CONVERSION_INVALID");
  const quantity=line.quantity*factor*conversion;if(!Number.isFinite(quantity)||quantity<=0)throw new Error("RECIPE_THEORETICAL_USAGE_INVALID");
  return Object.freeze({ingredient_id:line.ingredient_id,base_uom:line.base_uom,quantity_base:quantity});
 });
 return Object.freeze({recipe_version_id:recipeVersion.id,requested_output_quantity:requestedOutputQuantity,ingredients:Object.freeze(ingredients)});
}
