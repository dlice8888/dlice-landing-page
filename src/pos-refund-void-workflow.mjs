/** D02-F09: refund, return and void workflow with atomic financial/stock compensation. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("POS_REFUND_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("POS_REFUND_ADAPTER_REQUIRED",k);return d[k];};
const amount=(v,k)=>{if(!Number.isSafeInteger(v)||v<=0)fail("POS_REFUND_AMOUNT_INVALID",k);return v;};
export async function requestPosRefund(input,deps){
 const scope={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),saleId:req(input?.saleId,"saleId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),action:"pos.refund.request"};
 const value=amount(input.amountIdr,"amountIdr"),reason=req(input.reason,"reason");
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  await fn(deps,"authorizeRefund")(tx,scope);
  const sale=await fn(deps,"lockSaleForRefund")(tx,scope);
  if(!sale||sale.tenantId!==scope.tenantId||sale.branchId!==scope.branchId||sale.paymentStatus!=="paid")fail("POS_REFUND_SOURCE_INVALID","Refund source must be a paid sale in this branch");
  const remaining=sale.totalIdr-(sale.processedRefundIdr??0)-(sale.pendingRefundIdr??0);
  if(value>remaining)fail("POS_REFUND_EXCEEDS_REMAINING","Refund exceeds remaining refundable balance");
  const result=await fn(deps,"createRefundRequestOnce")(tx,{...scope,amountIdr:value,reason,items:input.items??[]});
  if(!result?.refundId||result.status!=="requested")fail("POS_REFUND_REQUEST_FAILED","Refund request was not persisted");
  await fn(deps,"appendAudit")(tx,{...scope,action:"pos.refund.requested",entityType:"refund_record",entityId:result.refundId,metadata:{amountIdr:value,reason}});
  return Object.freeze(result);
 });
}
export async function decidePosRefund(input,deps){
 const scope={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),refundId:req(input?.refundId,"refundId"),action:"pos.refund.decide"};
 if(!["approve","reject"].includes(input.decision))fail("POS_REFUND_DECISION_INVALID","Decision must be approve or reject");
 const reason=req(input.reason,"reason");
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  const refund=await fn(deps,"lockRefundForUpdate")(tx,scope);
  if(!refund||refund.tenantId!==scope.tenantId||refund.branchId!==scope.branchId)fail("POS_REFUND_SCOPE_DENIED","Refund is outside branch scope");
  if(refund.requestedBy===scope.actorId)fail("POS_REFUND_SELF_APPROVAL_DENIED","Requester cannot approve own refund");
  if(refund.status!=="requested")fail("POS_REFUND_NOT_PENDING","Refund is no longer awaiting approval");
  const policy=await fn(deps,"loadRefundApprovalPolicy")(tx,scope);
  if(refund.amountIdr>policy.maxAmountIdr&&!policy.supervisor)fail("POS_REFUND_LIMIT_EXCEEDED","Refund requires a higher-level approver");
  const result=await fn(deps,"decideRefundOnce")(tx,{...scope,decision:input.decision,reason,expectedVersion:input.expectedVersion});
  if(!result?.id||result.status!==(input.decision==="approve"?"approved":"rejected"))fail("POS_REFUND_DECISION_FAILED","Refund decision did not persist");
  await fn(deps,"appendAudit")(tx,{...scope,action:"pos.refund."+input.decision,entityType:"refund_record",entityId:refund.id,metadata:{reason,amountIdr:refund.amountIdr}});
  return Object.freeze(result);
 });
}
export async function processPosRefund(input,deps){
 const scope={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),refundId:req(input?.refundId,"refundId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),action:"pos.refund.process"};
 const reference=req(input.providerReference,"providerReference");
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  const refund=await fn(deps,"lockRefundForUpdate")(tx,scope);
  if(!refund||refund.tenantId!==scope.tenantId||refund.branchId!==scope.branchId)fail("POS_REFUND_SCOPE_DENIED","Refund is outside branch scope");
  if(refund.status!=="approved")fail("POS_REFUND_NOT_APPROVED","Refund must be approved before processing");
  if(refund.requestedBy===scope.actorId||refund.reviewedBy===scope.actorId)fail("POS_REFUND_SEPARATION_OF_DUTIES","Requester or approver cannot process refund");
  const result=await fn(deps,"processRefundAndCompensationsAtomically")(tx,{...scope,providerReference:reference,refund});
  if(!result?.refundId||result.status!=="processed"||result.refundCount!==1||!result.tenderReversalId||!result.financeJournalId||!result.receiptId||!result.auditEventId)
   fail("POS_REFUND_COMPENSATION_INCOMPLETE","Refund, tender reversal, Finance, receipt and audit must commit exactly once");
  return Object.freeze(result);
 });
}
export async function voidUnpaidPosSale(input,deps){
 const scope={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),saleId:req(input?.saleId,"saleId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),action:"pos.sale.void"};
 const reason=req(input.reason,"reason");
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  await fn(deps,"authorizeRefund")(tx,scope);
  const sale=await fn(deps,"lockSaleForRefund")(tx,scope);
  if(!sale||sale.tenantId!==scope.tenantId||sale.branchId!==scope.branchId)fail("POS_VOID_SCOPE_DENIED","Sale outside branch scope");
  if(sale.paymentStatus==="paid"||sale.fulfillmentStatus==="handed_over"||sale.fulfillmentStatus==="completed")fail("POS_VOID_COMPENSATION_REQUIRED","Paid or handed-over sale requires refund/cancellation compensation");
  const result=await fn(deps,"voidSaleOnce")(tx,{...scope,reason});
  if(!result?.saleId||result.paymentStatus!=="voided")fail("POS_VOID_FAILED","Sale void did not persist");
  await fn(deps,"appendAudit")(tx,{...scope,action:"pos.sale.voided",entityType:"pos_sale",entityId:sale.id,metadata:{reason}});
  return Object.freeze(result);
 });
}
