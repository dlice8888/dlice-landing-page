/** Demand-driven prep plan and ingredient reservation calculation. */
export function planProductionBatch({branchId,productId,recipeVersion,demandQuantity,onHandByIngredient,reservedByIngredient={},idempotencyKey,approvalThresholdQuantity=Number.MAX_SAFE_INTEGER}){
 if(!branchId||!productId||!recipeVersion?.id||recipeVersion.status!=="active"||!Number.isFinite(recipeVersion.yield_quantity)||recipeVersion.yield_quantity<=0)throw new Error("PREP_PLAN_CONTEXT_INVALID");
 if(!Number.isSafeInteger(demandQuantity)||demandQuantity<1)throw new Error("PREP_PLAN_DEMAND_INVALID");
 if(typeof idempotencyKey!=="string"||idempotencyKey.trim().length<16)throw new Error("PREP_PLAN_IDEMPOTENCY_REQUIRED");
 const batches=Math.ceil(demandQuantity/recipeVersion.yield_quantity);
 const requirements=(recipeVersion.ingredients||[]).map(line=>{
  const required=Math.ceil((line.quantity/recipeVersion.yield_quantity)*demandQuantity*1000)/1000;
  const available=Number(onHandByIngredient?.[line.ingredient_id]||0)-Number(reservedByIngredient?.[line.ingredient_id]||0);
  if(!Number.isFinite(available)||available<required)throw new Error("PREP_PLAN_INSUFFICIENT_STOCK:"+line.ingredient_id);
  return Object.freeze({ingredient_id:line.ingredient_id,required_quantity:required,reserve_quantity:required});
 });
 return Object.freeze({branch_id:branchId,product_id:productId,recipe_version_id:recipeVersion.id,demand_quantity:demandQuantity,batch_count:batches,requires_approval:demandQuantity>approvalThresholdQuantity,ingredient_reservations:Object.freeze(requirements),idempotency_key:idempotencyKey.trim()});
}
