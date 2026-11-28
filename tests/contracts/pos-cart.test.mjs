import test from "node:test";
import assert from "node:assert/strict";
import {normalizePosCartItems,submitPosCart} from "../../src/pos-cart.mjs";
const scope={tenantId:"t1",branchId:"b1",actorId:"u1",shiftId:"sh1",idempotencyKey:"cart-key-123"};
const result={saleId:"s1",tenantId:"t1",branchId:"b1",totalIdr:18000,discountIdr:2000,items:[{lineTotalIdr:20000,unitPriceIdr:10000,quantity:2}]};
test("normalizes only product identifiers and quantity, never client prices",()=>{const r=normalizePosCartItems([{slug:"kopi-susu",quantity:2,unit_price_idr:1,modifiers:[{code:"less-sugar"}]}]);assert.equal(r[0].quantity,2);assert.equal("unit_price_idr" in r[0],false);});
test("rejects invalid quantity and excessive cart size",()=>{assert.throws(()=>normalizePosCartItems([{slug:"x",quantity:0}]),{code:"POS_CART_ITEM_INVALID"});assert.throws(()=>normalizePosCartItems([]),{code:"POS_CART_ITEMS_INVALID"});});
test("checkout delegates price and availability to one atomic server operation",async()=>{let received;const r=await submitPosCart({...scope,items:[{slug:"kopi-susu",quantity:2,unit_price_idr:1}],discountIdr:2000},{checkoutPosCartAtomically:async x=>(received=x,result)});assert.equal(r.totalIdr,18000);assert.equal(received.items[0].slug,"kopi-susu");assert.equal("unit_price_idr" in received.items[0],false);});
test("rejects server total mismatch and missing RPC",async()=>{await assert.rejects(submitPosCart({...scope,items:[{slug:"kopi",quantity:2}]},{checkoutPosCartAtomically:async()=>({...result,totalIdr:1})}),{code:"POS_CART_TOTAL_MISMATCH"});await assert.rejects(submitPosCart({...scope,items:[{slug:"kopi",quantity:2}]},{}),{code:"POS_CART_ADAPTER_REQUIRED"});});
