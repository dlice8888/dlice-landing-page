/** Atomic Supabase RPC adapters for D02-F01..F13 POS and Order workflows. */
const required=(v,k)=>{if(typeof v!=="string"||!v.trim())throw Object.assign(new Error(k+" is required"),{code:"POS_RPC_INPUT_REQUIRED"});return v.trim();};
const rpcClient=client=>{if(typeof client?.rpc!=="function")throw Object.assign(new Error("Supabase RPC client required"),{code:"POS_RPC_CLIENT_REQUIRED"});return client;};
const unwrap=(r,code)=>{if(r?.error){const e=new Error(r.error.message||"POS workflow RPC failed");e.code=r.error.code||code;throw e;}return r?.data??null;};
export function createSupabasePosWorkflowAdapter(client,options={}){
 const db=rpcClient(client),verify=options.verifyProviderSignature;
 const call=async(name,args,code)=>unwrap(await db.rpc(name,args),code);
 return Object.freeze({
  openShiftAtomically:i=>call("pos_open_shift_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_actor_user_id:required(i.actorId,"actorId"),p_opening_cash_idr:i.openingCashIdr},"POS_SHIFT_OPEN_RPC_FAILED"),
  closeShiftAtomically:i=>call("pos_close_shift_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_actor_user_id:required(i.actorId,"actorId"),p_shift_id:required(i.shiftId,"shiftId"),p_counted_cash_idr:i.countedCashIdr,p_reason:required(i.reason,"reason")},"POS_SHIFT_CLOSE_RPC_FAILED"),
  checkoutPosCartAtomically:async i=>{
   const tenantId=required(i.tenantId,"tenantId"),branchId=required(i.branchId,"branchId"),actorId=required(i.actorId,"actorId");
   const shiftId=required(i.shiftId,"shiftId"),idempotencyKey=required(i.idempotencyKey,"idempotencyKey");
   const {data:branch,error:branchError}=await db.from("branches").select("id").eq("id",branchId).eq("tenant_id",tenantId).maybeSingle();
   if(branchError||!branch)throw Object.assign(new Error("POS branch is outside tenant scope"),{code:"POS_BRANCH_SCOPE_DENIED"});
   const pItems=i.items.map(x=>({slug:x.slug,quantity:String(x.quantity),modifiers:x.modifiers,substitutions:x.substitutions}));
   const sale=i.tenders?.length
    ? await call("erp_create_pos_sale_split_tender_idempotent",{p_branch_id:branchId,p_shift_id:shiftId,p_items:pItems,p_discount_idr:i.discountIdr,p_customer_reference:i.customerReference,p_notes:i.notes,p_actor_user_id:actorId,p_idempotency_key:idempotencyKey,p_tenders:i.tenders},"POS_CART_CHECKOUT_RPC_FAILED")
    : await call("erp_create_pos_sale_idempotent",{p_branch_id:branchId,p_shift_id:shiftId,p_items:pItems,p_payment_method:i.paymentMethod,p_discount_idr:i.discountIdr,p_customer_reference:i.customerReference,p_notes:i.notes,p_actor_user_id:actorId,p_idempotency_key:idempotencyKey},"POS_CART_CHECKOUT_RPC_FAILED");
   const saleId=required(sale?.sale_id??sale?.saleId,"sale_id");
   const {data:row,error:readError}=await db.from("pos_sales").select("id,branch_id,total_idr,payment_status").eq("id",saleId).eq("branch_id",branchId).maybeSingle();
   if(readError||!row)throw Object.assign(new Error("Created sale could not be verified in branch scope"),{code:"POS_CART_SALE_READBACK_FAILED"});
   let receiptId=null,receiptImmutable=false;
   if(row.payment_status==="paid"){
    const receipt=await call("erp_get_pos_receipt",{p_branch_id:branchId,p_sale_id:saleId,p_actor_user_id:actorId},"POS_CART_RECEIPT_RPC_FAILED");
    receiptId=receipt?.receipt_id??null;receiptImmutable=Boolean(receiptId&&receipt?.snapshot&&receipt?.receipt_version);
   }
   return {tenantId,branchId,saleId,totalIdr:Number(row.total_idr),paymentStatus:row.payment_status,
    receiptId,receiptImmutable,transactionCode:sale?.transaction_code??null,idempotentReplay:sale?.idempotent_replay===true};
  },
  createPosOrderAtomically:async i=>{
   const result=await call("pos_create_order_with_fulfillment_atomic",{
    p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),
    p_actor_user_id:required(i.actorId,"actorId"),p_shift_id:required(i.shiftId,"shiftId"),
    p_idempotency_key:required(i.idempotencyKey,"idempotencyKey"),p_fulfillment:i.fulfillment,p_items:i.items,
    p_payment_method:required(i.paymentMethod,"paymentMethod"),p_discount_idr:i.discountIdr??0,
    p_customer_reference:i.customerReference??null,p_notes:i.notes??null,p_tenders:i.tenders??null
   },"POS_ORDER_CREATE_RPC_FAILED");
   return {tenantId:i.tenantId,branchId:i.branchId,orderId:result?.order_id,fulfillmentId:result?.fulfillment_id,
    orderType:result?.order_type,paymentStatus:result?.payment_status,fulfillmentStatus:result?.fulfillment_status,
    saleId:result?.sale_id,transactionCode:result?.transaction_code,totalIdr:result?.total_idr,
    idempotentReplay:result?.idempotent_replay===true};
  },
  createPaymentIntentAtomically:i=>call("pos_create_payment_intent_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_actor_user_id:required(i.actorId,"actorId"),p_sale_id:required(i.saleId,"saleId"),p_idempotency_key:required(i.idempotencyKey,"idempotencyKey"),p_payment_method:i.paymentMethod,p_provider_id:i.providerId},"POS_PAYMENT_INTENT_RPC_FAILED"),
  recordTenderAtomically:i=>call("pos_record_tender_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_actor_user_id:required(i.actorId,"actorId"),p_sale_id:required(i.saleId,"saleId"),p_idempotency_key:required(i.idempotencyKey,"idempotencyKey"),p_payment_method:i.paymentMethod,p_amount_idr:i.amountIdr,p_provider_event_id:i.verifiedProviderEventId,p_reference:i.reference},"POS_TENDER_RPC_FAILED"),
  verifyProviderSignature:async i=>{if(typeof verify!=="function")throw Object.assign(new Error("Provider signature verifier is not configured"),{code:"POS_PROVIDER_VERIFIER_REQUIRED"});return verify(i);},
  applyVerifiedProviderEventAtomically:i=>call("pos_apply_provider_event_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_provider_id:required(i.providerId,"providerId"),p_event_id:required(i.eventId,"eventId"),p_timestamp:i.timestamp,p_signature_verified:i.signatureVerified,p_payload_hash:i.payloadHash,p_sale_id:required(i.saleId,"saleId"),p_amount_idr:i.amountIdr},"POS_PROVIDER_EVENT_RPC_FAILED"),
  reconcileSettlementAtomically:i=>call("pos_reconcile_settlement_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_actor_user_id:required(i.actorId,"actorId"),p_settlement_id:required(i.settlementId,"settlementId")},"POS_SETTLEMENT_RPC_FAILED"),
  requestRefundAtomically:i=>call("pos_request_refund_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_actor_user_id:required(i.actorId,"actorId"),p_sale_id:required(i.saleId,"saleId"),p_idempotency_key:required(i.idempotencyKey,"idempotencyKey"),p_amount_idr:i.amountIdr,p_reason:required(i.reason,"reason"),p_items:i.items},"POS_REFUND_REQUEST_RPC_FAILED"),
  decideRefundAtomically:i=>call("pos_decide_refund_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_actor_user_id:required(i.actorId,"actorId"),p_refund_id:required(i.refundId,"refundId"),p_decision:i.decision,p_reason:required(i.reason,"reason"),p_expected_version:i.expectedVersion},"POS_REFUND_DECISION_RPC_FAILED"),
  processRefundAndCompensationsAtomically:i=>call("pos_process_refund_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_actor_user_id:required(i.actorId,"actorId"),p_refund_id:required(i.refundId,"refundId"),p_idempotency_key:required(i.idempotencyKey,"idempotencyKey"),p_provider_reference:required(i.providerReference,"providerReference")},"POS_REFUND_PROCESS_RPC_FAILED"),
  voidUnpaidSaleAtomically:i=>call("pos_void_sale_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_actor_user_id:required(i.actorId,"actorId"),p_sale_id:required(i.saleId,"saleId"),p_idempotency_key:required(i.idempotencyKey,"idempotencyKey"),p_reason:required(i.reason,"reason")},"POS_SALE_VOID_RPC_FAILED"),
  recordCashMovementAtomically:i=>call("pos_record_cash_movement_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_actor_user_id:required(i.actorId,"actorId"),p_shift_id:required(i.shiftId,"shiftId"),p_idempotency_key:required(i.idempotencyKey,"idempotencyKey"),p_movement_type:i.movementType,p_amount_idr:i.amountIdr,p_reason:required(i.reason,"reason")},"POS_CASH_MOVEMENT_RPC_FAILED"),
  reconcileCashDrawerAtomically:i=>call("pos_reconcile_cash_drawer_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_actor_user_id:required(i.actorId,"actorId"),p_shift_id:required(i.shiftId,"shiftId"),p_counted_cash_idr:i.countedCashIdr,p_reason:required(i.reason,"reason")},"POS_CASH_RECONCILIATION_RPC_FAILED"),
  transitionOrderStateAtomically:i=>call("pos_transition_order_state_atomic",{p_tenant_id:required(i.tenantId,"tenantId"),p_branch_id:required(i.branchId,"branchId"),p_actor_user_id:required(i.actorId,"actorId"),p_order_id:required(i.orderId,"orderId"),p_domain:i.domain,p_next_status:i.nextStatus,p_expected_version:i.expectedVersion,p_idempotency_key:required(i.idempotencyKey,"idempotencyKey"),p_payment_evidence_type:i.paymentEvidenceType,p_handover_acknowledgement:i.handoverAcknowledgement,p_reason:i.reason},"ORDER_STATE_RPC_FAILED"),
 });
}
