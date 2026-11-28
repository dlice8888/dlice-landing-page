/** D02-F02: POS cart normalization and server-priced atomic checkout. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("POS_CART_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("POS_CART_ADAPTER_REQUIRED",k);return d[k];};
export function normalizePosCartItems(items){
 if(!Array.isArray(items)||items.length<1||items.length>50)fail("POS_CART_ITEMS_INVALID","Cart requires 1–50 items");
 return items.map((x,i)=>{
  const slug=req(x?.slug,"items["+i+"].slug"),quantity=x?.quantity;
  if(!/^[a-z0-9-]{1,80}$/.test(slug)||!Number.isSafeInteger(quantity)||quantity<1||quantity>1000)fail("POS_CART_ITEM_INVALID","Product and quantity are invalid");
  const modifiers=Array.isArray(x.modifiers)?x.modifiers.map(m=>({code:req(m?.code,"modifier.code")})):[];
  if(modifiers.length>20)fail("POS_CART_MODIFIERS_INVALID","Too many modifiers");
  const substitutions=Array.isArray(x.substitutions)?x.substitutions.map(s=>({recipe_ingredient_id:req(s?.recipe_ingredient_id,"substitution.ingredient"),substitute_inventory_item_id:req(s?.substitute_inventory_item_id,"substitution.item")})):[];
  if(substitutions.length>100)fail("POS_CART_SUBSTITUTIONS_INVALID","Too many substitutions");
  return Object.freeze({slug,quantity,modifiers,substitutions,notes:typeof x.notes==="string"?x.notes.trim().slice(0,500):""});
 });
}
export async function submitPosCart(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  shiftId:req(input?.shiftId,"shiftId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),
  items:normalizePosCartItems(input.items),discountIdr:input.discountIdr??0};
 if(!Number.isSafeInteger(payload.discountIdr)||payload.discountIdr<0)fail("POS_CART_DISCOUNT_INVALID","Discount must be a non-negative integer");
 const result=await fn(deps,"checkoutPosCartAtomically")(payload);
 if(!result?.saleId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||
  !Array.isArray(result.items)||!Number.isSafeInteger(result.totalIdr)||result.totalIdr<0||
  !Number.isSafeInteger(result.discountIdr)||result.discountIdr!==payload.discountIdr)
  fail("POS_CART_SERVER_RESULT_INVALID","Atomic server checkout result is incomplete");
 const itemTotal=result.items.reduce((sum,x)=>sum+x.lineTotalIdr,0);
 if(!Number.isSafeInteger(itemTotal)||itemTotal-result.discountIdr!==result.totalIdr)
  fail("POS_CART_TOTAL_MISMATCH","Persisted sale total does not match server-priced items");
 return Object.freeze(result);
}
