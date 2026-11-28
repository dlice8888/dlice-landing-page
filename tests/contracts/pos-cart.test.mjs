import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {validatePosCart,checkoutPosCart} from "../../src/pos-cart.mjs";
const item={slug:"coffee",quantity:2,modifiers:[{code:"oat"}],substitutions:[]};
const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"cashier-a",shiftId:"shift-a",idempotencyKey:"checkout-0001",items:[item],paymentMethod:"cash",discountIdr:0};
test("validates canonical cart payload without trusting browser price fields",()=>{const c=validatePosCart({...base,items:[{...item,unitPriceIdr:1,productName:"tampered"}]});assert.deepEqual(c.items[0],{slug:"coffee",quantity:2,modifiers:[{code:"oat"}],substitutions:[]});});
test("rejects empty cart, invalid quantities, unsafe discount and unknown payment method",()=>{assert.throws(()=>validatePosCart({...base,items:[]}),{code:"POS_CART_ITEMS_INVALID"});assert.throws(()=>validatePosCart({...base,items:[{...item,quantity:0}]}),{code:"POS_CART_QUANTITY_INVALID"});assert.throws(()=>validatePosCart({...base,discountIdr:-1}),{code:"POS_CART_AMOUNT_INVALID"});assert.throws(()=>validatePosCart({...base,paymentMethod:"crypto"}),{code:"POS_CART_PAYMENT_METHOD_INVALID"});});
test("split tender requires the split method, distinct methods and bounded amounts",()=>{assert.throws(()=>validatePosCart({...base,tenders:[{paymentMethod:"cash",amountIdr:10}]}),{code:"POS_CART_TENDERS_INVALID"});assert.throws(()=>validatePosCart({...base,paymentMethod:"split"}),{code:"POS_CART_TENDERS_INVALID"});assert.throws(()=>validatePosCart({...base,paymentMethod:"split",tenders:[{paymentMethod:"cash",amountIdr:10},{paymentMethod:"cash",amountIdr:20}]}),{code:"POS_CART_TENDERS_INVALID"});assert.equal(validatePosCart({...base,paymentMethod:"split",tenders:[{paymentMethod:"cash",amountIdr:100},{paymentMethod:"qris",amountIdr:200}]}).tenders.length,2);});
test("paid sale requires immutable receipt; pending sale remains receipt-free",async()=>{const paid=await checkoutPosCart(base,{checkoutPosCartAtomically:async()=>({tenantId:"tenant-a",branchId:"branch-a",saleId:"sale-a",totalIdr:50000,paymentStatus:"paid",receiptId:"receipt-a",receiptImmutable:true})});assert.equal(paid.totalIdr,50000);const pending=await checkoutPosCart(base,{checkoutPosCartAtomically:async()=>({tenantId:"tenant-a",branchId:"branch-a",saleId:"sale-b",totalIdr:50000,paymentStatus:"pending",receiptId:null,receiptImmutable:false})});assert.equal(pending.paymentStatus,"pending");});
test("rejects cross-tenant and unreceipted paid sale responses",async()=>{await assert.rejects(()=>checkoutPosCart(base,{checkoutPosCartAtomically:async()=>({tenantId:"tenant-b",branchId:"branch-a",saleId:"sale-a",totalIdr:50000,paymentStatus:"paid",receiptId:"r",receiptImmutable:true})}),{code:"POS_CART_CHECKOUT_RESULT_INVALID"});await assert.rejects(()=>checkoutPosCart(base,{checkoutPosCartAtomically:async()=>({tenantId:"tenant-a",branchId:"branch-a",saleId:"sale-a",totalIdr:50000,paymentStatus:"paid",receiptId:null,receiptImmutable:false})}),{code:"POS_CART_RECEIPT_REQUIRED"});});

test("POS UI previews discount but submits the exact integer amount for server-authoritative validation",async()=>{
 const ui=await readFile(new URL("../../erp.html",import.meta.url),"utf8");
 assert.match(ui,/id="posDiscount"/);
 assert.match(ui,/posDiscountField[^;]*classList\.toggle\('hidden',!isOwner\(\)\)/);
 assert.match(ui,/discount_idr:Number\(\$\('posDiscount'\)\.value\|\|0\)/);
 assert.match(ui,/Diskon tidak boleh melebihi subtotal/);
});
