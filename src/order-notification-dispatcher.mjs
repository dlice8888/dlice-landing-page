/** D03-F10: consent-aware notification outbox worker with idempotent retries and dead letters. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("ORDER_NOTIFICATION_ADAPTER_REQUIRED",k);return d[k];};
export async function dispatchOrderNotifications(input,deps){
 const workerId=typeof input?.workerId==="string"&&input.workerId.trim()?input.workerId.trim():fail("ORDER_NOTIFICATION_WORKER_REQUIRED","workerId");
 const limit=input.limit??20;if(!Number.isSafeInteger(limit)||limit<1||limit>100)fail("ORDER_NOTIFICATION_LIMIT_INVALID","limit must be 1..100");
 const results=[];
 for(let i=0;i<limit;i++){
  const event=await fn(deps,"claimNotificationOutboxAtomically")({workerId,leaseSeconds:60});
  if(!event)break;
  if(!event.id||!event.idempotencyKey||!event.orderId)fail("ORDER_NOTIFICATION_EVENT_INVALID","Outbox event is incomplete");
  if(event.consent!==true){await fn(deps,"completeNotificationAttemptAtomically")({eventId:event.id,workerId,status:"suppressed",reason:"customer_opt_out"});results.push({eventId:event.id,status:"suppressed"});continue;}
  try{
   const sent=await fn(deps,"sendWhatsAppNotification")({to:event.recipient,message:event.message,idempotencyKey:event.idempotencyKey});
   if(!sent?.providerMessageId)fail("ORDER_NOTIFICATION_PROVIDER_INVALID","Provider did not return message ID");
   await fn(deps,"completeNotificationAttemptAtomically")({eventId:event.id,workerId,status:"sent",providerMessageId:sent.providerMessageId});
   results.push({eventId:event.id,status:"sent",providerMessageId:sent.providerMessageId});
  }catch(error){
   const failure=await fn(deps,"recordNotificationFailureAtomically")({eventId:event.id,workerId,errorCode:error?.code??"provider_error",retryable:error?.retryable!==false});
   results.push({eventId:event.id,status:failure?.status??"retry_pending"});
  }
 }
 return Object.freeze({processed:results.length,results});
}
