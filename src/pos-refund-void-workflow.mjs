/** D02-F09: refund, return and void through atomic source-domain RPCs. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("POS_REFUND_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("POS_REFUND_ADAPTER_REQUIRED",k);return d[k];};
const amount=(v,k)=>{if(!Number.isSafeInteger(v)||v<=0)fail("POS_REFUND_AMOUNT_INVALID",k);return v;};
export async function requestPosRefund(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  saleId:req(input?.saleId,"saleId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),
  amountIdr:amount(input.amountIdr,"amountIdr"),reason:req(input.reason,"reason"),items:Array.isArray(input.items)?input.items:[]};
 const result=await fn(deps,"requestRefundAtomically")(payload);
 if(!result?.refundId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||
  result.status!=="requested"||!Number.isSafeInteger(result.remainingRefundableIdr)||result.remainingRefundableIdr<0)
  fail("POS_REFUND_REQUEST_FAILED","Atomic refund request result is invalid");
 return Object.freeze(result);
}
export async function decidePosRefund(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  refundId:req(input?.refundId,"refundId"),decision:input.decision,reason:req(input.reason,"reason"),expectedVersion:input.expectedVersion};
 if(!["approve","reject"].includes(payload.decision))fail("POS_REFUND_DECISION_INVALID","Decision must be approve or reject");
 if(!Number.isSafeInteger(payload.expectedVersion)||payload.expectedVersion<0)fail("POS_REFUND_VERSION_REQUIRED","Expected version required");
 const result=await fn(deps,"decideRefundAtomically")(payload);
 if(!result?.refundId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||
  result.status!==(payload.decision==="approve"?"approved":"rejected")||result.version!==payload.expectedVersion+1)
  fail("POS_REFUND_DECISION_FAILED","Atomic refund decision result is invalid");
 return Object.freeze(result);
}
export async function processPosRefund(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  refundId:req(input?.refundId,"refundId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),
  providerReference:req(input.providerReference,"providerReference")};
 const result=await fn(deps,"processRefundAndCompensationsAtomically")(payload);
 const baseComplete=result?.refundId&&result.tenantId===payload.tenantId&&result.branchId===payload.branchId&&
  result.status==="processed"&&result.refundCount===1&&result.tenderReversalId&&result.financeJournalId&&result.receiptId&&result.auditEventId;
 if(!baseComplete||(result.stockReturnRequired===true&&(!Array.isArray(result.stockReturnMovementIds)||!result.stockReturnMovementIds.length)))
  fail("POS_REFUND_COMPENSATION_INCOMPLETE","Refund, tender reversal, applicable stock, Finance, receipt and audit must commit exactly once");
 return Object.freeze(result);
}
export async function voidUnpaidPosSale(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  saleId:req(input?.saleId,"saleId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),reason:req(input.reason,"reason")};
 const result=await fn(deps,"voidUnpaidSaleAtomically")(payload);
 if(!result?.saleId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||result.paymentStatus!=="voided")
  fail("POS_VOID_FAILED","Atomic unpaid sale void result is invalid");
 return Object.freeze(result);
}
