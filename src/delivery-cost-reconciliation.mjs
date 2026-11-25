/**
 * Separates customer charge, merchant subsidy, courier cost and COD remittance.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
const idr=(v,k)=>{if(!Number.isSafeInteger(v)||v<0)fail("DELIVERY_AMOUNT_INVALID",k);return v;};
export function reconcileDeliveryEconomics({dispatchId,tenantId,branchId,customerFeeIdr,merchantSubsidyIdr,actualCourierFeeIdr,codCollectedIdr=0,codRemittedIdr=0,providerSettlementIdr,providerFeeIdr=0,settlementStatus}) {
 if(!dispatchId||!tenantId||!branchId)fail("DELIVERY_SOURCE_REQUIRED","Dispatch, tenant and branch identity are required");
 const customerFee=idr(customerFeeIdr,"customerFeeIdr"),subsidy=idr(merchantSubsidyIdr,"merchantSubsidyIdr"),courier=idr(actualCourierFeeIdr,"actualCourierFeeIdr");
 const codCollected=idr(codCollectedIdr,"codCollectedIdr"),codRemitted=idr(codRemittedIdr,"codRemittedIdr"),settlement=idr(providerSettlementIdr,"providerSettlementIdr"),fee=idr(providerFeeIdr,"providerFeeIdr");
 if(codRemitted>codCollected)fail("COD_REMITTANCE_EXCEEDS_COLLECTION","Courier cannot remit more COD than collected");
 const funded=customerFee+subsidy;
 const courierVarianceIdr=courier-funded;
 const codOutstandingIdr=codCollected-codRemitted;
 const expectedSettlement=courier-fee;
 const settlementVarianceIdr=settlement-expectedSettlement;
 const reconciled=settlementStatus==="reconciled"&&codOutstandingIdr===0&&courierVarianceIdr===0&&settlementVarianceIdr===0;
 return Object.freeze({dispatchId,tenantId,branchId,customerFeeIdr:customerFee,merchantSubsidyIdr:subsidy,actualCourierFeeIdr:courier,courierFundingVarianceIdr:courierVarianceIdr,codCollectedIdr:codCollected,codRemittedIdr:codRemitted,codOutstandingIdr,providerSettlementIdr:settlement,providerFeeIdr:fee,settlementVarianceIdr,status:reconciled?"reconciled":"exception"});
}
