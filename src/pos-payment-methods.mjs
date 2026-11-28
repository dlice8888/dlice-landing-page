/** Tender validation and provider confirmation invariants. */
const METHODS=new Set(["cash","qris","card","bank_transfer"]);
export function validateTenderAllocations({saleTotalIdr,tenders,minTenders=1,maxTenders=5}) {
  if(!Number.isSafeInteger(saleTotalIdr)||saleTotalIdr<=0)throw new Error("sale_total_invalid");
  if(!Array.isArray(tenders)||tenders.length<minTenders||tenders.length>maxTenders)throw new Error("tender_count_invalid");
  const methods=new Set();
  const normalized=tenders.map(t=>{
    if(!METHODS.has(t.method)||methods.has(t.method))throw new Error("tender_method_invalid_or_duplicate");
    methods.add(t.method);
    if(!Number.isSafeInteger(t.amount_idr)||t.amount_idr<=0)throw new Error("tender_amount_invalid");
    return Object.freeze({method:t.method,amount_idr:t.amount_idr,provider_reference:typeof t.provider_reference==="string"?t.provider_reference:null});
  });
  const allocated=normalized.reduce((s,t)=>s+t.amount_idr,0);
  if(allocated!==saleTotalIdr)throw new Error(allocated>saleTotalIdr?"tender_overpayment":"tender_underpayment");
  return Object.freeze({sale_total_idr:saleTotalIdr,allocated_idr:allocated,tenders:Object.freeze(normalized)});
}
export function assertProviderPaymentConfirmation({method,signatureValid,replayDetected,providerReference,amountIdr,expectedAmountIdr,providerStatus}) {
  if(!["qris","card","bank_transfer"].includes(method))throw new Error("provider_method_invalid");
  if(signatureValid!==true)throw new Error("provider_signature_invalid");
  if(replayDetected===true)throw new Error("provider_event_replayed");
  if(typeof providerReference!=="string"||!providerReference.trim())throw new Error("provider_reference_required");
  if(!Number.isSafeInteger(amountIdr)||amountIdr!==expectedAmountIdr)throw new Error("provider_amount_mismatch");
  if(providerStatus!=="succeeded")throw new Error("provider_payment_not_succeeded");
  return Object.freeze({status:"paid",provider_reference:providerReference.trim()});
}
export function assertPaymentStatusMutation({requestedStatus,source,proofVerified=false}) {
  if(requestedStatus==="paid"&&(source!=="trusted_provider"||proofVerified!==true))throw new Error("client_cannot_mark_paid");
  if(!["pending","paid","failed","cancelled","refunded"].includes(requestedStatus))throw new Error("payment_status_invalid");
  return true;
}
