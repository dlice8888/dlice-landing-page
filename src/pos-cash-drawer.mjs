/** D02-F11: cash-in/out and drawer reconciliation. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("POS_CASH_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("POS_CASH_ADAPTER_REQUIRED",k);return d[k];};
const money=(v,k)=>{if(!Number.isSafeInteger(v)||v<=0)fail("POS_CASH_AMOUNT_INVALID",k);return v;};
export async function recordCashDrawerMovement(input,deps){
 const scope={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),shiftId:req(input?.shiftId,"shiftId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),action:"pos.cash.movement"};
 if(!["cash_in","cash_out"].includes(input.movementType))fail("POS_CASH_MOVEMENT_TYPE_INVALID","Movement must be cash_in or cash_out");
 const amountIdr=money(input.amountIdr,"amountIdr"),reason=req(input.reason,"reason");
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  await fn(deps,"authorizeCashDrawer")(tx,scope);
  const shift=await fn(deps,"lockOpenShift")(tx,scope);
  if(!shift||shift.status!=="open")fail("POS_CASH_SHIFT_NOT_OPEN","Cash drawer requires an open assigned shift");
  const result=await fn(deps,"recordCashMovementOnce")(tx,{...scope,movementType:input.movementType,amountIdr,reason});
  if(!result?.movementId||result.shiftId!==scope.shiftId)fail("POS_CASH_MOVEMENT_PERSIST_FAILED","Cash movement was not recorded on this shift");
  await fn(deps,"appendAudit")(tx,{...scope,action:"pos.cash."+input.movementType,entityType:"cash_drawer_movement",entityId:result.movementId,metadata:{amountIdr,reason}});
  return Object.freeze(result);
 });
}
export async function reconcileCashDrawer(input,deps){
 const scope={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),shiftId:req(input?.shiftId,"shiftId"),action:"pos.cash.reconcile"};
 const counted=money(input.countedCashIdr,"countedCashIdr");
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  await fn(deps,"authorizeCashDrawer")(tx,scope);
  const shift=await fn(deps,"lockOpenShift")(tx,scope);
  if(!shift||shift.status!=="open")fail("POS_CASH_SHIFT_NOT_OPEN","Only open shifts can be reconciled");
  const l=await fn(deps,"loadCashDrawerLedger")(tx,scope);
  const expected=l.openingCashIdr+l.cashSalesIdr+l.cashInIdr-l.cashOutIdr-l.cashRefundsIdr;
  if(!Number.isSafeInteger(expected)||expected<0)fail("POS_CASH_LEDGER_INVALID","Cash ledger invalid");
  const variance=counted-expected;
  const result=await fn(deps,"persistCashReconciliation")(tx,{...scope,expectedCashIdr:expected,countedCashIdr:counted,varianceIdr:variance,reason:req(input.reason,"reason")});
  if(!result?.id||result.expectedCashIdr!==expected||result.countedCashIdr!==counted||result.varianceIdr!==variance)fail("POS_CASH_RECONCILIATION_MISMATCH","Persisted reconciliation differs from ledger");
  await fn(deps,"appendAudit")(tx,{...scope,action:"pos.cash.reconciled",entityType:"cash_reconciliation",entityId:result.id,metadata:{expectedCashIdr:expected,countedCashIdr:counted,varianceIdr:variance}});
  return Object.freeze(result);
 });
}
