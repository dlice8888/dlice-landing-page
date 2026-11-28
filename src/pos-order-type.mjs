/** Fulfilment-specific POS order requirements; payment status is intentionally separate. */
const TYPES=new Set(["dine_in","takeaway","pickup","delivery"]);
export function validatePosOrderType({type,branchEnabledTypes,tableId,pickupSlot,deliveryReference,deliveryAddress,paid=false,previousType,serverOverride=false}) {
  if(!TYPES.has(type))throw new Error("order_type_invalid");
  if(!branchEnabledTypes?.includes(type))throw new Error("order_type_disabled_for_branch");
  if(type==="dine_in"&&!tableId)throw new Error("dine_in_table_required");
  if(type==="pickup"&&!pickupSlot)throw new Error("pickup_slot_required");
  if(type==="delivery"&&!deliveryReference&&!deliveryAddress)throw new Error("delivery_destination_required");
  if(paid&&previousType&&previousType!==type&&!serverOverride)throw new Error("paid_order_type_change_forbidden");
  return Object.freeze({type,table_id:type==="dine_in"?tableId:null,pickup_slot:type==="pickup"?pickupSlot:null,delivery_reference:type==="delivery"?(deliveryReference||null):null,delivery_address:type==="delivery"?(deliveryAddress||null):null});
}
export function fulfillmentQueueForType(type) {
  if(!TYPES.has(type))throw new Error("order_type_invalid");
  return ({dine_in:"kitchen_and_table",takeaway:"kitchen_and_counter",pickup:"kitchen_and_pickup_shelf",delivery:"kitchen_and_dispatch"})[type];
}
