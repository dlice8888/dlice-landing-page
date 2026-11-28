/** D02-F01: POS shift lifecycle. All shift mutations are single atomic server RPCs. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("POS_SHIFT_INPUT_REQUIRED",k);return v.trim();};
const money=(v,k)=>{if(!Number.isSafeInteger(v)||v<0)fail("POS_SHIFT_AMOUNT_INVALID",k);return v;};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("POS_SHIFT_ADAPTER_REQUIRED",k);return d[k];};
export async function openPosShift(input,deps){
 const scope={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),action:"pos.shift.open"};
 const opening=money(input.openingCashIdr??0,"openingCashIdr");
 if(opening>1_000_000_000)fail("POS_SHIFT_AMOUNT_LIMIT","opening cash exceeds branch limit");
 const shift=await fn(deps,"openShiftAtomically")({...scope,openingCashIdr:opening});
 if(!shift?.id||shift.tenantId!==scope.tenantId||shift.branchId!==scope.branchId||shift.status!=="open"||shift.openingCashIdr!==opening)
  fail("POS_SHIFT_CREATE_FAILED","Atomic shift open result is invalid");
 return Object.freeze(shift);
}
export async function closePosShift(input,deps){
 const scope={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),shiftId:req(input?.shiftId,"shiftId"),action:"pos.shift.close"};
 const counted=money(input.countedCashIdr,"countedCashIdr"),reason=req(input.reason??"Shift close","reason");
 const result=await fn(deps,"closeShiftAtomically")({...scope,countedCashIdr:counted,reason});
 if(!result?.shift?.id||result.shift.id!==scope.shiftId||result.shift.status!=="closed"||
  result.shift.countedCashIdr!==counted||!result.ledger||result.ledger.pendingPaymentCount!==0||result.ledger.pendingOrderCount!==0)
  fail("POS_SHIFT_ATOMIC_CLOSE_FAILED","Shift close must return a closed shift and a fully reconciled ledger snapshot");
 const expected=result.ledger.openingCashIdr+result.ledger.cashSalesIdr+result.ledger.cashInIdr-result.ledger.cashOutIdr-result.ledger.cashRefundsIdr;
 if(!Number.isSafeInteger(expected)||expected<0||result.expectedCashIdr!==expected||result.shift.expectedCashIdr!==expected||
  result.cashVarianceIdr!==counted-expected||result.shift.cashVarianceIdr!==counted-expected)
  fail("POS_SHIFT_LEDGER_MISMATCH","Shift close snapshot differs from source cash ledger");
 return Object.freeze(result);
}
