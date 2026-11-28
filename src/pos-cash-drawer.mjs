/** D02-F11: cash-in/out and drawer reconciliation via atomic server RPCs. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("POS_CASH_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("POS_CASH_ADAPTER_REQUIRED",k);return d[k];};
const money=(v,k)=>{if(!Number.isSafeInteger(v)||v<=0)fail("POS_CASH_AMOUNT_INVALID",k);return v;};
export async function recordCashDrawerMovement(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  shiftId:req(input?.shiftId,"shiftId"),idempotencyKey:req(input?.idempotencyKey,"idempotencyKey"),
  movementType:input.movementType,amountIdr:money(input.amountIdr,"amountIdr"),reason:req(input.reason,"reason")};
 if(!["cash_in","cash_out"].includes(payload.movementType))fail("POS_CASH_MOVEMENT_TYPE_INVALID","Movement must be cash_in or cash_out");
 const result=await fn(deps,"recordCashMovementAtomically")(payload);
 if(!result?.movementId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||result.shiftId!==payload.shiftId||result.amountIdr!==payload.amountIdr)
  fail("POS_CASH_MOVEMENT_PERSIST_FAILED","Atomic cash movement result is invalid");
 return Object.freeze(result);
}
export async function reconcileCashDrawer(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  shiftId:req(input?.shiftId,"shiftId"),countedCashIdr:money(input.countedCashIdr,"countedCashIdr"),reason:req(input.reason,"reason")};
 const result=await fn(deps,"reconcileCashDrawerAtomically")(payload);
 if(!result?.reconciliationId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||result.shiftId!==payload.shiftId||
  !result.ledger||result.ledger.pendingPaymentCount!==0||result.ledger.pendingOrderCount!==0)
  fail("POS_CASH_RECONCILIATION_MISMATCH","Cash reconciliation did not include a complete shift ledger");
 const expected=result.ledger.openingCashIdr+result.ledger.cashSalesIdr+result.ledger.cashInIdr-result.ledger.cashOutIdr-result.ledger.cashRefundsIdr;
 if(!Number.isSafeInteger(expected)||expected<0||result.expectedCashIdr!==expected||result.countedCashIdr!==payload.countedCashIdr||result.varianceIdr!==payload.countedCashIdr-expected)
  fail("POS_CASH_LEDGER_MISMATCH","Cash drawer snapshot differs from authoritative ledger");
 return Object.freeze(result);
}
