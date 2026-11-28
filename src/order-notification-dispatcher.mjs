/** Consent-aware notification outbox dispatch contract. */
export function prepareOrderNotification({orderId,tenantId,customerId,eventId,eventType,channel,destination,consent,preferences,templateVersion}){
 if(!orderId||!tenantId||!customerId||!eventId||!eventType||!templateVersion)throw new Error("ORDER_NOTIFICATION_CONTEXT_REQUIRED");
 if(!["whatsapp","email","sms","push"].includes(channel))throw new Error("ORDER_NOTIFICATION_CHANNEL_INVALID");
 if(typeof destination!=="string"||!destination.trim())throw new Error("ORDER_NOTIFICATION_DESTINATION_REQUIRED");
 if(consent?.[channel]!=="granted"||preferences?.[channel]===false)return Object.freeze({dispatch:false,reason:"customer_opt_out",idempotency_key:tenantId+":"+orderId+":"+eventId+":"+channel});
 return Object.freeze({dispatch:true,tenant_id:tenantId,order_id:orderId,customer_id:customerId,event_id:eventId,event_type:eventType,channel,destination:destination.trim(),template_version:templateVersion,idempotency_key:tenantId+":"+orderId+":"+eventId+":"+channel});
}
export function evaluateNotificationAttempt({attemptCount,maxAttempts,providerResult,providerMessageId,nextAttemptAt}){
 if(!Number.isInteger(attemptCount)||attemptCount<0||!Number.isInteger(maxAttempts)||maxAttempts<1)throw new Error("ORDER_NOTIFICATION_ATTEMPTS_INVALID");
 if(providerResult==="delivered"&&providerMessageId)return Object.freeze({status:"delivered",provider_message_id:providerMessageId,next_attempt_at:null});
 if(attemptCount+1>=maxAttempts)return Object.freeze({status:"dead_letter",provider_message_id:providerMessageId||null,next_attempt_at:null});
 if(!Number.isFinite(Date.parse(nextAttemptAt)))throw new Error("ORDER_NOTIFICATION_RETRY_TIME_INVALID");
 return Object.freeze({status:"retry",provider_message_id:providerMessageId||null,next_attempt_at:nextAttemptAt});
}
