/** Delivery customer charge, COD, subsidy and carrier fee reconciliation. */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
const money=(v,k)=>{if(!Number.isSafeInteger(v)||v<0)fail("DELIVERY_AMOUNT_INVALID",k);return v;};
export function reconcileDeliveryFinancials({dispatch,order,providerSettlement,financePosting,expectedSubsidyIdr}) {
 if(!dispatch?.id||dispatch.status!=="delivered"||!dispatch.providerOrderReference)fail("DELIVERY_NOT_COMPLETED","Provider-confirmed delivery is required");
 if(!order?.id||order.id!==dispatch.orderId||order.tenantId!==dispatch.tenantId)fail("DELIVERY_ORDER_SCOPE_MISMATCH","Order and dispatch must match tenant and source");
 if(!providerSettlement||providerSettlement.status!=="settled"||providerSettlement.dispatchId!==dispatch.id)fail("CARRIER_SETTLEMENT_NOT_FINAL","Carrier settlement must be final");
 if(!financePosting||financePosting.status!=="posted"||financePosting.reconciled!==true)fail("DELIVERY_FINANCE_NOT_RECONCILED","Finance posting must be reconciled");
 const customerCharge=money(dispatch.customerDeliveryChargeIdr??0,"customerDeliveryChargeIdr"),cod=money(dispatch.codCollectedIdr??0,"codCollectedIdr"),subsidy=money(expectedSubsidyIdr,"expectedSubsidyIdr"),actualFee=money(providerSettlement.actualFeeIdr,"actualFeeIdr"),settled=money(providerSettlement.settledAmountIdr,"settledAmountIdr");
 if(settled!==actualFee)fail("CARRIER_SETTLEMENT_AMOUNT_MISMATCH","Settlement differs from actual carrier fee");
 if(money(financePosting.carrierFeeIdr,"finance carrier fee")!==actualFee||money(financePosting.customerChargeIdr,"finance customer charge")!==customerCharge||money(financePosting.subsidyIdr,"finance subsidy")!==subsidy)fail("DELIVERY_FINANCE_AMOUNT_MISMATCH","Finance delivery amounts do not match source evidence");
 if(cod>0&&order.paymentMethod!=="cod")fail("COD_METHOD_MISMATCH","COD collection is only valid for COD orders");
 if(order.paymentMethod==="cod"&&cod!==money(order.codDueIdr,"codDueIdr"))fail("COD_COLLECTION_MISMATCH","COD collection must equal due amount");
 return Object.freeze({dispatchId:dispatch.id,actualFeeIdr:actualFee,customerChargeIdr:customerCharge,subsidyIdr:subsidy,codCollectedIdr:cod,status:"reconciled"});
}
