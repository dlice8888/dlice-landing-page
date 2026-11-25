/**
 * Usage worker consumes only authoritative committed business events.
 * It meters idempotently; it never creates synthetic usage or bypasses quotas.
 */
export async function runSaasUsageMeteringBatch({events,adapter}){
 if(!Array.isArray(events))throw Object.assign(new Error("Committed usage events are required"),{code:"SAAS_EVENTS_REQUIRED"});
 if(typeof adapter?.recordUsage!=="function")throw Object.assign(new Error("SaaS usage adapter required"),{code:"SAAS_ADAPTER_REQUIRED"});
 const results=[];
 for(const event of events){
  try{
   if(event?.committed!==true)throw Object.assign(new Error("Usage source must be authoritatively committed"),{code:"SAAS_SOURCE_NOT_COMMITTED"});
   const result=await adapter.recordUsage({tenantId:event.tenantId,entitlementKey:event.entitlementKey,quantity:event.quantity,
    sourceEntity:event.sourceEntity,sourceId:event.sourceId,idempotencyKey:event.idempotencyKey,
    metadata:event.metadata||{},at:event.occurredAt,actorId:event.actorId});
   results.push({sourceId:event.sourceId,status:result.duplicate?"duplicate":"recorded",usageEventId:result.usage_event_id});
  }catch(error){results.push({sourceId:event?.sourceId||null,status:"failed",errorCode:error?.code||"SAAS_METERING_FAILED"});}
 }
 return Object.freeze({status:results.every(x=>x.status!=="failed")?"complete":"partial",eventCount:events.length,results:Object.freeze(results.map(Object.freeze))});
}

export async function runSaasInvoiceIssuanceBatch({subscriptions,adapter,actorId,dueAt,taxIdr=0,runKey}){
 if(!Array.isArray(subscriptions))throw Object.assign(new Error("Subscription batch is required"),{code:"SAAS_SUBSCRIPTIONS_REQUIRED"});
 if(typeof adapter?.issueInvoice!=="function")throw Object.assign(new Error("SaaS invoice adapter required"),{code:"SAAS_ADAPTER_REQUIRED"});
 if(typeof actorId!=="string"||!actorId||typeof runKey!=="string"||!runKey)throw Object.assign(new Error("Actor and run key are required"),{code:"SAAS_INPUT_REQUIRED"});
 const results=[];
 for(const sub of subscriptions){
  try{
   if(!["active","past_due"].includes(sub?.status))throw Object.assign(new Error("Only billable subscriptions can be invoiced"),{code:"SAAS_SUBSCRIPTION_NOT_BILLABLE"});
   const key=(runKey+":"+sub.id+":"+String(sub.current_period_start)).slice(0,120);
   const invoice=await adapter.issueInvoice({tenantId:sub.tenant_id,subscriptionId:sub.id,
    periodStart:String(sub.current_period_start).slice(0,10),periodEnd:String(sub.current_period_end).slice(0,10),
    taxIdr,dueAt,idempotencyKey:key,actorId});
   results.push({subscriptionId:sub.id,status:invoice.status||"issued",invoiceId:invoice.invoice_id||null});
  }catch(error){results.push({subscriptionId:sub?.id||null,status:"failed",errorCode:error?.code||"SAAS_INVOICE_FAILED"});}
 }
 return Object.freeze({status:results.every(x=>x.status!=="failed")?"complete":"partial",invoiceCount:results.length,results:Object.freeze(results.map(Object.freeze))});
}
