/** Reconcile batch consumption to immutable stock movements and waste. */
export function reconcileProductionConsumption({batchId,recipeVersionId,plannedByIngredient,actualByIngredient,movements,wasteByIngredient={},varianceTolerance=0}){
 if(!batchId||!recipeVersionId||!Number.isFinite(varianceTolerance)||varianceTolerance<0)throw new Error("PRODUCTION_RECONCILIATION_CONTEXT_INVALID");
 const keys=new Set([...Object.keys(plannedByIngredient||{}),...Object.keys(actualByIngredient||{})]);
 const rows=[...keys].sort().map(id=>{
  const planned=Number(plannedByIngredient?.[id]||0),actual=Number(actualByIngredient?.[id]||0),waste=Number(wasteByIngredient?.[id]||0);
  if(![planned,actual,waste].every(Number.isFinite)||planned<0||actual<0||waste<0)throw new Error("PRODUCTION_QUANTITY_INVALID");
  const ledger=(movements||[]).filter(m=>m.ingredient_id===id&&m.batch_id===batchId&&m.status==="posted").reduce((s,m)=>s+Number(m.quantity_base||0),0);
  if(Math.abs(ledger-actual)>0.000001)throw new Error("PRODUCTION_STOCK_LEDGER_MISMATCH:"+id);
  return Object.freeze({ingredient_id:id,planned_quantity:planned,actual_quantity:actual,waste_quantity:waste,variance_quantity:actual-planned,waste_within_tolerance:waste<=varianceTolerance});
 });
 return Object.freeze({batch_id:batchId,recipe_version_id:recipeVersionId,reconciled:rows.every(r=>r.waste_within_tolerance),ingredients:Object.freeze(rows)});
}
