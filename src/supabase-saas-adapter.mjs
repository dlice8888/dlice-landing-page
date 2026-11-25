/**
 * Tenant SaaS adapter. All writes delegate to a single database RPC so
 * subscription, usage, invoice and offboarding state changes remain atomic.
 */
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())throw Object.assign(new Error(k+" is required"),{code:"SAAS_INPUT_REQUIRED"});return v.trim();};
export function createSupabaseSaasAdapter(client){
 if(typeof client?.rpc!=="function")throw Object.assign(new Error("Supabase RPC client required"),{code:"SAAS_RPC_CLIENT_REQUIRED"});
 const call=async(name,args)=>{const {data,error}=await client.rpc(name,args);if(error){const e=new Error(error.message||"SaaS RPC failed");e.code=error.code||"SAAS_RPC_FAILED";throw e;}return data;};
 return Object.freeze({
  checkEntitlement(i){return call("saas_check_entitlement",{p_tenant_id:req(i.tenantId,"tenantId"),p_entitlement_key:req(i.entitlementKey,"entitlementKey"),p_quantity:i.quantity??1,p_at:req(i.at,"at")});},
  recordUsage(i){return call("saas_record_usage",{p_tenant_id:req(i.tenantId,"tenantId"),p_entitlement_key:req(i.entitlementKey,"entitlementKey"),p_quantity:i.quantity,p_source_entity:req(i.sourceEntity,"sourceEntity"),p_source_id:req(i.sourceId,"sourceId"),p_idempotency_key:req(i.idempotencyKey,"idempotencyKey"),p_metadata:i.metadata||{},p_at:req(i.at,"at"),p_actor_user_id:req(i.actorId,"actorId")});},
  startTrial(i){return call("saas_start_trial",{p_tenant_id:req(i.tenantId,"tenantId"),p_plan_version_id:req(i.planVersionId,"planVersionId"),p_trial_days:i.trialDays,p_actor_user_id:req(i.actorId,"actorId")});},
  cancelSubscription(i){return call("saas_cancel_subscription",{p_tenant_id:req(i.tenantId,"tenantId"),p_subscription_id:req(i.subscriptionId,"subscriptionId"),p_reason:req(i.reason,"reason"),p_actor_user_id:req(i.actorId,"actorId")});},
  requestOffboarding(i){return call("saas_request_offboarding",{p_tenant_id:req(i.tenantId,"tenantId"),p_reason:req(i.reason,"reason"),p_idempotency_key:req(i.idempotencyKey,"idempotencyKey"),p_actor_user_id:req(i.actorId,"actorId")});},
  approveOffboarding(i){return call("saas_approve_offboarding",{p_request_id:req(i.requestId,"requestId"),p_actor_user_id:req(i.actorId,"actorId"),p_retention_days:i.retentionDays,p_legal_hold:i.legalHold===true,p_legal_hold_reference:i.legalHoldReference||null});},
  completeOffboarding(i){return call("saas_complete_offboarding",{p_request_id:req(i.requestId,"requestId"),p_actor_user_id:req(i.actorId,"actorId"),p_completion_evidence:req(i.completionEvidence,"completionEvidence")});},
  issueInvoice(i){return call("saas_issue_invoice",{p_tenant_id:req(i.tenantId,"tenantId"),p_subscription_id:req(i.subscriptionId,"subscriptionId"),p_period_start:req(i.periodStart,"periodStart"),p_period_end:req(i.periodEnd,"periodEnd"),p_tax_idr:i.taxIdr??0,p_due_at:req(i.dueAt,"dueAt"),p_idempotency_key:req(i.idempotencyKey,"idempotencyKey"),p_actor_user_id:req(i.actorId,"actorId")});},
  recordInvoicePayment(i){return call("saas_record_invoice_payment",{p_tenant_id:req(i.tenantId,"tenantId"),p_invoice_id:req(i.invoiceId,"invoiceId"),p_provider:req(i.provider,"provider"),p_provider_reference:req(i.providerReference,"providerReference"),p_amount_idr:i.amountIdr,p_status:req(i.status,"status"),p_settled_at:i.settledAt||null,p_actor_user_id:req(i.actorId,"actorId")});},
 });
}
