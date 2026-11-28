/**
 * Consent-first campaign dispatch contract. A provider adapter is injectable
 * only after its contract, credentials and webhook scheme have been approved.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export async function dispatchConsentedCampaignMessage({campaign,customer,consent,outbox,provider,claimOutbox,sendProvider,recordProviderAcceptance,scheduleRetry,now=new Date().toISOString()}) {
 if(!campaign?.id||campaign.status!=="approved"||!campaign.version)fail("CAMPAIGN_NOT_APPROVED","Campaign must be approved and versioned");
 if(!customer?.id||!customer.tenantId||!customer.destination)fail("CAMPAIGN_CUSTOMER_DESTINATION_REQUIRED","Tenant-scoped customer and destination are required");
 if(campaign.tenantId!==customer.tenantId)fail("CAMPAIGN_TENANT_MISMATCH","Campaign and customer must belong to the same tenant");
 if(!consent||consent.status!=="granted"||consent.channel!==campaign.channel||consent.purpose!==campaign.purpose||!consent.recordedAt||consent.withdrawnAt||(consent.expiresAt&&Date.parse(consent.expiresAt)<=Date.parse(now))) return Object.freeze({status:"suppressed",reason:"CONSENT_NOT_GRANTED_OR_EXPIRED"});
 if(consent.customerId!==customer.id||consent.tenantId!==customer.tenantId)fail("CONSENT_SCOPE_MISMATCH","Consent must belong to this customer and tenant");
 if(customer.unsubscribedAt&&Date.parse(customer.unsubscribedAt)<=Date.parse(now))return Object.freeze({status:"suppressed",reason:"UNSUBSCRIBED"});
 if(!provider?.approved||!provider.id||!provider.contractVersion||typeof sendProvider!=="function")fail("APPROVED_CAMPAIGN_PROVIDER_REQUIRED","A real approved provider adapter and versioned contract are required");
 const idempotencyKey=`campaign:${campaign.tenantId}:${campaign.id}:${campaign.version}:${customer.id}:${campaign.channel}`;
 if(typeof claimOutbox!=="function"||typeof recordProviderAcceptance!=="function")fail("CAMPAIGN_OUTBOX_ADAPTER_REQUIRED","Durable idempotent outbox adapters are required");
 const claim=await claimOutbox({tenantId:campaign.tenantId,campaignId:campaign.id,customerId:customer.id,idempotencyKey,providerId:provider.id});
 if(claim?.status==="accepted"||claim?.status==="delivered")return Object.freeze({status:"duplicate",idempotencyKey,providerMessageId:claim.providerMessageId??null});
 if(!claim?.claimed||!claim.outboxId)fail("CAMPAIGN_OUTBOX_CLAIM_FAILED","Message could not be claimed atomically");
 try {
  const response=await sendProvider({providerId:provider.id,contractVersion:provider.contractVersion,channel:campaign.channel,destination:customer.destination,content:campaign.content,idempotencyKey});
  if(!response?.accepted||!response.providerMessageId)fail("PROVIDER_ACCEPTANCE_UNVERIFIED","Provider did not return a verifiable accepted message identity");
  await recordProviderAcceptance({outboxId:claim.outboxId,providerId:provider.id,providerMessageId:response.providerMessageId,acceptedAt:now});
  return Object.freeze({status:"accepted",outboxId:claim.outboxId,providerMessageId:response.providerMessageId,idempotencyKey});
 } catch(error) {
  if(typeof scheduleRetry==="function")await scheduleRetry({outboxId:claim.outboxId,reasonCode:error.code??"PROVIDER_ERROR"});
  error.campaignOutboxId=claim.outboxId;throw error;
 }
}
export function calculateCampaignRoi({campaignCostIdr,attributedOrders,attributionWindowStart,attributionWindowEnd}) {
 if(!Number.isSafeInteger(campaignCostIdr)||campaignCostIdr<0)fail("CAMPAIGN_COST_INVALID","Campaign cost must be a non-negative IDR integer");
 const start=Date.parse(attributionWindowStart),end=Date.parse(attributionWindowEnd);
 if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start)fail("CAMPAIGN_ATTRIBUTION_WINDOW_INVALID","A bounded attribution window is required");
 let netSales=0,count=0;
 for(const order of attributedOrders??[]){
  if(order.financialCloseStatus!=="reconciled"||!order.attributionId||!order.orderId||Date.parse(order.closedAt)<start||Date.parse(order.closedAt)>end)continue;
  if(!Number.isSafeInteger(order.eligibleNetSalesIdr)||order.eligibleNetSalesIdr<0)fail("ATTRIBUTED_NET_SALES_INVALID","Attributed order must carry reconciled eligible net sales");
  netSales+=order.eligibleNetSalesIdr;count++;
 }
 if(!Number.isSafeInteger(netSales))fail("CAMPAIGN_ROI_OVERFLOW","Attributed sales exceed safe integer range");
 return Object.freeze({attributedOrderCount:count,attributedNetSalesIdr:netSales,campaignCostIdr,netSalesToCostRatio:campaignCostIdr===0?null:netSales/campaignCostIdr,roiEligible:count>0&&campaignCostIdr>0});
}


/** Apply a provider delivery receipt only after provider-specific signature verification. */
export function applyCampaignProviderReceipt({outbox,receipt,signatureVerified,existingEvent,maxAttempts=5}) {
 if(signatureVerified!==true)fail("CAMPAIGN_WEBHOOK_SIGNATURE_INVALID","Provider receipt signature must be verified over the raw request body");
 if(!outbox?.id||!receipt?.eventId||!receipt?.providerMessageId||!receipt?.payloadHash)fail("CAMPAIGN_RECEIPT_IDENTITY_REQUIRED","Outbox, event, provider message and payload hash required");
 if(existingEvent){if(existingEvent.payloadHash!==receipt.payloadHash)fail("CAMPAIGN_EVENT_ID_COLLISION","Same provider event id has a different payload");return Object.freeze({action:"duplicate",status:existingEvent.status});}
 const terminal=new Set(["delivered","bounced","failed","unsubscribed"]);const transient=new Set(["queued","sent","accepted","deferred","temporary_failure"]);
 if(!terminal.has(receipt.status)&&!transient.has(receipt.status))fail("CAMPAIGN_RECEIPT_STATUS_INVALID","Unsupported provider receipt state");
 const attempt=Number.isSafeInteger(outbox.attemptCount)?outbox.attemptCount:0;
 const retry=receipt.status==="temporary_failure"||receipt.status==="deferred";
 return Object.freeze({action:"apply",outboxId:outbox.id,eventId:receipt.eventId,status:receipt.status,retryScheduled:retry&&attempt<maxAttempts,nextAttempt:retry&&attempt<maxAttempts?attempt+1:null,deadLetter:retry&&attempt>=maxAttempts});
}

/** Unsubscribe callback must be signature-verified and persisted as a consent withdrawal event. */
export function applyCampaignUnsubscribe({customer,consent,providerEvent,signatureVerified}) {
 if(signatureVerified!==true)fail("UNSUBSCRIBE_SIGNATURE_INVALID","Unsubscribe callback signature must be verified");
 if(!customer?.id||!consent?.id||consent.customerId!==customer.id||consent.tenantId!==customer.tenantId)fail("UNSUBSCRIBE_SCOPE_INVALID","Customer and consent scope do not match");
 if(!providerEvent?.eventId||!providerEvent.occurredAt)fail("UNSUBSCRIBE_EVENT_REQUIRED","Provider unsubscribe event identity and timestamp required");
 return Object.freeze({tenantId:customer.tenantId,customerId:customer.id,consentId:consent.id,eventId:providerEvent.eventId,withdrawnAt:providerEvent.occurredAt,nextConsentStatus:"withdrawn",requiresAppendOnlyConsentEvent:true});
}
