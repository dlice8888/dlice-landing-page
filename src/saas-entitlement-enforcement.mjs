/** Server-side entitlement and quota gate. Call before authoritative operation. */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
export function enforceTenantEntitlement({tenant,subscription,entitlement,usage,requested=1,now=Date.now()}) {
 if(!tenant?.id||tenant.status!=="active")fail("TENANT_NOT_ACTIVE","Tenant must be active");
 if(!subscription||subscription.tenantId!==tenant.id||subscription.status!=="active"||!Number.isFinite(Date.parse(subscription.currentPeriodEnd))||Date.parse(subscription.currentPeriodEnd)<=now)fail("SUBSCRIPTION_NOT_ACTIVE","Subscription is not active");
 if(!entitlement?.key||entitlement.enabled!==true||entitlement.tenantId!==tenant.id)fail("ENTITLEMENT_DISABLED","Entitlement is disabled");
 if(!Number.isSafeInteger(requested)||requested<=0||!Number.isSafeInteger(entitlement.quota)||entitlement.quota<0||!Number.isSafeInteger(usage?.committedQuantity)||usage.committedQuantity<0)fail("QUOTA_INPUT_INVALID","Quota and committed usage must be valid integers");
 if(usage.committedQuantity+requested>entitlement.quota)fail("ENTITLEMENT_QUOTA_EXCEEDED","Operation exceeds committed tenant quota");
 return Object.freeze({allowed:true,tenantId:tenant.id,entitlementKey:entitlement.key,remainingAfterCommit:entitlement.quota-usage.committedQuantity-requested,periodEnd:subscription.currentPeriodEnd});
}
export function evaluateTenantSuspension({tenant,openInvoices,settlements,gracePeriodExpired,approvedBy}) {
 if(!tenant?.id||tenant.status!=="active")fail("ACTIVE_TENANT_REQUIRED","Tenant must be active before suspension");
 if(!gracePeriodExpired||!approvedBy)fail("SUSPENSION_APPROVAL_REQUIRED","Expired grace period and authorized approval required");
 if((openInvoices??[]).some(i=>i.status!=="paid"&&i.status!=="void"))fail("UNPAID_INVOICES_BLOCK_SUSPENSION","Outstanding invoices require resolution");
 if((settlements??[]).some(s=>s.status!=="reconciled"))fail("SETTLEMENTS_NOT_RECONCILED","Billing settlements must be reconciled");
 return Object.freeze({tenantId:tenant.id,eligible:true,nextStatus:"suspended"});
}
