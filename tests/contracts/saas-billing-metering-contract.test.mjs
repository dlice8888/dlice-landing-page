import test from "node:test";
import assert from "node:assert/strict";
import { createSupabaseSaasAdapter } from "../../src/supabase-saas-adapter.mjs";
import { runSaasUsageMeteringBatch, runSaasInvoiceIssuanceBatch } from "../../src/workers/saas-billing-metering-worker.mjs";
import { readFileSync } from "node:fs";
const read=p=>readFileSync(new URL(p,import.meta.url),"utf8");
const sql=read("../../docs/implementation/sql/SAAS_TENANT_BILLING_SCHEMA_DRAFT.sql");
const edge=read("../../supabase/functions/dlice-orders/index.ts");
const erp=read("../../erp.html");

test("SaaS adapter uses atomic RPCs for lifecycle, usage, billing and offboarding",async()=>{
 const calls=[];const adapter=createSupabaseSaasAdapter({rpc:async(name,args)=>{calls.push({name,args});return {data:{ok:true},error:null}}});
 await adapter.startTrial({tenantId:"t",planVersionId:"p",trialDays:14,actorId:"u"});
 await adapter.cancelSubscription({tenantId:"t",subscriptionId:"s",reason:"customer request",actorId:"u"});
 await adapter.recordUsage({tenantId:"t",entitlementKey:"orders",quantity:1,sourceEntity:"orders",sourceId:"o-1",idempotencyKey:"usage-key-123",metadata:{},at:"2026-01-01T00:00:00Z",actorId:"u"});
 await adapter.issueInvoice({tenantId:"t",subscriptionId:"s",periodStart:"2026-01-01",periodEnd:"2026-02-01",taxIdr:0,dueAt:"2026-02-10T00:00:00Z",idempotencyKey:"invoice-key-123",actorId:"u"});
 assert.deepEqual(calls.map(x=>x.name),["saas_start_trial","saas_cancel_subscription","saas_record_usage","saas_issue_invoice"]);
 assert.equal(calls[2].args.p_actor_user_id,"u");
});

test("usage worker accepts only committed business events and records idempotently",async()=>{
 const calls=[];const adapter={recordUsage:async x=>{calls.push(x);return {usage_event_id:"u-1",duplicate:false}}};
 const result=await runSaasUsageMeteringBatch({adapter,events:[
  {committed:true,tenantId:"t",entitlementKey:"orders",quantity:1,sourceEntity:"orders",sourceId:"o-1",idempotencyKey:"usage-123456",occurredAt:"2026-01-01T00:00:00Z",actorId:"worker"},
  {committed:false,tenantId:"t",entitlementKey:"orders",quantity:1,sourceEntity:"orders",sourceId:"o-2",idempotencyKey:"usage-123457",occurredAt:"2026-01-01T00:00:00Z",actorId:"worker"}
 ]});
 assert.equal(result.status,"partial");assert.equal(result.results[0].status,"recorded");assert.equal(result.results[1].errorCode,"SAAS_SOURCE_NOT_COMMITTED");assert.equal(calls.length,1);
});

test("invoice worker issues only for active or past-due subscriptions",async()=>{
 const calls=[];const adapter={issueInvoice:async x=>{calls.push(x);return {status:"issued",invoice_id:"inv-1"}}};
 const result=await runSaasInvoiceIssuanceBatch({adapter,actorId:"u",dueAt:"2026-02-10T00:00:00Z",runKey:"billing-run-2026",subscriptions:[
  {id:"s1",tenant_id:"t",status:"active",current_period_start:"2026-01-01T00:00:00Z",current_period_end:"2026-02-01T00:00:00Z"},
  {id:"s2",tenant_id:"t",status:"trialing",current_period_start:"2026-01-01T00:00:00Z",current_period_end:"2026-02-01T00:00:00Z"}
 ]});
 assert.equal(result.status,"partial");assert.equal(calls.length,1);assert.equal(result.results[1].errorCode,"SAAS_SUBSCRIPTION_NOT_BILLABLE");
});

test("SaaS entitlement respects trial/grace expiry and metering is idempotent and audited",()=>{
 assert.match(sql,/trial_ends_at is null or trial_ends_at>p_at/);
 assert.match(sql,/grace_ends_at is not null and grace_ends_at>p_at/);
 assert.match(sql,/USAGE_IDEMPOTENCY_KEY_PAYLOAD_MISMATCH/);
 assert.match(sql,/saas\.usage\.recorded/);
 assert.match(sql,/revoke all on function public\.saas_record_usage\(uuid,text,bigint,text,text,text,jsonb,timestamptz\) from public,anon,authenticated,service_role/);
 assert.match(sql,/grant execute on function public\.saas_record_usage\(uuid,text,bigint,text,text,text,jsonb,timestamptz,uuid\) to service_role/);
});

test("SaaS billing and offboarding RPCs enforce separation of duties and settlement evidence",()=>{
 for(const fn of ["saas_start_trial","saas_cancel_subscription","saas_request_offboarding","saas_issue_invoice","saas_record_invoice_payment","saas_complete_offboarding"])
  assert.match(sql,new RegExp("create or replace function public\\."+fn));
 assert.match(sql,/INDEPENDENT_OFFBOARDING_APPROVER_REQUIRED/);
 assert.match(sql,/INDEPENDENT_OFFBOARDING_COMPLETER_AND_EVIDENCE_REQUIRED/);
 assert.match(sql,/SAAS_INVOICE_OVERPAYMENT/);
 assert.match(sql,/SAAS_PAYMENT_STATUS_TRANSITION_INVALID/);
 assert.match(sql,/if not p_legal_hold then[\s\S]*status='suspended'/);
 assert.match(sql,/SAAS_TRIAL_NOT_EXPIRED/);
});

test("SaaS Edge uses RPCs instead of direct lifecycle mutations and scopes invoices by tenant",()=>{
 const start=edge.indexOf('const saasActions=new Set(['),end=edge.indexOf('const biExecutiveActions=new Set([',start);
 const block=edge.slice(start,end);
 assert.match(block,/admin\.rpc\("saas_start_trial"/);
 assert.match(block,/admin\.rpc\("saas_cancel_subscription"/);
 assert.match(block,/admin\.rpc\("saas_request_offboarding"/);
 assert.match(block,/admin\.rpc\("saas_issue_invoice"/);
 assert.match(block,/eq\("tenant_id",tenantId\)/);
 assert.doesNotMatch(block,/from\("saas_tenant_subscriptions"\)\.insert/);
 assert.doesNotMatch(block,/from\("saas_tenant_subscriptions"\)\.update/);
});

test("SaaS ERP UI exposes invoice issuance, payment evidence and retention completion",()=>{
 assert.match(erp,/id="saasInvoiceForm"/);
 assert.match(erp,/id="saasInvoiceList"/);
 assert.match(erp,/erp-saas-issue-invoice/);
 assert.match(erp,/saas_invoice_payments/);
 assert.match(erp,/data-complete-offboarding/);
});
