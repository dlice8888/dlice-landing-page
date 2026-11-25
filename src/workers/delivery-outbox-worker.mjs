/**
 * Provider outbox worker. The caller supplies provider adapters and secret retrieval.
 * No provider request is sent unless an approved API-mode config and secret are present.
 */
export async function runDeliveryOutboxBatch({adapter,providerAdapters,loadSecret,workerId,limit=10}){
 if(!adapter||typeof adapter.claimOutboxBatch!=="function"||typeof adapter.getOutboxJobContext!=="function"||
  typeof adapter.confirmProviderBooking!=="function"||typeof adapter.finishOutbox!=="function")
  throw Object.assign(new Error("Delivery worker adapter is incomplete"),{code:"DELIVERY_WORKER_ADAPTER_REQUIRED"});
 if(typeof loadSecret!=="function")throw Object.assign(new Error("Secret resolver is required"),{code:"DELIVERY_SECRET_RESOLVER_REQUIRED"});
 const jobs=await adapter.claimOutboxBatch({workerId,limit});
 const results=[];
 for(const job of jobs||[]){
  try{
   if(job.event_type!=="book")throw Object.assign(new Error("Unsupported delivery outbox event"),{code:"DELIVERY_OUTBOX_EVENT_UNSUPPORTED"});
   const context=await adapter.getOutboxJobContext({outboxId:job.id,workerId});
   const config=context?.provider_config;
   if(!config||config.integration_mode!=="api")throw Object.assign(new Error("Approved API-mode provider config required"),{code:"DELIVERY_PROVIDER_API_CONFIG_REQUIRED"});
   const secret=await loadSecret(config.credential_secret_reference);
   if(typeof secret!=="string"||!secret)throw Object.assign(new Error("Provider secret unavailable"),{code:"DELIVERY_PROVIDER_SECRET_UNAVAILABLE"});
   const provider=providerAdapters?.[config.provider_key];
   if(typeof provider?.book!=="function")throw Object.assign(new Error("Provider adapter unavailable"),{code:"DELIVERY_PROVIDER_ADAPTER_UNAVAILABLE"});
   const result=await provider.book({dispatch:context.dispatch,quote:context.quote,order:context.order,secret,idempotencyKey:job.idempotency_key});
   if(!result?.success){
    await adapter.confirmProviderBooking({tenantId:job.tenant_id,dispatchId:job.dispatch_id,succeeded:false,errorCode:result?.errorCode||"PROVIDER_BOOKING_FAILED",actorId:context.dispatch.created_by});
    const finished=await adapter.finishOutbox({outboxId:job.id,workerId,succeeded:false,errorCode:result?.errorCode||"PROVIDER_BOOKING_FAILED",retryAfterSeconds:result?.retryAfterSeconds||60});
    results.push({outboxId:job.id,status:finished.status,errorCode:result?.errorCode||"PROVIDER_BOOKING_FAILED"});
    continue;
   }
   await adapter.confirmProviderBooking({tenantId:job.tenant_id,dispatchId:job.dispatch_id,succeeded:true,bookingReference:result.bookingReference,trackingNumber:result.trackingNumber||null,trackingUrl:result.trackingUrl||null,actorId:context.dispatch.created_by});
   const finished=await adapter.finishOutbox({outboxId:job.id,workerId,succeeded:true});
   results.push({outboxId:job.id,status:finished.status,dispatchId:job.dispatch_id});
  }catch(error){
   const finished=await adapter.finishOutbox({outboxId:job.id,workerId,succeeded:false,errorCode:error?.code||"DELIVERY_WORKER_FAILED",retryAfterSeconds:60});
   results.push({outboxId:job.id,status:finished.status,errorCode:error?.code||"DELIVERY_WORKER_FAILED"});
  }
 }
 return results;
}
