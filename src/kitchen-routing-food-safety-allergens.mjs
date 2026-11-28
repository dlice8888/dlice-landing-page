/**
 * Kitchen station routing, food-safety checks and product allergen declarations.
 * Routing and policy are server-loaded and tenant/branch scoped.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("KITCHEN_INPUT_REQUIRED",f);return v.trim();};

/** Route committed order lines to approved active kitchen stations. */
export function routeKitchenItems(input){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId");
 if(!Array.isArray(input.items)||!input.items.length||!Array.isArray(input.stations)||!Array.isArray(input.routingRules))
  fail("KITCHEN_ROUTING_INPUT_REQUIRED","Items, stations and approved routing rules are required");
 const stations=new Map(input.stations.filter(s=>s.tenantId===tenantId&&s.branchId===branchId&&s.status==="active").map(s=>[s.id,s]));
 const routed=[];
 for(const item of input.items){
  if(item.tenantId!==tenantId||item.branchId!==branchId)fail("KITCHEN_ROUTING_SCOPE_MISMATCH","Order item must match tenant and branch");
  const rule=input.routingRules.find(r=>r.tenantId===tenantId&&r.branchId===branchId&&r.productCategory===item.productCategory&&r.status==="approved");
  if(!rule)fail("KITCHEN_STATION_ROUTE_MISSING",`No approved station route for ${item.productCategory}`);
  const station=stations.get(rule.stationId);
  if(!station)fail("KITCHEN_STATION_UNAVAILABLE","Configured station is not active for this branch");
  const quantity=Number(item.quantity);
  if(!Number.isFinite(quantity)||quantity<=0)fail("KITCHEN_ITEM_QUANTITY_INVALID","Order item quantity must be positive");
  if(Number(station.queuedItems??0)+quantity>Number(station.capacity??Infinity))fail("KITCHEN_STATION_CAPACITY_EXCEEDED","Station capacity would be exceeded");
  routed.push(Object.freeze({orderItemId:req(item.id,"orderItemId"),stationId:station.id,quantity,priority:rule.priority??"normal"}));
 }
 return Object.freeze({tenantId,branchId,routes:Object.freeze(routed)});
}

/** Evaluate temperature, shelf-life and allergen controls using an approved effective policy. */
export function evaluateFoodSafetyObservation(input){
 const policy=input.policy,observation=input.observation;
 if(!policy||policy.status!=="approved"||policy.tenantId!==input.tenantId||policy.branchId!==input.branchId)
  fail("FOOD_SAFETY_POLICY_NOT_APPROVED","Approved same-tenant/branch policy is required");
 const at=Date.parse(req(input.at,"at")),temperature=Number(observation?.temperatureC);
 if(!Number.isFinite(at)||!Number.isFinite(temperature))fail("FOOD_SAFETY_OBSERVATION_INVALID","Timestamp and temperature are required");
 const min=Number(policy.minTemperatureC),max=Number(policy.maxTemperatureC);
 if(!Number.isFinite(min)||!Number.isFinite(max)||min>max)fail("FOOD_SAFETY_POLICY_INVALID","Temperature policy range is invalid");
 const observedAt=Date.parse(req(observation.observedAt,"observedAt"));
 const expired=observation.useBy?Date.parse(observation.useBy+"T23:59:59Z")<at:false;
 const temperatureOutOfRange=temperature<min||temperature>max;
 const declared=new Set(observation.declaredAllergens||[]),required=new Set(policy.requiredAllergens||[]);
 const missingAllergens=[...required].filter(a=>!declared.has(a));
 const crossContact=Array.isArray(observation.crossContactAllergens)?observation.crossContactAllergens:[];
 const criticalCrossContact=crossContact.some(a=>(policy.criticalAllergens||[]).includes(a));
 const passed=observedAt<=at&&!expired&&!temperatureOutOfRange&&!missingAllergens.length&&!criticalCrossContact;
 return Object.freeze({status:passed?"accepted":"quarantined",passed,temperatureOutOfRange,expired,
  missingAllergens:Object.freeze(missingAllergens),criticalCrossContact,quarantineRequired:!passed});
}

/** Derive product allergen declarations from authoritative recipe ingredients and approved cross-contact policy. */
export function validateProductAllergenDeclaration(input){
 const declared=new Set(input.declaredAllergens||[]),ingredientAllergens=new Set();
 for(const ingredient of input.ingredients||[]){
  if(ingredient.tenantId!==input.tenantId)fail("ALLERGEN_INGREDIENT_SCOPE_MISMATCH","Ingredient must belong to tenant");
  for(const allergen of ingredient.allergens||[])ingredientAllergens.add(allergen);
 }
 const missing=[...ingredientAllergens].filter(a=>!declared.has(a));
 const unsupported=[...declared].filter(a=>!ingredientAllergens.has(a)&&!(input.approvedMayContainAllergens||[]).includes(a));
 if(missing.length)fail("ALLERGEN_DECLARATION_INCOMPLETE","Declared allergen list omits recipe ingredient allergens");
 if(unsupported.length)fail("ALLERGEN_DECLARATION_UNSUPPORTED","Declared allergens need approved cross-contact evidence");
 return Object.freeze({status:"valid",declaredAllergens:Object.freeze([...declared].sort()),
  ingredientAllergens:Object.freeze([...ingredientAllergens].sort()),mayContainAllergens:Object.freeze([...(input.approvedMayContainAllergens||[])].sort())});
}
