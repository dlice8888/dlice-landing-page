/**
 * Delivery fulfilment close from authenticated provider events and canonical Order.
 * Provider delivery state cannot close an order without tenant/branch-bound proof.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("DELIVERY_INPUT_REQUIRED",f);return v.trim();};
const adapter=(d,n)=>{if(typeof d?.[n]!=="function")fail("DELIVERY_ADAPTER_REQUIRED",n);return d[n];};
const scopeOf=(i)=>({tenantId:req(i?.tenantId,"tenantId"),branchId:req(i?.branchId,"branchId"),
 actorId:req(i?.actorId,"actorId"),orderId:req(i?.orderId,"orderId"),
 providerEventId:req(i?.providerEventId,"providerEventId"),idempotencyKey:req(i?.idempotencyKey,"idempotencyKey"),
 action:"delivery.fulfilment.apply_provider_event"});
const same=(r,s,f)=>{if(!r||r.tenantId!==s.tenantId||r.branchId!==s.branchId)fail("DELIVERY_SCOPE_MISMATCH",f);};
const transitions={accepted:["picked_up","cancelled"],picked_up:["in_transit","delivered","failed"],in_transit:["delivered","failed"],failed:["picked_up","cancelled"],delivered:[],cancelled:[]};

/** Required tx adapters: authorize, findProviderEvent, loadVerifiedProviderEvent,
 * loadOrderForUpdate, verifyPrivateDeliveryProof, persistDeliveryTransition,
 * reconcileDeliveryCharge, appendAudit.
 */
export async function applyDeliveryProviderEvent(input,deps){
 const s=scopeOf(input);
 return adapter(deps,"withTenantTransaction")(s,async tx=>{
  if(!tx)fail("DELIVERY_TRANSACTION_REQUIRED","Database transaction required");
  await adapter(deps,"authorize")(tx,s);
  const prior=await adapter(deps,"findProviderEvent")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",deliveryId:prior.deliveryId});
  const event=await adapter(deps,"loadVerifiedProviderEvent")(tx,s);
  same(event,s,"providerEvent");
  if(event.signatureVerified!==true||event.replayChecked!==true||event.providerEventId!==s.providerEventId)
   fail("DELIVERY_PROVIDER_AUTHENTICITY_REQUIRED","Provider signature, event identity and replay protection are required");
  const order=await adapter(deps,"loadOrderForUpdate")(tx,s);same(order,s,"order");
  if(order.status==="cancelled"||order.status==="refunded")fail("DELIVERY_ORDER_TERMINAL","Cancelled/refunded order cannot be fulfilled");
  const current=event.currentStatus, next=event.nextStatus;
  if(!Object.hasOwn(transitions,current)||!transitions[current].includes(next))
   fail("DELIVERY_TRANSITION_INVALID","Unsupported provider delivery transition");
  if(order.deliveryStatus!==current)fail("DELIVERY_STATE_CONFLICT","Provider state does not match canonical delivery state");
  if(next==="delivered"){
   if(!event.deliveredAt||!Number.isFinite(Date.parse(event.deliveredAt)))fail("DELIVERY_PROOF_REQUIRED","Delivered event needs a timestamp");
   const proof=await adapter(deps,"verifyPrivateDeliveryProof")(tx,{...s,proofReference:event.proofReference,deliveredAt:event.deliveredAt});
   if(proof!==true)fail("DELIVERY_PROOF_UNVERIFIED","Delivery proof must be private and verified for this order");
  }
  const saved=await adapter(deps,"persistDeliveryTransition")(tx,{...s,provider:event.provider,
   providerStatus:next,occurredAt:req(event.occurredAt,"occurredAt"),deliveredAt:next==="delivered"?event.deliveredAt:null,
   proofReference:next==="delivered"?event.proofReference:null});
  if(!saved?.id)fail("DELIVERY_TRANSITION_PERSIST_FAILED","Delivery transition was not persisted");
  const charge=await adapter(deps,"reconcileDeliveryCharge")(tx,{...s,deliveryId:saved.id,provider:event.provider});
  if(!charge||charge.reconciled!==true||charge.tenantId!==s.tenantId||charge.branchId!==s.branchId)
   fail("DELIVERY_CHARGE_UNRECONCILED","Provider delivery fee must reconcile to the canonical Order/Finance source");
  await adapter(deps,"appendAudit")(tx,{...s,action:"delivery.fulfilment.provider_transition",entityType:"delivery_fulfilments",
   entityId:saved.id,metadata:{provider:event.provider,from:current,to:next,chargeId:charge.id}});
  return Object.freeze({status:"applied",deliveryId:saved.id,deliveryStatus:next,chargeId:charge.id});
 });
}
