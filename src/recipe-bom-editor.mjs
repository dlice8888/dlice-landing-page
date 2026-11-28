/** D05-F04: recipe/BOM editor with nested recipe and UOM validation delegated server-side. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("RECIPE_BOM_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("RECIPE_BOM_ADAPTER_REQUIRED",k);return d[k];};
export async function saveRecipeBom(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  recipeId:req(input?.recipeId,"recipeId"),version:input.version,lines:input.lines,expectedVersion:input.expectedVersion};
 if(!Number.isSafeInteger(payload.version)||payload.version<1||!Number.isSafeInteger(payload.expectedVersion)||payload.expectedVersion<0||
  !Array.isArray(payload.lines)||!payload.lines.length)fail("RECIPE_BOM_PAYLOAD_INVALID","Recipe version and BOM lines required");
 const ids=new Set();for(const line of payload.lines){const id=req(line.inventoryItemId??line.childRecipeId,"BOM component");if(ids.has(id))fail("RECIPE_BOM_DUPLICATE_COMPONENT","Duplicate BOM component");ids.add(id);if(!Number.isFinite(line.quantity)||line.quantity<=0)fail("RECIPE_BOM_QUANTITY_INVALID","BOM quantity must be positive");if(Boolean(line.inventoryItemId)===Boolean(line.childRecipeId))fail("RECIPE_BOM_COMPONENT_INVALID","Each line must reference one inventory item or child recipe");}
 const result=await fn(deps,"saveRecipeBomAtomically")(payload);
 if(!result?.recipeId||result.recipeId!==payload.recipeId||result.version!==payload.version||result.status!=="draft")fail("RECIPE_BOM_SAVE_FAILED","BOM version was not persisted as draft");
 return Object.freeze(result);
}
