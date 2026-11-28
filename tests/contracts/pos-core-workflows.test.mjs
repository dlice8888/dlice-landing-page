import test from "node:test";
import assert from "node:assert/strict";
import { calculateExpectedDrawer, assertShiftOpenAllowed, assertShiftCloseAllowed } from "../../src/pos-shift-workflow.mjs";
import { buildValidatedCart } from "../../src/pos-cart.mjs";
import { validatePosOrderType, fulfillmentQueueForType } from "../../src/pos-order-type.mjs";
import { validateTenderAllocations, assertProviderPaymentConfirmation, assertPaymentStatusMutation } from "../../src/pos-payment-methods.mjs";
import { validateRefundRequest, assertRefundProcessable } from "../../src/pos-refund-void-workflow.mjs";
import { assertLifecycleTransition, assertLifecycleConsistency } from "../../src/order-payment-fulfillment-state.mjs";

test("shift drawer expected cash reconciles opening, sales, cash in/out and refunds",()=>{
 assert.equal(calculateExpectedDrawer({openingCashIdr:100000,cashSalesIdr:250000,cashInIdr:20000,cashOutIdr:10000,cashRefundsIdr:15000}),345000);
 assert.throws(()=>calculateExpectedDrawer({openingCashIdr:0,cashSalesIdr:0,cashRefundsIdr:1}),/drawer_expected_out_of_range/);
});
test("shift open and close enforce assignment, pending sales and variance approval",()=>{
 assert.throws(()=>assertShiftOpenAllowed({actorUserId:"u1",assignedBranchIds:["b2"],branchId:"b1",openingCashIdr:0}),/shift_branch_forbidden/);
 assert.throws(()=>assertShiftOpenAllowed({actorUserId:"u1",assignedBranchIds:["b1"],branchId:"b1",openingCashIdr:0,existingOpenShift:{id:"s"}}),/shift_already_open/);
 const shift={id:"s",branch_id:"b1",opened_by:"u1",status:"open",expected_cash_idr:1000};
 assert.throws(()=>assertShiftCloseAllowed({shift,actorUserId:"u1",assignedBranchIds:["b1"],pendingSaleCount:1,countedCashIdr:1000}),/shift_has_pending_sales/);
 assert.throws(()=>assertShiftCloseAllowed({shift,actorUserId:"u1",assignedBranchIds:["b1"],countedCashIdr:1100,varianceApprovalRequired:true}),/variance_approval_required/);
 assert.equal(assertShiftCloseAllowed({shift,actorUserId:"u1",assignedBranchIds:["b1"],countedCashIdr:900}).cash_variance_idr,-100);
});
test("cart pricing comes from active server catalog, validates stock and modifiers",()=>{
 const catalog=[{id:"p1",name:"Cake",is_active:true,unit_price_idr:10000,allowed_branch_ids:["b1"],modifiers:[{id:"m1",name:"Extra",price_idr:2000,is_active:true}],required_modifier_groups:[{option_ids:["m1"]}]}];
 const cart=buildValidatedCart({requestedItems:[{productId:"p1",quantity:2,modifierIds:["m1"],unitPriceIdr:1}],catalogItems:catalog,branchId:"b1",availableStockByProduct:{p1:2}});
 assert.equal(cart.subtotal_idr,24000);
 assert.throws(()=>buildValidatedCart({requestedItems:[{productId:"p1",quantity:3}],catalogItems:catalog,branchId:"b1",availableStockByProduct:{p1:2}}),/insufficient_available_stock/);
 assert.throws(()=>buildValidatedCart({requestedItems:[{productId:"p1",quantity:1}],catalogItems:catalog,branchId:"b1"}),/required_modifier_missing/);
});
test("order type enforces type-specific data and routes fulfillment separately",()=>{
 assert.throws(()=>validatePosOrderType({type:"dine_in",branchEnabledTypes:["dine_in"]}),/dine_in_table_required/);
 assert.throws(()=>validatePosOrderType({type:"delivery",branchEnabledTypes:["delivery"]}),/delivery_destination_required/);
 assert.equal(fulfillmentQueueForType("pickup"),"kitchen_and_pickup_shelf");
 assert.throws(()=>validatePosOrderType({type:"takeaway",branchEnabledTypes:["takeaway"],paid:true,previousType:"delivery"}),/paid_order_type_change_forbidden/);
});
test("tender allocations exactly match sale total and paid requires trusted proof",()=>{
 assert.equal(validateTenderAllocations({saleTotalIdr:10000,tenders:[{method:"cash",amount_idr:4000},{method:"qris",amount_idr:6000}]}).allocated_idr,10000);
 assert.throws(()=>validateTenderAllocations({saleTotalIdr:10000,tenders:[{method:"cash",amount_idr:11000}]}),/tender_overpayment/);
 assert.throws(()=>assertPaymentStatusMutation({requestedStatus:"paid",source:"client",proofVerified:true}),/client_cannot_mark_paid/);
 assert.throws(()=>assertProviderPaymentConfirmation({method:"qris",signatureValid:true,replayDetected:true,providerReference:"ref",amountIdr:100,expectedAmountIdr:100,providerStatus:"succeeded"}),/provider_event_replayed/);
});
test("refund requires branch match, remaining paid balance, reason and separation of duties",()=>{
 const input={saleId:"s1",branchId:"b1",requestedBranchId:"b1",paidAmountIdr:10000,previouslyRefundedIdr:2000,refundAmountIdr:3000,reason:"Customer returned item",requestedBy:"u1",approvedBy:"u2",soldQuantities:{i1:2},returnItems:[{saleItemId:"i1",quantity:1,restock:true}]};
 assert.equal(validateRefundRequest(input).amount_idr,3000);
 assert.throws(()=>validateRefundRequest({...input,approvedBy:"u1"}),/refund_self_approval_forbidden/);
 assert.throws(()=>validateRefundRequest({...input,refundAmountIdr:9000}),/refund_exceeds_remaining_paid_amount/);
 assert.throws(()=>assertRefundProcessable({status:"approved",idempotencyKey:"short",approvalRequired:true,approved:true,actorUserId:"u2",requestedBy:"u1"}),/refund_idempotency_key_required/);
});
test("order, payment and fulfillment state transitions are independent and versioned",()=>{
 assert.equal(assertLifecycleTransition({axis:"payment",from:"pending",to:"paid",actorDomain:"trusted_provider",expectedVersion:2,currentVersion:2,eventId:"evt-1"}).append_only,true);
 assert.throws(()=>assertLifecycleTransition({axis:"payment",from:"pending",to:"paid",actorDomain:"customer",expectedVersion:2,currentVersion:2,eventId:"evt-1"}),/lifecycle_actor_forbidden/);
 assert.throws(()=>assertLifecycleTransition({axis:"fulfillment",from:"preparing",to:"fulfilled",actorDomain:"kitchen",expectedVersion:1,currentVersion:2,eventId:"evt-2"}),/lifecycle_stale_version/);
 assert.throws(()=>assertLifecycleConsistency({orderStatus:"cancelled",paymentStatus:"paid",fulfillmentStatus:"preparing"}),/requires_compensation/);
});
