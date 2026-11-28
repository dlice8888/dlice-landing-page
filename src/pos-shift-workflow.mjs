/** D02-F01: POS shift lifecycle with atomic cash close and audit. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("POS_SHIFT_INPUT_REQUIRED",k);return v.trim();};
const money=(v,k)=>{if(!Number.isSafeInteger(v)||v<0)fail("POS_SHIFT_AMOUNT_INVALID",k);return v;};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("POS_SHIFT_ADAPTER_REQUIRED",k);return d[k];};
async function transact(input,deps,action,work){
 const scope={tenantId:req(input.tenantId,"tenantId"),branchId:req(input.branchId,"branchId"),actorId:req(input.actorId,"actorId"),action};
 return fn(deps,"withTenantTransaction")(scope,async tx=>{if(!tx)fail("POS_SHIFT_TRANSACTION_REQUIRED","transaction required");await fn(deps,"authorizeShiftAction")(tx,scope);return work(tx,scope);});
}
export async function openPosShift(input,deps){
 const opening=money(input.openingCashIdr??0,"openingCashIdr");
 if(opening>1_000_000_000)fail("POS_SHIFT_AMOUNT_LIMIT","opening cash exceeds branch limit");
 return transact(input,deps,"pos.shift.open",async(tx,scope)=>{
  const existing=await fn(deps,"findOpenShiftForActor")(tx,scope);
  if(existing)fail("POS_SHIFT_ALREADY_OPEN","Actor already has an open shift in this branch");
  const shift=await fn(deps,"insertOpenShift")(tx,{...scope,openingCashIdr:opening});
  if(!shift?.id||shift.tenantId!==scope.tenantId||shift.branchId!==scope.branchId||shift.status!=="open")fail("POS_SHIFT_CREATE_FAILED","Open shift was not persisted in authorized branch");
  await fn(deps,"appendAudit")(tx,{...scope,action:"pos.shift.opened",entityType:"pos_shift",entityId:shift.id,metadata:{openingCashIdr:opening}});
  return Object.freeze(shift);
 });
}
export async function closePosShift(input,deps){
 const shiftId=req(input.shiftId,"shiftId"),counted=money(input.countedCashIdr,"countedCashIdr");
 const note=req(input.reason??"Shift close","reason");
 return transact(input,deps,"pos.shift.close",async(tx,scope)=>{
  const shift=await fn(deps,"lockShiftForUpdate")(tx,{...scope,shiftId});
  if(!shift||shift.tenantId!==scope.tenantId||shift.branchId!==scope.branchId)fail("POS_SHIFT_NOT_FOUND","Shift not found in authorized branch");
  if(shift.status!=="open")fail("POS_SHIFT_NOT_OPEN","Only an open shift can be closed");
  if(shift.openedBy!==scope.actorId&&!shift.actorCanClose)fail("POS_SHIFT_CLOSE_FORBIDDEN","Only the assigned cashier or authorized supervisor can close this shift");
  const ledger=await fn(deps,"loadShiftCashLedgerForUpdate")(tx,{...scope,shiftId});
  const opening=money(ledger.openingCashIdr,"openingCashIdr"),cashSales=money(ledger.cashSalesIdr,"cashSalesIdr"),
   cashIn=money(ledger.cashInIdr,"cashInIdr"),cashOut=money(ledger.cashOutIdr,"cashOutIdr"),
   cashRefunds=money(ledger.cashRefundsIdr,"cashRefundsIdr");
  if(ledger.pendingPaymentCount!==0||ledger.pendingOrderCount!==0)fail("POS_SHIFT_PENDING_TRANSACTIONS","Shift has pending payments or orders");
  const expected=opening+cashSales+cashIn-cashOut-cashRefunds;
  if(!Number.isSafeInteger(expected)||expected<0)fail("POS_SHIFT_LEDGER_INVALID","Cash ledger produced an invalid expected drawer");
  const variance=counted-expected,threshold=money(ledger.supervisorVarianceThresholdIdr??0,"supervisorVarianceThresholdIdr");
  if(Math.abs(variance)>threshold&&!shift.actorCanApproveVariance)fail("POS_SHIFT_VARIANCE_APPROVAL_REQUIRED","Variance exceeds cashier authority; supervisor approval is required");
  const closed=await fn(deps,"closeShiftAtomically")(tx,{...scope,shiftId,expectedCashIdr:expected,countedCashIdr:counted,
   cashVarianceIdr:variance,reason:note,ledgerSnapshot:{openingCashIdr:opening,cashSalesIdr:cashSales,cashInIdr:cashIn,cashOutIdr:cashOut,cashRefundsIdr:cashRefunds}});
  if(!closed?.id||closed.id!==shiftId||closed.status!=="closed"||closed.expectedCashIdr!==expected||closed.countedCashIdr!==counted||closed.cashVarianceIdr!==variance)
   fail("POS_SHIFT_ATOMIC_CLOSE_FAILED","Shift close snapshot does not match computed ledger");
  await fn(deps,"appendAudit")(tx,{...scope,action:"pos.shift.closed",entityType:"pos_shift",entityId:shiftId,metadata:{expectedCashIdr:expected,countedCashIdr:counted,cashVarianceIdr:variance}});
  return Object.freeze({shift:closed,ledger:ledger,expectedCashIdr:expected,countedCashIdr:counted,cashVarianceIdr:variance});
 });
}
