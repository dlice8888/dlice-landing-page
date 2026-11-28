import test from "node:test";
import assert from "node:assert/strict";
import {normalizePosCartItems,submitPosCart} from "../../src/pos-cart.mjs";
const scope={tenantId:"t1",branchId:"b1",actorId:"u1",shiftId:"sh1",idempotencyKey:"cart-key-123"};
const base=()=>({withTenantTransaction:async(_s,fn)=>fn({}),authorizeCheckout:async()=>{},lockOpenShift:async()=>({status:"open"}),
 createSaleFromServerCatalogOnce:async(_tx,x)=>({saleId:"s1",totalIdr:18000,items:[{lineTotalIdr:20000,unitPriceIdr:10000,quantity:2}],discountIdr:x.discountIdr}),
 appendAudit:async()=>{}});
test("normalizes only product IDs, quantity, modifiers and substitutions",()=>{const r=normalizePosCartItems([{slug:"kopi-susu",quantity:2,unit_price_idr:1,modifiers:[{code:"less-sugar"}]}]);assert.equal(r[0].quantity,2);assert.equal("unit_price_idr" in r[0],false);});
test("rejects invalid quantity and excessive cart size",()=>{assert.throws(()=>normalizePosCartItems([{slug:"x",quantity:0}]),{code:"POS_CART_ITEM_INVALID"});assert.throws(()=>normalizePosCartItems([]),{code:"POS_CART_ITEMS_INVALID"});});
test("checkout delegates price and availability to server adapter",async()=>{let received;const d={...base(),createSaleFromServerCatalogOnce:async(_tx,x)=>(received=x,{saleId:"s1",totalIdr:18000,items:[{lineTotalIdr:20000,unitPriceIdr:10000,quantity:2}]})};const r=await submitPosCart({...scope,items:[{slug:"kopi-susu",quantity:2,unit_price_idr:1}],discountIdr:2000},d);assert.equal(r.totalIdr,18000);assert.equal(received.items[0].slug,"kopi-susu");assert.equal("unit_price_idr" in received.items[0],false);});
test("rejects a closed shift and server total mismatch",async()=>{await assert.rejects(submitPosCart({...scope,items:[{slug:"kopi",quantity:1}]},{...base(),lockOpenShift:async()=>({status:"closed"})}),{code:"POS_CART_SHIFT_NOT_OPEN"});await assert.rejects(submitPosCart({...scope,items:[{slug:"kopi",quantity:2}]},{...base(),createSaleFromServerCatalogOnce:async()=>({saleId:"s1",totalIdr:1,items:[{lineTotalIdr:20000}]})}),{code:"POS_CART_TOTAL_MISMATCH"});});
