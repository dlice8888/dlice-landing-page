/** D05-F03: central/regional/branch price precedence and effective dates. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("PRICING_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("PRICING_ADAPTER_REQUIRED",k);return d[k];};
export async function resolveEffectiveProductPrice(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),productId:req(input?.productId,"productId"),businessAt:req(input?.businessAt,"businessAt")};
 const result=await fn(deps,"resolveEffectiveProductPriceReadOnly")(payload);
 if(!result||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||result.productId!==payload.productId||
  !Number.isSafeInteger(result.priceIdr)||result.priceIdr<0||!["central","regional","branch"].includes(result.scope)||
  !result.policyVersion)fail("PRICING_RESOLUTION_INVALID","Effective price result lacks scope, precedence or version");
 return Object.freeze(result);
}
export async function requestProductPriceChange(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),actorId:req(input?.actorId,"actorId"),scope:input.scope,branchId:input.branchId??null,
  regionId:input.regionId??null,productId:req(input?.productId,"productId"),priceIdr:input.priceIdr,effectiveFrom:req(input?.effectiveFrom,"effectiveFrom"),
  reason:req(input?.reason,"reason"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey")};
 if(!["central","regional","branch"].includes(payload.scope)||!Number.isSafeInteger(payload.priceIdr)||payload.priceIdr<0)fail("PRICING_CHANGE_INVALID","Price scope and amount invalid");
 const result=await fn(deps,"requestProductPriceChangeAtomically")(payload);
 if(!result?.requestId||result.tenantId!==payload.tenantId||result.status!=="pending_approval")fail("PRICING_CHANGE_REQUEST_FAILED","Price change request not persisted");
 return Object.freeze(result);
}
