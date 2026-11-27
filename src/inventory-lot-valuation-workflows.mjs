/**
 * Lot allocation and inventory valuation domain workflows.
 * Quantities/costs are sourced from tenant-scoped repository adapters, not client claims.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("INVENTORY_INPUT_REQUIRED",f);return v.trim();};
const positive=(v,f)=>{const n=Number(v);if(!Number.isFinite(n)||n<=0)fail("INVENTORY_QUANTITY_INVALID",f);return n;};
const adapter=(d,n)=>{if(typeof d?.[n]!=="function")fail("INVENTORY_ADAPTER_REQUIRED",n);return d[n];};
const scope=(i,a)=>({tenantId:req(i?.tenantId,"tenantId"),branchId:req(i?.branchId,"branchId"),
 actorId:req(i?.actorId,"actorId"),idempotencyKey:req(i?.idempotencyKey,"idempotencyKey"),action:a});
const txScope=(d,s,fn)=>adapter(d,"withTenantTransaction")(s,async tx=>{
 if(!tx)fail("INVENTORY_TRANSACTION_REQUIRED","Database transaction required");
 await adapter(d,"authorize")(tx,s);return fn(tx);
});
const assertLot=(lot,s,itemId)=>{if(!lot||lot.tenantId!==s.tenantId||lot.branchId!==s.branchId||lot.itemId!==itemId)
 fail("INVENTORY_LOT_SCOPE_MISMATCH","Lot must match tenant, branch and item");};

/** Allocate FEFO or FIFO lots with stable ordering and no negative/expired stock. */
export function allocateInventoryLots(input){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId"),itemId=req(input?.itemId,"itemId");
 const quantity=positive(input.quantity,"quantity"),method=input.method;
 if(!["FIFO","FEFO"].includes(method))fail("INVENTORY_ALLOCATION_METHOD_INVALID","Only FIFO or FEFO is supported");
 const asOf=Date.parse(req(input.asOf,"asOf"));
 if(!Number.isFinite(asOf))fail("INVENTORY_AS_OF_INVALID","asOf must be a valid timestamp");
 const lots=(input.lots||[]).map(lot=>{
  if(lot.tenantId!==tenantId||lot.branchId!==branchId||lot.itemId!==itemId)fail("INVENTORY_LOT_SCOPE_MISMATCH","Lot must match tenant, branch and item");
  const available=Number(lot.availableQuantity),received=Date.parse(lot.receivedAt),expiry=lot.expiryDate?Date.parse(lot.expiryDate+"T23:59:59Z"):Infinity;
  if(!Number.isFinite(available)||available<0||!Number.isFinite(received))fail("INVENTORY_LOT_DATA_INVALID","Lot quantity and received date are required");
  return {...lot,available,received,expiry};
 }).filter(l=>l.status==="available"&&l.available>0&&l.expiry>=asOf);
 lots.sort((a,b)=>method==="FEFO"?(a.expiry-b.expiry||a.received-b.received||a.id.localeCompare(b.id)):
  (a.received-b.received||a.id.localeCompare(b.id)));
 let remaining=quantity;const allocations=[];
 for(const lot of lots){
  if(remaining<=0)break;
  const take=Math.min(remaining,lot.available);
  allocations.push(Object.freeze({lotId:lot.id,quantity:Number(take.toFixed(6)),unitCostIdr:lot.unitCostIdr}));
  remaining=Number((remaining-take).toFixed(6));
 }
 if(remaining>0)fail("INVENTORY_INSUFFICIENT_UNEXPIRED_STOCK","Available non-expired lot quantity is insufficient");
 return Object.freeze({tenantId,branchId,itemId,method,requestedQuantity:quantity,
  allocations:Object.freeze(allocations),allocatedQuantity:Number((quantity-remaining).toFixed(6))});
}

/** Value remaining inventory by FIFO layers or weighted average at a historical cutoff. */
export function calculateInventoryValuation(input){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId"),itemId=req(input?.itemId,"itemId");
 const method=input.method,asOf=Date.parse(req(input.asOf,"asOf"));
 if(!["FIFO","WEIGHTED_AVERAGE"].includes(method))fail("INVENTORY_VALUATION_METHOD_INVALID","Unsupported valuation method");
 if(!Number.isFinite(asOf)||!Array.isArray(input.lots))fail("INVENTORY_VALUATION_INPUT_INVALID","Historical cutoff and lot layers are required");
 const lots=input.lots.filter(l=>Date.parse(l.receivedAt)<=asOf&&l.status!=="voided").map(l=>{
  if(l.tenantId!==tenantId||l.branchId!==branchId||l.itemId!==itemId)fail("INVENTORY_LOT_SCOPE_MISMATCH","Valuation lot must match tenant, branch and item");
  const quantity=Number(l.remainingQuantity),unitCost=Number(l.unitCostIdr),received=Date.parse(l.receivedAt);
  if(!Number.isFinite(quantity)||quantity<0||!Number.isSafeInteger(unitCost)||unitCost<0||!Number.isFinite(received))
   fail("INVENTORY_VALUATION_LAYER_INVALID","Valuation layer quantity and cost are invalid");
  return {...l,quantity,unitCost,received};
 }).filter(l=>l.quantity>0).sort((a,b)=>a.received-b.received||a.id.localeCompare(b.id));
 const quantity=lots.reduce((sum,l)=>sum+l.quantity,0);
 const totalValue=lots.reduce((sum,l)=>sum+l.quantity*l.unitCost,0);
 const valueIdr=method==="FIFO"?Math.round(totalValue):Math.round(totalValue);
 const averageUnitCostIdr=quantity?Number((totalValue/quantity).toFixed(4)):0;
 return Object.freeze({tenantId,branchId,itemId,method,asOf:new Date(asOf).toISOString(),
  quantity:Number(quantity.toFixed(6)),valueIdr,averageUnitCostIdr,layerCount:lots.length});
}

/** Allocate against locked authoritative lots and persist all stock movements atomically. */
export async function reserveInventoryFromLots(input,deps){
 const s=scope(input,"inventory.lot.allocate"),itemId=req(input.itemId,"itemId"),quantity=positive(input.quantity,"quantity");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findLotAllocationByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",allocationId:prior.id});
  const policy=await adapter(deps,"loadApprovedInventoryPolicy")(tx,s);
  if(!policy||policy.status!=="approved"||!["FIFO","FEFO"].includes(policy.allocationMethod))
   fail("INVENTORY_ALLOCATION_POLICY_REQUIRED","Approved FIFO/FEFO policy is required");
  const lots=await adapter(deps,"loadAvailableLotsForUpdate")(tx,{...s,itemId});
  const result=allocateInventoryLots({tenantId:s.tenantId,branchId:s.branchId,itemId,quantity,
   method:policy.allocationMethod,asOf:input.asOf,lots});
  const saved=await adapter(deps,"persistLotAllocationsAndMovements")(tx,{...s,...result});
  if(!saved?.id||saved.movementCount!==result.allocations.length)fail("INVENTORY_ALLOCATION_PERSIST_FAILED","Every lot allocation must persist with its stock movement");
  await adapter(deps,"appendAudit")(tx,{...s,action:"inventory.lot.allocated",entityType:"inventory_lot_allocation",entityId:saved.id,
   metadata:{itemId,method:result.method,quantity}});
  return Object.freeze({status:"allocated",allocationId:saved.id,allocations:result.allocations});
 });
}

/** Publish a historical valuation only from approved method and persisted lot layers. */
export async function publishInventoryValuation(input,deps){
 const s=scope(input,"inventory.valuation.publish"),itemId=req(input.itemId,"itemId"),asOf=req(input.asOf,"asOf");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findInventoryValuationByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",valuationId:prior.id});
  const policy=await adapter(deps,"loadApprovedInventoryPolicy")(tx,s);
  if(!policy||policy.status!=="approved"||!["FIFO","WEIGHTED_AVERAGE"].includes(policy.valuationMethod))
   fail("INVENTORY_VALUATION_POLICY_REQUIRED","Approved valuation method is required");
  const lots=await adapter(deps,"loadValuationLotsAsOf")(tx,{...s,itemId,asOf});
  const valuation=calculateInventoryValuation({tenantId:s.tenantId,branchId:s.branchId,itemId,asOf,
   method:policy.valuationMethod,lots});
  const saved=await adapter(deps,"persistInventoryValuationSnapshot")(tx,{...s,...valuation,policyVersion:policy.version});
  if(!saved?.id)fail("INVENTORY_VALUATION_PERSIST_FAILED","Valuation snapshot was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"inventory.valuation.published",entityType:"inventory_valuation_snapshot",entityId:saved.id,
   metadata:{itemId,asOf,quantity:valuation.quantity,valueIdr:valuation.valueIdr,method:valuation.method}});
  return Object.freeze({status:"published",valuationId:saved.id,valuation});
 });
}
