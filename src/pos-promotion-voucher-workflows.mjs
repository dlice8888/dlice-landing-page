/**
 * Promotion, coupon and voucher pricing rules for POS.
 * Subtotal, customer, usage and voucher balance are loaded from trusted adapters.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const req=(v,f)=>{if(typeof v!=="string"||!v.trim())fail("POS_PROMOTION_INPUT_REQUIRED",f);return v.trim();};
const adapter=(d,n)=>{if(typeof d?.[n]!=="function")fail("POS_PROMOTION_ADAPTER_REQUIRED",n);return d[n];};
const scope=(i,a)=>({tenantId:req(i?.tenantId,"tenantId"),branchId:req(i?.branchId,"branchId"),
 actorId:req(i?.actorId,"actorId"),idempotencyKey:req(i?.idempotencyKey,"idempotencyKey"),action:a});
const txScope=(d,s,fn)=>adapter(d,"withTenantTransaction")(s,async tx=>{
 if(!tx)fail("POS_PROMOTION_TRANSACTION_REQUIRED","Database transaction required");
 await adapter(d,"authorize")(tx,s);return fn(tx);
});
const assertScope=(r,s,name)=>{if(!r||r.tenantId!==s.tenantId||(r.branchId&&r.branchId!==s.branchId))fail("POS_PROMOTION_SCOPE_MISMATCH",name);};

/** Evaluate an approved promotion against an authoritative sale subtotal and cart scope. */
export function calculatePromotionDiscount(input){
 const promotion=input.promotion,sale=input.sale;
 if(!promotion||!sale||promotion.tenantId!==sale.tenantId||promotion.tenantId!==input.tenantId)
  fail("POS_PROMOTION_SCOPE_MISMATCH","Promotion and sale must belong to the same tenant");
 if(promotion.status!=="approved"||promotion.enabled!==true)fail("POS_PROMOTION_NOT_APPROVED","Promotion must be approved and enabled");
 const at=Date.parse(req(input.at,"at")),start=Date.parse(promotion.effectiveFrom),end=promotion.effectiveTo?Date.parse(promotion.effectiveTo):Infinity;
 if(!Number.isFinite(at)||!Number.isFinite(start)||at<start||at>end)fail("POS_PROMOTION_NOT_EFFECTIVE","Promotion is outside its effective period");
 if(promotion.branchIds?.length&&!promotion.branchIds.includes(sale.branchId))fail("POS_PROMOTION_BRANCH_NOT_ALLOWED","Promotion is not valid for this branch");
 if(promotion.customerSegments?.length&&!promotion.customerSegments.includes(sale.customerSegment))
  fail("POS_PROMOTION_CUSTOMER_NOT_ELIGIBLE","Customer does not meet promotion segment requirements");
 const subtotal=Number(sale.eligibleSubtotalIdr);
 if(!Number.isSafeInteger(subtotal)||subtotal<0)fail("POS_PROMOTION_SUBTOTAL_INVALID","Authoritative eligible subtotal must be non-negative integer IDR");
 const minimum=Number(promotion.minimumSpendIdr??0);
 if(!Number.isSafeInteger(minimum)||minimum<0)fail("POS_PROMOTION_MINIMUM_INVALID","Promotion minimum spend is invalid");
 if(subtotal<minimum)fail("POS_PROMOTION_MINIMUM_NOT_MET","Sale does not meet minimum spend");
 const value=Number(promotion.discountValue),max=promotion.maximumDiscountIdr==null?Infinity:Number(promotion.maximumDiscountIdr);
 if(!Number.isFinite(value)||value<=0||!Number.isFinite(max)&&max!==Infinity||max<=0)
  fail("POS_PROMOTION_VALUE_INVALID","Promotion discount values are invalid");
 let discount;
 if(promotion.discountType==="percentage"){
  if(value>100)fail("POS_PROMOTION_PERCENT_INVALID","Percentage discount cannot exceed 100");
  discount=Math.floor(subtotal*value/100);
 }else if(promotion.discountType==="fixed"){
  if(!Number.isSafeInteger(value))fail("POS_PROMOTION_VALUE_INVALID","Fixed discount must be integer IDR");
  discount=value;
 }else fail("POS_PROMOTION_TYPE_INVALID","Unsupported discount type");
 discount=Math.min(subtotal,discount,max);
 return Object.freeze({promotionId:promotion.id,subtotalIdr:subtotal,discountIdr:discount,
  netSubtotalIdr:subtotal-discount,stackable:promotion.stackable===true});
}

/** Apply promotion atomically; client cannot supply price or discount amounts. */
export async function applyPromotionToPosSale(input,deps){
 const s=scope(input,"pos.promotion.apply"),saleId=req(input.saleId,"saleId"),promotionId=req(input.promotionId,"promotionId");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findPromotionApplicationByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",applicationId:prior.id});
  const sale=await adapter(deps,"loadPosSaleForPromotionUpdate")(tx,{...s,saleId});assertScope(sale,s,"sale");
  if(sale.status!=="open"||sale.paymentStatus!=="unpaid")fail("POS_PROMOTION_SALE_NOT_OPEN","Promotion can only be applied to an unpaid open sale");
  const promotion=await adapter(deps,"loadApprovedPromotionForUpdate")(tx,{...s,promotionId});
  assertScope(promotion,s,"promotion");
  const usage=await adapter(deps,"loadPromotionUsageForUpdate")(tx,{...s,promotionId});
  if(promotion.maxRedemptions!=null&&Number(usage.count)>=Number(promotion.maxRedemptions))
   fail("POS_PROMOTION_REDEMPTION_LIMIT_REACHED","Promotion redemption limit has been reached");
  const result=calculatePromotionDiscount({tenantId:s.tenantId,promotion,sale,at:req(input.at,"at")});
  const saved=await adapter(deps,"persistPromotionApplication")(tx,{...s,saleId,promotionId,...result});
  if(!saved?.id)fail("POS_PROMOTION_APPLICATION_FAILED","Promotion application was not persisted");
  await adapter(deps,"appendAudit")(tx,{...s,action:"pos.promotion.applied",entityType:"pos_promotion_application",entityId:saved.id,
   metadata:{saleId,promotionId,discountIdr:result.discountIdr}});
  return Object.freeze({status:"applied",applicationId:saved.id,discountIdr:result.discountIdr,netSubtotalIdr:result.netSubtotalIdr});
 });
}

/** Redeem a tenant/branch-bound voucher with locked balance and immutable consumption record. */
export async function redeemPosVoucher(input,deps){
 const s=scope(input,"pos.voucher.redeem"),voucherCode=req(input.voucherCode,"voucherCode"),saleId=req(input.saleId,"saleId");
 return txScope(deps,s,async tx=>{
  const prior=await adapter(deps,"findVoucherConsumptionByIdempotencyKey")(tx,s);
  if(prior)return Object.freeze({status:"duplicate",consumptionId:prior.id});
  const voucher=await adapter(deps,"loadVoucherForUpdate")(tx,{...s,voucherCode});
  assertScope(voucher,s,"voucher");
  if(voucher.status!=="active"||Date.parse(voucher.expiresAt)<=Date.now())fail("POS_VOUCHER_NOT_ACTIVE","Voucher is expired or inactive");
  const sale=await adapter(deps,"loadPosSaleForPromotionUpdate")(tx,{...s,saleId});assertScope(sale,s,"sale");
  if(sale.status!=="open"||sale.paymentStatus!=="unpaid")fail("POS_VOUCHER_SALE_NOT_OPEN","Voucher can only be redeemed on an unpaid open sale");
  if(voucher.customerId&&voucher.customerId!==sale.customerId)fail("POS_VOUCHER_CUSTOMER_MISMATCH","Voucher belongs to another customer");
  const amount=Number(voucher.remainingValueIdr),subtotal=Number(sale.eligibleSubtotalIdr);
  if(!Number.isSafeInteger(amount)||amount<=0||!Number.isSafeInteger(subtotal)||subtotal<=0)
   fail("POS_VOUCHER_VALUE_INVALID","Voucher balance and sale subtotal must be positive integer IDR");
  const redemption=Math.min(amount,subtotal);
  const saved=await adapter(deps,"persistVoucherConsumptionAndUpdateBalance")(tx,{...s,saleId,voucherId:voucher.id,
   voucherCode,amountIdr:redemption});
  if(!saved?.id||saved.remainingValueIdr!==amount-redemption)fail("POS_VOUCHER_CONSUMPTION_FAILED","Voucher balance and consumption must update atomically");
  await adapter(deps,"appendAudit")(tx,{...s,action:"pos.voucher.redeemed",entityType:"pos_voucher_consumption",entityId:saved.id,
   metadata:{saleId,voucherId:voucher.id,amountIdr:redemption}});
  return Object.freeze({status:"redeemed",consumptionId:saved.id,amountIdr:redemption,remainingValueIdr:saved.remainingValueIdr});
 });
}
