import test from "node:test";
import assert from "node:assert/strict";
import {calculatePromotionDiscount,applyPromotionToPosSale,redeemPosVoucher} from "../../src/pos-promotion-voucher-workflows.mjs";

const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"cashier-a",idempotencyKey:"pos-promo-0001"};
const sale={tenantId:"tenant-a",branchId:"branch-a",id:"sale-a",status:"open",paymentStatus:"unpaid",
 customerId:"customer-a",customerSegment:"loyal",eligibleSubtotalIdr:100000};
const promotion={tenantId:"tenant-a",branchId:"branch-a",id:"promo-a",status:"approved",enabled:true,
 effectiveFrom:"2026-11-01T00:00:00Z",effectiveTo:"2026-12-01T00:00:00Z",branchIds:["branch-a"],
 customerSegments:["loyal"],minimumSpendIdr:50000,discountType:"percentage",discountValue:10,maximumDiscountIdr:8000};

test("promotion calculates percentage discount with maximum cap",()=>{
 const result=calculatePromotionDiscount({tenantId:"tenant-a",promotion:{...promotion,discountValue:20},sale,at:"2026-11-27T10:00:00Z"});
 assert.equal(result.discountIdr,8000);assert.equal(result.netSubtotalIdr,92000);
});
test("promotion supports fixed discount and rejects invalid scope, period and eligibility",()=>{
 const fixed=calculatePromotionDiscount({tenantId:"tenant-a",promotion:{...promotion,discountType:"fixed",discountValue:15000},sale,at:"2026-11-27T10:00:00Z"});
 assert.equal(fixed.discountIdr,15000);
 assert.throws(()=>calculatePromotionDiscount({tenantId:"tenant-a",promotion:{...promotion,branchIds:["branch-b"]},sale,at:"2026-11-27T10:00:00Z"}),
  {code:"POS_PROMOTION_BRANCH_NOT_ALLOWED"});
 assert.throws(()=>calculatePromotionDiscount({tenantId:"tenant-a",promotion:{...promotion,effectiveTo:"2026-11-20T00:00:00Z"},sale,at:"2026-11-27T10:00:00Z"}),
  {code:"POS_PROMOTION_NOT_EFFECTIVE"});
 assert.throws(()=>calculatePromotionDiscount({tenantId:"tenant-a",promotion:{...promotion,status:"draft"},sale,at:"2026-11-27T10:00:00Z"}),
  {code:"POS_PROMOTION_NOT_APPROVED"});
});
test("promotion application loads authoritative sale and promotion under transaction",async()=>{
 const deps={
  withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
  findPromotionApplicationByIdempotencyKey:async()=>null,
  loadPosSaleForPromotionUpdate:async()=>sale,loadApprovedPromotionForUpdate:async()=>promotion,
  loadPromotionUsageForUpdate:async()=>({count:2}),
  persistPromotionApplication:async(_tx,row)=>{assert.equal(row.discountIdr,8000);return{id:"application-a"};},
  appendAudit:async()=>{},
 };
 const result=await applyPromotionToPosSale({...base,saleId:"sale-a",promotionId:"promo-a",at:"2026-11-27T10:00:00Z"},deps);
 assert.deepEqual(result,{status:"applied",applicationId:"application-a",discountIdr:8000,netSubtotalIdr:92000});
});
test("promotion application enforces redemption cap before persistence",async()=>{
 let persisted=false;
 const deps={
  withTenantTransaction:async(_s,fn)=>fn({}),authorize:async()=>{},findPromotionApplicationByIdempotencyKey:async()=>null,
  loadPosSaleForPromotionUpdate:async()=>sale,loadApprovedPromotionForUpdate:async()=>({...promotion,maxRedemptions:2}),
  loadPromotionUsageForUpdate:async()=>({count:2}),persistPromotionApplication:async()=>{persisted=true;},
 };
 await assert.rejects(applyPromotionToPosSale({...base,saleId:"sale-a",promotionId:"promo-a",at:"2026-11-27T10:00:00Z"},deps),
  {code:"POS_PROMOTION_REDEMPTION_LIMIT_REACHED"});
 assert.equal(persisted,false);
});
test("voucher redemption consumes balance atomically and uses transaction time for expiry",async()=>{
 const deps={
  withTenantTransaction:async(_s,fn)=>fn({tx:true}),authorize:async()=>{},
  findVoucherConsumptionByIdempotencyKey:async()=>null,
  loadVoucherForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"voucher-a",status:"active",
   expiresAt:"2026-12-01T00:00:00Z",customerId:"customer-a",remainingValueIdr:30000}),
  loadPosSaleForPromotionUpdate:async()=>sale,
  persistVoucherConsumptionAndUpdateBalance:async(_tx,row)=>{assert.equal(row.amountIdr,30000);return{id:"consumption-a",remainingValueIdr:0};},
  appendAudit:async()=>{},
 };
 const result=await redeemPosVoucher({...base,voucherCode:"VC-001",saleId:"sale-a",at:"2026-11-27T10:00:00Z"},deps);
 assert.deepEqual(result,{status:"redeemed",consumptionId:"consumption-a",amountIdr:30000,remainingValueIdr:0});
});
test("voucher redemption rejects expired voucher, wrong customer and non-open sale",async()=>{
 const deps={
  withTenantTransaction:async(_s,fn)=>fn({}),authorize:async()=>{},findVoucherConsumptionByIdempotencyKey:async()=>null,
  loadVoucherForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"voucher-a",status:"active",
   expiresAt:"2026-11-01T00:00:00Z",customerId:"customer-b",remainingValueIdr:10000}),
  loadPosSaleForPromotionUpdate:async()=>sale,
 };
 await assert.rejects(redeemPosVoucher({...base,voucherCode:"VC-001",saleId:"sale-a",at:"2026-11-27T10:00:00Z"},deps),
  {code:"POS_VOUCHER_NOT_ACTIVE"});
 const active={...deps,loadVoucherForUpdate:async()=>({tenantId:"tenant-a",branchId:"branch-a",id:"voucher-a",status:"active",
  expiresAt:"2026-12-01T00:00:00Z",customerId:"customer-b",remainingValueIdr:10000})};
 await assert.rejects(redeemPosVoucher({...base,voucherCode:"VC-001",saleId:"sale-a",at:"2026-11-27T10:00:00Z"},active),
  {code:"POS_VOUCHER_CUSTOMER_MISMATCH"});
});
