/** D05-F02: branch-specific product availability and override audit. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("BRANCH_AVAILABILITY_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("BRANCH_AVAILABILITY_ADAPTER_REQUIRED",k);return d[k];};
export async function setBranchProductAvailability(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  productId:req(input?.productId,"productId"),available:input.available,startsAt:input.startsAt??null,endsAt:input.endsAt??null,
  reason:req(input.reason,"reason"),expectedVersion:input.expectedVersion};
 if(typeof payload.available!=="boolean"||!Number.isSafeInteger(payload.expectedVersion)||payload.expectedVersion<0)fail("BRANCH_AVAILABILITY_PAYLOAD_INVALID","Availability and expected version required");
 if(payload.startsAt&&payload.endsAt&&Date.parse(payload.endsAt)<=Date.parse(payload.startsAt))fail("BRANCH_AVAILABILITY_RANGE_INVALID","Availability end must follow start");
 const result=await fn(deps,"setBranchProductAvailabilityAtomically")(payload);
 if(!result?.productId||result.productId!==payload.productId||result.branchId!==payload.branchId||result.available!==payload.available||
  result.version!==payload.expectedVersion+1)fail("BRANCH_AVAILABILITY_UPDATE_FAILED","Branch availability update did not persist");
 return Object.freeze(result);
}
