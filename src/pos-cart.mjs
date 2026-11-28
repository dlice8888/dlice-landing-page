/** D02-F03: POS cart input validation. All price, tax, discount and stock checks remain server-authoritative. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("POS_CART_INPUT_REQUIRED",k);return v.trim();};
const amount=(v,k)=>{if(!Number.isSafeInteger(v)||v<0)fail("POS_CART_AMOUNT_INVALID",k);return v;};
const quantity=(v,k)=>{if(!Number.isSafeInteger(v)||v<1||v>999)fail("POS_CART_QUANTITY_INVALID",k);return v;};
export function validatePosCart(input){
 const items=input?.items;
 if(!Array.isArray(items)||items.length<1||items.length>50)fail("POS_CART_ITEMS_INVALID","Cart must contain 1–50 lines");
 const lines=items.map((item,index)=>{
  const slug=req(item?.slug,"items["+index+"].slug");
  const qty=quantity(item?.quantity,"items["+index+"].quantity");
  const modifiers=(item?.modifiers??[]).map(m=>({code:req(m?.code,"modifier.code")}));
  const substitutions=(item?.substitutions??[]).map(s=>({
   recipe_ingredient_id:req(s?.recipe_ingredient_id,"substitution.recipe_ingredient_id"),
   substitute_inventory_item_id:req(s?.substitute_inventory_item_id,"substitution.substitute_inventory_item_id")
  }));
  return Object.freeze({slug,quantity:qty,modifiers,substitutions});
 });
 const discountIdr=amount(input?.discountIdr??0,"discountIdr");
 const paymentMethod=req(input?.paymentMethod,"paymentMethod");
 if(!["cash","bank_transfer","qris","split"].includes(paymentMethod))fail("POS_CART_PAYMENT_METHOD_INVALID","Unsupported payment method");
 const tenders=input?.tenders??[];
 if(!Array.isArray(tenders)||tenders.length>5)fail("POS_CART_TENDERS_INVALID","At most five tenders are supported");
 if(paymentMethod==="split"&&tenders.length<2)fail("POS_CART_TENDERS_INVALID","Split payment requires at least two tenders");
 if(paymentMethod!=="split"&&tenders.length>0)fail("POS_CART_TENDERS_INVALID","Tender allocations require paymentMethod split");
 const canonicalTenders=tenders.map((t,i)=>({
  payment_method:req(t?.paymentMethod,"tenders["+i+"].paymentMethod"),
  amount_idr:amount(t?.amountIdr,"tenders["+i+"].amountIdr"),
  reference:typeof t?.reference==="string"?t.reference.trim().slice(0,120):null
 }));
 if(canonicalTenders.some(t=>!["cash","bank_transfer","qris"].includes(t.payment_method)||t.amount_idr<1))
  fail("POS_CART_TENDERS_INVALID","Tender methods and amounts must be valid");
 if(canonicalTenders.length>0&&new Set(canonicalTenders.map(t=>t.payment_method)).size<2)
  fail("POS_CART_TENDERS_INVALID","Split tender requires distinct payment methods");
 return Object.freeze({items:lines,discountIdr,paymentMethod,tenders:canonicalTenders});
}
export async function checkoutPosCart(input,deps){
 const tenantId=req(input?.tenantId,"tenantId"),branchId=req(input?.branchId,"branchId");
 const actorId=req(input?.actorId,"actorId"),shiftId=req(input?.shiftId,"shiftId");
 const idempotencyKey=req(input?.idempotencyKey,"idempotencyKey");
 if(idempotencyKey.length<8||idempotencyKey.length>120)fail("POS_CART_IDEMPOTENCY_INVALID","Idempotency key must be 8–120 chars");
 const cart=validatePosCart(input);
 if(typeof deps?.checkoutPosCartAtomically!=="function")fail("POS_CART_ADAPTER_REQUIRED","checkoutPosCartAtomically");
 const result=await deps.checkoutPosCartAtomically({tenantId,branchId,actorId,shiftId,idempotencyKey,
  items:cart.items,discountIdr:cart.discountIdr,paymentMethod:cart.paymentMethod,tenders:cart.tenders,
  customerReference:typeof input.customerReference==="string"?input.customerReference.trim().slice(0,120):null,
  notes:typeof input.notes==="string"?input.notes.trim().slice(0,500):null});
 if(!result?.saleId||result.tenantId!==tenantId||result.branchId!==branchId||
  !Number.isSafeInteger(result.totalIdr)||result.totalIdr<0||
  !["pending","paid"].includes(result.paymentStatus))
  fail("POS_CART_CHECKOUT_RESULT_INVALID","Server did not return a valid tenant-scoped POS sale");
 if(result.paymentStatus==="paid"&&(!result.receiptId||result.receiptImmutable!==true))
  fail("POS_CART_RECEIPT_REQUIRED","Paid sale must have an immutable receipt snapshot");
 if(result.paymentStatus==="pending"&&(result.receiptId||result.receiptImmutable===true))
  fail("POS_CART_PENDING_RECEIPT_INVALID","Pending payment must not issue a final receipt");
 return Object.freeze({...result,cart});
}
