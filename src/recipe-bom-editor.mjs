/** Nested BOM validation: cycles, missing ingredients and UOM compatibility. */
export function validateRecipeBom({rootRecipeId,lines,knownIngredients,knownRecipes,uomDimensions}){
 if(!rootRecipeId||!Array.isArray(lines))throw new Error("BOM_CONTEXT_INVALID");
 const ingredients=new Set(knownIngredients||[]),recipes=new Set(knownRecipes||[]),graph=new Map();
 for(const line of lines){
  if(!line.parent_recipe_id||!line.component_id||!Number.isFinite(line.quantity)||line.quantity<=0)throw new Error("BOM_LINE_INVALID");
  if(line.component_type==="ingredient"&&!ingredients.has(line.component_id))throw new Error("BOM_INGREDIENT_MISSING");
  if(line.component_type==="recipe"){if(!recipes.has(line.component_id))throw new Error("BOM_RECIPE_MISSING");const children=graph.get(line.parent_recipe_id)||[];children.push(line.component_id);graph.set(line.parent_recipe_id,children);}
  if(!["ingredient","recipe"].includes(line.component_type))throw new Error("BOM_COMPONENT_TYPE_INVALID");
  if(!uomDimensions?.[line.uom]||!uomDimensions?.[line.base_uom]||uomDimensions[line.uom]!==uomDimensions[line.base_uom])throw new Error("BOM_UOM_INCOMPATIBLE");
 }
 const visiting=new Set(),visited=new Set();
 const visit=id=>{if(visiting.has(id))throw new Error("BOM_CYCLE_DETECTED");if(visited.has(id))return;visiting.add(id);for(const child of graph.get(id)||[])visit(child);visiting.delete(id);visited.add(id);};
 visit(rootRecipeId);
 return Object.freeze({root_recipe_id:rootRecipeId,line_count:lines.length,validated:true});
}
