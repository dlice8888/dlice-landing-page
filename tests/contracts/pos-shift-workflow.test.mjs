import test from "node:test";
import assert from "node:assert/strict";
import {openPosShift,closePosShift} from "../../src/pos-shift-workflow.mjs";
const scope={tenantId:"t1",branchId:"b1",actorId:"u1"};
const openDeps=()=>({withTenantTransaction:async(_s,fn)=>fn({}),authorizeShiftAction:async()=>{},findOpenShiftForActor:async()=>null,
 insertOpenShift:async x=>({id:"sh1",tenantId:x.tenantId,branchId:x.branchId,status:"open"}),appendAudit:async()=>{}});
const closeDeps=(overrides={})=>({withTenantTransaction:async(_s,fn)=>fn({}),authorizeShiftAction:async()=>{},
 lockShiftForUpdate:async()=>({id:"sh1",tenantId:"t1",branchId:"b1",status:"open",openedBy:"u1",actorCanClose:false,actorCanApproveVariance:false}),
 loadShiftCashLedgerForUpdate:async()=>({openingCashIdr:100000,cashSalesIdr:250000,cashInIdr:20000,cashOutIdr:10000,cashRefundsIdr:5000,pendingPaymentCount:0,pendingOrderCount:0,supervisorVarianceThresholdIdr:5000}),
 closeShiftAtomically:async x=>({id:x.shiftId,status:"closed",expectedCashIdr:x.expectedCashIdr,countedCashIdr:x.countedCashIdr,cashVarianceIdr:x.cashVarianceIdr}),appendAudit:async()=>{},...overrides});
test("opens one shift within authorized branch and audits it",async()=>{const r=await openPosShift({...scope,openingCashIdr:100000},openDeps());assert.equal(r.id,"sh1");});
test("rejects a second open shift",async()=>{await assert.rejects(openPosShift(scope,{...openDeps(),findOpenShiftForActor:async()=>({id:"old"})}),{code:"POS_SHIFT_ALREADY_OPEN"});});
test("cash close calculates opening + sales + cash in - cash out - cash refunds",async()=>{const r=await closePosShift({...scope,shiftId:"sh1",countedCashIdr:355000},closeDeps());assert.equal(r.expectedCashIdr,355000);assert.equal(r.cashVarianceIdr,0);});
test("pending payments or orders block shift close",async()=>{await assert.rejects(closePosShift({...scope,shiftId:"sh1",countedCashIdr:355000},closeDeps({loadShiftCashLedgerForUpdate:async()=>({...await closeDeps().loadShiftCashLedgerForUpdate(),pendingPaymentCount:1})})),{code:"POS_SHIFT_PENDING_TRANSACTIONS"});});
test("variance above threshold requires supervisor approval",async()=>{await assert.rejects(closePosShift({...scope,shiftId:"sh1",countedCashIdr:365000},closeDeps()),{code:"POS_SHIFT_VARIANCE_APPROVAL_REQUIRED"});});
test("rejects cross-tenant shift and stale closed shift",async()=>{await assert.rejects(closePosShift({...scope,shiftId:"sh1",countedCashIdr:355000},closeDeps({lockShiftForUpdate:async()=>({id:"sh1",tenantId:"t2",branchId:"b1",status:"open"})})),{code:"POS_SHIFT_NOT_FOUND"});await assert.rejects(closePosShift({...scope,shiftId:"sh1",countedCashIdr:355000},closeDeps({lockShiftForUpdate:async()=>({id:"sh1",tenantId:"t1",branchId:"b1",status:"closed"})})),{code:"POS_SHIFT_NOT_OPEN"});});
